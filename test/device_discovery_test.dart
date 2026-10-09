import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometrackhub/data/home_item_repository.dart';
import 'package:hometrackhub/data/settings_repository.dart';
import 'package:hometrackhub/services/device_discovery_service.dart';
import 'package:hometrackhub/state/home_item_controller.dart';
import 'package:hometrackhub/state/settings_controller.dart';
import 'package:hometrackhub/ui/screens/home_items/device_discovery_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('devices at the same address are merged into the most useful one', () {
    const devices = [
      DiscoveredDevice(
        id: 'mdns:3be72874-c6c2-59f3-878b-13d5dfc2920c',
        name: '3be72874-c6c2-59f3-878b-13d5dfc2920c',
        kind: 'Spotify Connect speaker',
        suggestedTypeId: 'smart_speaker',
        address: '192.168.0.164',
      ),
      DiscoveredDevice(
        id: 'upnp:uuid:roku',
        name: 'Roku Express 4K+',
        kind: 'Roku streaming device',
        suggestedTypeId: 'smart_tv',
        manufacturer: 'Roku',
        address: '192.168.0.164',
      ),
      DiscoveredDevice(
        id: 'mdns:printer',
        name: 'Office printer',
        kind: 'Network printer',
        suggestedTypeId: 'printer',
        address: '192.168.0.171',
      ),
    ];

    final merged = mergeDuplicateDevices(devices);

    expect(merged.map((device) => device.name), [
      'Roku Express 4K+',
      'Office printer',
    ]);
  });

  test('devices without an address are kept separately', () {
    const devices = [
      DiscoveredDevice(
        id: 'mdns:a',
        name: 'A',
        kind: 'AirPlay device',
        suggestedTypeId: 'smart_tv',
      ),
      DiscoveredDevice(
        id: 'mdns:b',
        name: 'B',
        kind: 'AirPlay device',
        suggestedTypeId: 'smart_tv',
      ),
    ];

    expect(mergeDuplicateDevices(devices), hasLength(2));
  });

  test('devices waiting for details replace only unreadable entries', () {
    DiscoveredDevice waitingForDetails(String address) => DiscoveredDevice(
      id: 'upnp:http://$address/description.xml',
      name: address,
      kind: 'Network device',
      suggestedTypeId: 'smart_device',
      address: address,
      detailsUrl: Uri.parse('http://$address/description.xml'),
    );

    final devices = [
      const DiscoveredDevice(
        id: 'mdns:3be72874-c6c2-59f3-878b-13d5dfc2920c',
        name: '3be72874-c6c2-59f3-878b-13d5dfc2920c',
        kind: 'Spotify Connect speaker',
        suggestedTypeId: 'smart_speaker',
        address: '192.168.0.164',
      ),
      waitingForDetails('192.168.0.164'),
      const DiscoveredDevice(
        id: 'mdns:printer',
        name: 'Office printer',
        kind: 'Network printer',
        suggestedTypeId: 'printer',
        address: '192.168.0.171',
      ),
      waitingForDetails('192.168.0.171'),
    ];

    expect(mergeDuplicateDevices(devices).map((device) => device.name), [
      '192.168.0.164',
      'Office printer',
    ]);
  });

  test(
    'identified devices rank above generic ones, then by discovery order',
    () {
      const devices = [
        DiscoveredDevice(
          id: 'upnp:laptop',
          name: 'DESKTOP-4F2A',
          kind: 'Network device',
          suggestedTypeId: 'smart_device',
        ),
        DiscoveredDevice(
          id: 'mdns:3be72874-c6c2-59f3-878b-13d5dfc2920c',
          name: '3be72874-c6c2-59f3-878b-13d5dfc2920c',
          kind: 'Spotify Connect speaker',
          suggestedTypeId: 'smart_speaker',
        ),
        DiscoveredDevice(
          id: 'mdns:kitchen',
          name: 'Kitchen speaker',
          kind: 'Sonos speaker',
          suggestedTypeId: 'smart_speaker',
        ),
        DiscoveredDevice(
          id: 'upnp:roku',
          name: 'Roku Express 4K+',
          kind: 'Roku streaming device',
          suggestedTypeId: 'smart_tv',
          manufacturer: 'Roku',
          model: '3941X',
        ),
        DiscoveredDevice(
          id: 'mdns:bedroom',
          name: 'Bedroom speaker',
          kind: 'Sonos speaker',
          suggestedTypeId: 'smart_speaker',
        ),
      ];

      expect(rankDevicesByRelevance(devices).map((device) => device.name), [
        'Roku Express 4K+',
        'Kitchen speaker',
        'Bedroom speaker',
        'DESKTOP-4F2A',
        '3be72874-c6c2-59f3-878b-13d5dfc2920c',
      ]);
    },
  );

  test('closer Bluetooth devices rank higher', () {
    const devices = [
      DiscoveredDevice(
        id: 'ble:far',
        name: 'Neighbor\'s speaker',
        kind: 'Bluetooth speaker',
        suggestedTypeId: 'smart_speaker',
        signalStrength: -90,
      ),
      DiscoveredDevice(
        id: 'ble:unknown',
        name: 'XK-204',
        kind: 'Bluetooth device',
        suggestedTypeId: 'smart_device',
        signalStrength: -45,
      ),
      DiscoveredDevice(
        id: 'ble:near',
        name: 'Living room speaker',
        kind: 'Bluetooth speaker',
        suggestedTypeId: 'smart_speaker',
        signalStrength: -55,
      ),
    ];

    expect(rankDevicesByRelevance(devices).map((device) => device.name), [
      'Living room speaker',
      'Neighbor\'s speaker',
      'XK-204',
    ]);
  });

  group('Bluetooth devices are recognized', () {
    (String, String) classify(
      String name, {
      List<String> serviceUuids = const [],
      Map<int, List<int>> manufacturerData = const {},
    }) => classifyBluetoothDevice(
      name: name,
      serviceUuids: serviceUuids,
      manufacturerData: manufacturerData,
    );

    test('by the services they advertise', () {
      expect(classify('MATTER-3840', serviceUuids: ['FFF6']), (
        'Matter device (setup mode)',
        'smart_device',
      ));
      expect(
        classify('Hue color lamp', serviceUuids: ['fe0f']).$2,
        'smart_lighting',
      );
    });

    test('as HomeKit accessories', () {
      expect(
        classify(
          'Eve Energy',
          manufacturerData: {
            0x004C: [0x06, 0x31],
          },
        ),
        ('Apple HomeKit accessory', 'smart_device'),
      );
    });

    test('by whole words in their names', () {
      expect(classify('Front Door Lock').$2, 'smart_lock');
      expect(classify('Bedroom TV').$2, 'smart_tv');
      expect(classify('Ring Doorbell').$2, 'security_camera');
      expect(classify('Cambridge Audio').$2, 'smart_device');
      expect(classify('Spring sensor'), ('Bluetooth device', 'smart_device'));
    });
  });

  test('Bluetooth devices also found on the network are merged by name', () {
    const devices = [
      DiscoveredDevice(
        id: 'ble:AA:BB',
        name: 'living room tv',
        kind: 'TV or streaming device',
        suggestedTypeId: 'smart_tv',
        foundOverBluetooth: true,
      ),
      DiscoveredDevice(
        id: 'mdns:living room tv',
        name: 'Living Room TV',
        kind: 'Google Cast device',
        suggestedTypeId: 'smart_tv',
        address: '192.168.0.20',
      ),
      DiscoveredDevice(
        id: 'ble:CC:DD',
        name: 'Front Door Lock',
        kind: 'Smart lock',
        suggestedTypeId: 'smart_lock',
        foundOverBluetooth: true,
      ),
    ];

    expect(mergeDuplicateDevices(devices).map((device) => device.id), [
      'mdns:living room tv',
      'ble:CC:DD',
    ]);
  });

  testWidgets('only devices found just over Bluetooth show its icon', (
    tester,
  ) async {
    await _pumpDiscoveryScreen(
      tester,
      _FixedDevicesDiscoveryService(const [
        DiscoveredDevice(
          id: 'ble:AA:BB',
          name: 'Living Room TV',
          kind: 'TV or streaming device',
          suggestedTypeId: 'smart_tv',
          foundOverBluetooth: true,
        ),
        DiscoveredDevice(
          id: 'mdns:living room tv',
          name: 'Living Room TV',
          kind: 'Google Cast device',
          suggestedTypeId: 'smart_tv',
          address: '192.168.0.20',
        ),
        DiscoveredDevice(
          id: 'ble:CC:DD',
          name: 'Front Door Lock',
          kind: 'Smart lock',
          suggestedTypeId: 'smart_lock',
          foundOverBluetooth: true,
        ),
      ]),
    );

    expect(find.text('Living Room TV'), findsOneWidget);
    expect(find.byIcon(Icons.bluetooth), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byIcon(Icons.bluetooth),
        matching: find.widgetWithText(ListTile, 'Front Door Lock'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the help button explains which devices can be found', (
    tester,
  ) async {
    await _pumpDiscoveryScreen(tester, _FixedDevicesDiscoveryService(const []));

    await tester.tap(find.byTooltip('Help'));
    await tester.pumpAndSettle();
    expect(find.textContaining('you can add them yourself'), findsOneWidget);

    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.textContaining('you can add them yourself'), findsNothing);
  });

  testWidgets('only Bluetooth is scanned without Wi-Fi', (tester) async {
    final discovery = _ManyDevicesDiscoveryService(0, connected: false);
    await _pumpDiscoveryScreen(tester, discovery);

    expect(discovery.includedNetwork, isFalse);
    expect(find.textContaining('so scanning only detected'), findsOneWidget);
  });

  testWidgets('busy networks show a few devices at a time, and only their '
      'details are loaded', (tester) async {
    final discovery = _ManyDevicesDiscoveryService(2000, unreadable: {3});
    await _pumpDiscoveryScreen(tester, discovery);

    // Device 3's details can't be read, so device 8 takes its place.
    expect(discovery.detailsLoaded, hasLength(9));
    expect(find.text('Showing 8 of 1999 devices found.'), findsOneWidget);

    await tester.scrollUntilVisible(find.textContaining('Load more'), 100);
    expect(find.text('Device 3'), findsNothing);
    expect(find.text('Device 8'), findsOneWidget);
    expect(find.text('Device 9'), findsNothing);
    expect(find.text('Load more (1991 not shown)'), findsOneWidget);
    await tester.ensureVisible(find.textContaining('Load more'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Load more'));
    await tester.pumpAndSettle();

    expect(discovery.detailsLoaded, hasLength(17));
    await tester.scrollUntilVisible(find.textContaining('Load more'), 100);
    expect(find.text('Device 16'), findsOneWidget);
    expect(find.text('Device 17'), findsNothing);
    expect(find.text('Load more (1983 not shown)'), findsOneWidget);
  });
}

Future<void> _pumpDiscoveryScreen(
  WidgetTester tester,
  DeviceDiscoveryService discovery,
) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => HomeItemController(HomeItemRepository(preferences)),
        ),
        ChangeNotifierProvider(
          create: (_) => SettingsController(SettingsRepository(preferences)),
        ),
        Provider<DeviceDiscoveryService>.value(value: discovery),
      ],
      child: const MaterialApp(home: DeviceDiscoveryScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

/// Pretends to find [count] devices, like a busy public network would. Only
/// their addresses are known until their details are loaded.
class _ManyDevicesDiscoveryService implements DeviceDiscoveryService {
  _ManyDevicesDiscoveryService(
    this.count, {
    this.unreadable = const {},
    this.connected = true,
  });

  final int count;

  /// Whether the phone pretends to be on Wi-Fi.
  final bool connected;

  /// Whether the last scan included the local network.
  bool? includedNetwork;

  /// Numbers of the devices whose details can't be read.
  final Set<int> unreadable;

  /// Numbers of the devices whose details have been loaded.
  final List<int> detailsLoaded = [];

  @override
  Future<bool> isConnectedToLocalNetwork() async => connected;

  @override
  Stream<DiscoveredDevice> scan({
    Duration duration = Duration.zero,
    bool includeNetwork = true,
  }) {
    includedNetwork = includeNetwork;
    return Stream.fromIterable([
      for (var i = 0; i < count; i++)
        DiscoveredDevice(
          id: 'upnp:device $i',
          name: '10.0.${i ~/ 256}.${i % 256}',
          kind: 'Network device',
          suggestedTypeId: 'smart_device',
          address: '10.0.${i ~/ 256}.${i % 256}',
          detailsUrl: Uri.parse('http://device$i/description.xml'),
        ),
    ]);
  }

  @override
  Future<DiscoveredDevice?> loadDetails(DiscoveredDevice device) async {
    final number = int.parse(device.id.split(' ').last);
    detailsLoaded.add(number);
    if (unreadable.contains(number)) return null;
    return DiscoveredDevice(
      id: device.id,
      name: 'Device $number',
      kind: 'Smart TV or media player',
      suggestedTypeId: 'smart_tv',
      address: device.address,
    );
  }
}

/// Finds the same fixed list of devices every scan.
class _FixedDevicesDiscoveryService implements DeviceDiscoveryService {
  _FixedDevicesDiscoveryService(this.devices);

  final List<DiscoveredDevice> devices;

  @override
  Future<bool> isConnectedToLocalNetwork() async => true;

  @override
  Stream<DiscoveredDevice> scan({
    Duration duration = Duration.zero,
    bool includeNetwork = true,
  }) => Stream.fromIterable(devices);

  @override
  Future<DiscoveredDevice?> loadDetails(DiscoveredDevice device) async =>
      device;
}
