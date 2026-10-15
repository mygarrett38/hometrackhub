import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/home_item_catalog.dart';
import '../../../models/home_item_category.dart';
import '../../../services/device_discovery_service.dart';
import '../../../state/home_item_controller.dart';
import '../../../state/settings_controller.dart';
import '../../widgets/category_icon.dart';
import 'home_item_form_screen.dart';

/// The stages the scan can be in.
enum _ScanState { checkingNetwork, scanning, finished, failed }

/// Scans the home network and Bluetooth for smart devices and lets the user
/// add them as home items.
class DeviceDiscoveryScreen extends StatefulWidget {
  const DeviceDiscoveryScreen({super.key});

  @override
  State<DeviceDiscoveryScreen> createState() => _DeviceDiscoveryScreenState();
}

class _DeviceDiscoveryScreenState extends State<DeviceDiscoveryScreen> {
  /// How many devices are shown at first, and how many more each tap of
  /// "Load more" reveals. Busy networks, like public Wi-Fi, can have
  /// thousands of devices, so only the most relevant few are listed.
  static const _pageSize = 8;

  /// Devices found so far, keyed by [DiscoveredDevice.id] so that later,
  /// more detailed copies of a device replace earlier ones. Devices whose
  /// details were loaded stay under the id they were first found with.
  final Map<String, DiscoveredDevice> _devices = {};
  StreamSubscription<DiscoveredDevice>? _subscription;
  _ScanState _state = _ScanState.checkingNetwork;
  int _visibleCount = _pageSize;
  int _scanGeneration = 0;
  int _detailsInFlight = 0;
  Timer? _refreshTimer;

  // Coalesce bursts of advertisements rather than sorting and rebuilding
  // the list for every packet from a busy network.
  void _scheduleRefresh() {
    _refreshTimer ??= Timer(const Duration(milliseconds: 100), () {
      _refreshTimer = null;
      if (mounted) setState(() {});
    });
  }

  /// Whether the phone is on Wi-Fi. Without it, only Bluetooth is scanned.
  bool _connectedToNetwork = true;

  /// Ids of devices whose details have been requested during this scan.
  final Set<String> _detailsRequested = {};

  @override
  void initState() {
    super.initState();
    if (context.read<SettingsController>().settings.networkDiscoveryEnabled) {
      _startScan();
    }
  }

