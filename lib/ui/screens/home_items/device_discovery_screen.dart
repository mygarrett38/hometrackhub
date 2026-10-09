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

/// The stages the network scan can be in.
enum _ScanState { checkingNetwork, notConnected, scanning, finished, failed }

/// Scans the home network for smart devices and lets the user add them as
/// home items.
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
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _startScan() async {
    final discovery = context.read<DeviceDiscoveryService>();
    await _subscription?.cancel();
    setState(() {
      _devices.clear();
      _detailsRequested.clear();
      _visibleCount = _pageSize;
      _state = _ScanState.checkingNetwork;
    });

    final connected = await discovery.isConnectedToLocalNetwork();
    if (!mounted) return;
    if (!connected) {
      setState(() => _state = _ScanState.notConnected);
      return;
    }

    setState(() => _state = _ScanState.scanning);
    _subscription = discovery.scan().listen(
      (device) {
        setState(() {
          final previous = _devices[device.id];
          // Keep a previously found address if the update doesn't have one.
          _devices[device.id] = device.address == null && previous != null
              ? previous
              : device;
        });
      },
      onError: (Object error) {
        setState(() => _state = _ScanState.failed);
      },
      onDone: () {
        if (_state == _ScanState.scanning) {
          setState(() => _state = _ScanState.finished);
        }
      },
    );
  }

  /// Loads the details of shown devices that only have an address so far.
  void _loadDetailsOf(Iterable<DiscoveredDevice> shownDevices) {
    final discovery = context.read<DeviceDiscoveryService>();
    for (final device in shownDevices) {
      if (!device.needsDetails || !_detailsRequested.add(device.id)) continue;
      discovery.loadDetails(device).then((detailed) {
        // Ignore results that arrive after the screen closed or a new scan
        // started.
        if (!mounted || !identical(_devices[device.id], device)) return;
        setState(() {
          if (detailed == null) {
            // Unreadable devices are dropped, making room for the next one.
            _devices.remove(device.id);
          } else {
            _devices[device.id] = detailed;
          }
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsController = context.watch<SettingsController>();
    final allowed = settingsController.settings.networkDiscoveryEnabled;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Find smart devices'),
        actions: [
          if (allowed && _state != _ScanState.scanning)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Scan again',
              onPressed: _startScan,
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadDetailsOf(visibleDevices);
      });
    }

    final status = switch (_state) {
      _ScanState.checkingNetwork => 'Checking your network connection...',
      _ScanState.notConnected =>
        'You are not connected to Wi-Fi. Connect to your home network and '
            'scan again.',
      _ScanState.scanning =>
        'Searching your network. This takes about 10 '
            'seconds...',
      _ScanState.finished when devices.isEmpty =>
        'No smart devices were found.',
      _ScanState.finished when hiddenCount > 0 =>
        'Found ${devices.length} devices. Showing the '
            '${visibleDevices.length} most relevant.',
      _ScanState.finished =>
        'Found ${devices.length} '
            '${devices.length == 1 ? 'device' : 'devices'}.',
      _ScanState.failed =>
        'Your network could not be scanned. Check that the app is allowed '
            'to access your local network in your device settings, then '
            'scan again.',
    };

    return ListView(
      children: [
        if (_state == _ScanState.scanning ||
            _state == _ScanState.checkingNetwork)
          const LinearProgressIndicator(),
        Padding(padding: const EdgeInsets.all(16), child: Text(status)),
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
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Only devices that announce themselves on your local network can '
            'be found. Devices that only use Bluetooth or a manufacturer\'s '
            'cloud service may not appear, but you can add them yourself. '
            'Scanning stays on your local network and nothing is sent to '
            'the internet.',
          ),
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
    final details = [
      device.kind,
      if (device.address != null) device.address!,
    ].join(' · ');

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
      leading: Icon(category.icon),
      title: Text(device.name),
      subtitle: Text(details),
      trailing: alreadyAdded
          ? const Chip(label: Text('Added'))
          : FilledButton.tonal(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => HomeItemFormScreen(discoveredDevice: device),
                ),
              ),
              child: const Text('Add'),
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
              'Network scanning is turned off in your privacy settings.\n\n'
              'When allowed, the app looks for smart devices on your local '
              'Wi-Fi network. Nothing is sent to the internet.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onEnable,
              child: const Text('Allow network scanning'),
            ),
          ],
        ),
      ),
    );
  }
}
