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

  testWidgets('busy networks show a few devices at a time, and only their '
      'details are loaded', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final discovery = _ManyDevicesDiscoveryService(2000, unreadable: {3});

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

    // Device 3's details can't be read, so device 8 takes its place.
    expect(discovery.detailsLoaded, hasLength(9));
    expect(find.textContaining('Found 1999 devices'), findsOneWidget);

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

/// Pretends to find [count] devices, like a busy public network would. Only
/// their addresses are known until their details are loaded.
class _ManyDevicesDiscoveryService implements DeviceDiscoveryService {
  _ManyDevicesDiscoveryService(this.count, {this.unreadable = const {}});

  final int count;

  /// Numbers of the devices whose details can't be read.
  final Set<int> unreadable;

  /// Numbers of the devices whose details have been loaded.
  final List<int> detailsLoaded = [];

  @override
  Future<bool> isConnectedToLocalNetwork() async => true;

  @override
  Stream<DiscoveredDevice> scan({Duration duration = Duration.zero}) {
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