  @override
  void dispose() {
    _scanGeneration++;
    _refreshTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _startScan() async {
    final generation = ++_scanGeneration;
    final discovery = context.read<DeviceDiscoveryService>();
    await _subscription?.cancel();
    if (!mounted || generation != _scanGeneration) return;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    setState(() {
      _devices.clear();
      _detailsRequested.clear();
      _visibleCount = _pageSize;
      _state = _ScanState.checkingNetwork;
    });

    bool connected;
    try {
      connected = await discovery.isConnectedToLocalNetwork();
    } catch (error) {
      if (mounted && generation == _scanGeneration) {
        setState(() => _state = _ScanState.failed);
      }
      return;
    }
    if (!mounted || generation != _scanGeneration) return;

    setState(() {
      _connectedToNetwork = connected;
      _state = _ScanState.scanning;
    });
    _subscription = discovery
        .scan(includeNetwork: connected)
        .listen(
          (device) {
            if (!mounted || generation != _scanGeneration) return;
            final previous = _devices[device.id];
            // Keep downloaded details and resolved addresses when a repeated
            // announcement only contains the original placeholder.
            if (previous != null &&
                ((!previous.needsDetails && device.needsDetails) ||
                    (previous.address != null && device.address == null))) {
              return;
            }
            _devices[device.id] = device;
            _scheduleRefresh();
          },
          onError: (Object error) {
            if (!mounted || generation != _scanGeneration) return;
            setState(() => _state = _ScanState.failed);
          },
          onDone: () {
            if (!mounted || generation != _scanGeneration) return;
            _refreshTimer?.cancel();
            _refreshTimer = null;
            if (_state == _ScanState.scanning) {
              setState(() => _state = _ScanState.finished);
            }
          },
        );
  }

  /// Loads the details of shown devices that only have an address so far.
  void _loadDetailsOf(Iterable<DiscoveredDevice> shownDevices) {
    final discovery = context.read<DeviceDiscoveryService>();
    final generation = _scanGeneration;
    for (final device in shownDevices) {
      if (_detailsInFlight >= 4) break;
      if (!device.needsDetails || !_detailsRequested.add(device.id)) continue;
      _detailsInFlight++;
      unawaited(_loadDeviceDetails(discovery, device, generation));
    }
  }

  Future<void> _loadDeviceDetails(
    DeviceDiscoveryService discovery,
    DiscoveredDevice device,
    int generation,
  ) async {
    DiscoveredDevice? detailed;
    try {
      detailed = await discovery.loadDetails(device);
    } catch (error) {
      debugPrint('Could not load device details: $error');
    } finally {
      _detailsInFlight--;
    }
    if (!mounted) return;
    setState(() {
      if (generation != _scanGeneration) return;
      final current = _devices[device.id];
      if (current == null || !current.needsDetails) return;
      if (detailed == null) {
        _devices.remove(device.id);
      } else {
        _devices[device.id] = detailed;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final settingsController = context.watch<SettingsController>();
    final allowed = settingsController.settings.networkDiscoveryEnabled;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Find smart devices'),
        actions: [
          if (allowed &&
              _state != _ScanState.scanning &&
              _state != _ScanState.checkingNetwork)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Scan again',
              onPressed: _startScan,
            ),
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Help',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const _DiscoveryHelpDialog(),
            ),
          ),
        ],
      ),
      body: allowed
          ? _buildResults(context)
          : _DiscoveryDisabledMessage(
              onEnable: () async {
                await settingsController.update(
                  settingsController.settings.copyWith(
                    networkDiscoveryEnabled: true,
                  ),
                );
                await _startScan();
              },
            ),
    );
  }

  Widget _buildResults(BuildContext context) {
    final addedIds = context.watch<HomeItemController>().networkIds;
    final devices = rankDevicesByRelevance(
      mergeDuplicateDevices(_devices.values),
    );
    final visibleDevices = devices.take(_visibleCount).toList();
    final hiddenCount = devices.length - visibleDevices.length;

    // Details are only downloaded for devices that are shown, so busy
    // networks aren't flooded with requests. Loading more devices loads
    // their details too.
    if (visibleDevices.any((device) => device.needsDetails)) {
      final generation = _scanGeneration;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && generation == _scanGeneration) {
          _loadDetailsOf(visibleDevices);
        }
      });
    }

    final status = switch (_state) {
      _ScanState.checkingNetwork => 'Checking your network connection...',
      _ScanState.scanning => 'Scanning for nearby devices...',
      _ScanState.finished when devices.isEmpty =>
        'No smart devices were found.',
      _ScanState.finished when hiddenCount > 0 =>
        'Showing ${visibleDevices.length} of ${devices.length} devices found.',
      _ScanState.finished =>
        '${devices.length} ${devices.length == 1 ? 'device' : 'devices'} found.',
      _ScanState.failed when !_connectedToNetwork =>
        'You are not connected to Wi-Fi, and Bluetooth is off or the app is '
            'not allowed to use it. Connect to your home network or turn on '
            'Bluetooth, then scan again.',
      _ScanState.failed =>
        'Nearby devices could not be searched for. Check that the app is '
            'allowed to access your local network and Bluetooth in your '
            'device settings, then scan again.',
    };

    return ListView(
      children: [
        if (_state == _ScanState.scanning ||
            _state == _ScanState.checkingNetwork)
          const LinearProgressIndicator(),
        Padding(padding: const EdgeInsets.all(16), child: Text(status)),
        if (_state == _ScanState.finished && !_connectedToNetwork)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              'You are not connected to a Wi-Fi network, so scanning only '
              'detected nearby Bluetooth devices. Connect to your home network '
              'and scan again to find more devices.',
            ),
          ),
        for (final device in visibleDevices)
          _DeviceTile(
            device: device,
            alreadyAdded: addedIds.contains(device.id),
          ),
        if (hiddenCount > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.expand_more),
              label: Text('Load more ($hiddenCount not shown)'),
              onPressed: () => setState(() => _visibleCount += _pageSize),
            ),
          ),
      ],
    );
  }
}

/// Explains which devices can be found and that scanning stays local.
class _DiscoveryHelpDialog extends StatelessWidget {
  const _DiscoveryHelpDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Finding devices'),
      content: const Text(
        'Only devices that announce themselves on your local network or '
        'over Bluetooth can be found. Devices that only use a '
        'manufacturer\'s cloud service, or that are already connected to '
        'another phone, may not appear, but you can add them yourself.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Got it'),
        ),
      ],
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device, required this.alreadyAdded});

  final DiscoveredDevice device;
  final bool alreadyAdded;

  @override
  Widget build(BuildContext context) {
    final category =
        findHomeItemType(device.suggestedTypeId)?.category ??
        HomeItemCategory.smartDevice;
    if (device.needsDetails) {
      return ListTile(
        leading: Icon(category.icon),
        title: Text(device.name),
        subtitle: const Text('Looking up device details...'),
        trailing: const SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return ListTile(
      leading: device.foundOverBluetooth
          ? const Icon(Icons.bluetooth, semanticLabel: 'Bluetooth')
          : Icon(category.icon),
      title: Text(device.name),
      subtitle: Text(device.kind),
      trailing: alreadyAdded
          ? const Chip(label: Text('Added'))
          : const Icon(Icons.chevron_right),
      // Devices that were already added can't be added a second time.
      onTap: alreadyAdded
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => HomeItemFormScreen(discoveredDevice: device),
              ),
            ),
    );
  }
}

class _DiscoveryDisabledMessage extends StatelessWidget {
  const _DiscoveryDisabledMessage({required this.onEnable});

  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Device scanning is turned off in your privacy settings.\n\n'
              'When allowed, the app looks for smart devices on your local '
              'Wi-Fi network and over Bluetooth. Nothing is sent to the '
              'internet.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onEnable,
              child: const Text('Allow device scanning'),
            ),
          ],
        ),
      ),
    );
  }
}
