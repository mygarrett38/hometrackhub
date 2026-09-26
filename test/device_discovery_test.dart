import 'package:flutter_test/flutter_test.dart';
import 'package:hometrackhub/services/device_discovery_service.dart';

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
}
