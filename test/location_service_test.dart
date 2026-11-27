import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hometrackhub/services/location_service.dart';

/// A position at [latitude], found at [timestamp].
Position _positionAt(double latitude, DateTime timestamp) => Position(
  latitude: latitude,
  longitude: -89.6,
  timestamp: timestamp,
  accuracy: 100,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

/// The device's location services, with location allowed. Counts how often
/// a fresh location is asked for.
class _FakeGeolocator extends GeolocatorPlatform {
  _FakeGeolocator({required this.current});

  /// The fresh location, or `null` if finding one times out.
  Position? current;

  /// The last location the device knows of.
  Position? lastKnown;

  int freshRequests = 0;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async => lastKnown;

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    freshRequests++;
    return current ?? (throw TimeoutException('No fix'));
  }
}

void main() {
  final now = DateTime(2026, 11, 27, 12);
  late _FakeGeolocator device;
  late DeviceLocationService service;

  setUp(() {
    device = _FakeGeolocator(current: _positionAt(39.8, now));
    GeolocatorPlatform.instance = device;
    service = DeviceLocationService(clock: () => now);
  });

  test('uses a location the device found recently', () async {
    device.lastKnown = _positionAt(
      39.7,
      now.subtract(DeviceLocationService.recentEnough),
    );

    final here = await service.currentLocation();

    expect(here.latitude, 39.7);
    expect(device.freshRequests, 0);
  });

  test('waits for a fresh location when the last one is too old', () async {
    device.lastKnown = _positionAt(
      39.7,
      now.subtract(
        DeviceLocationService.recentEnough + const Duration(minutes: 1),
      ),
    );

    final here = await service.currentLocation();

    expect(here.latitude, 39.8);
    expect(device.freshRequests, 1);
  });

  test('reuses a location it found while it is recent', () async {
    var time = now;
    service = DeviceLocationService(clock: () => time);

    await service.currentLocation();
    time = now.add(const Duration(minutes: 5));
    await service.currentLocation();
    expect(device.freshRequests, 1);

    time = now.add(const Duration(minutes: 11));
    device.current = _positionAt(39.9, time);
    final later = await service.currentLocation();
    expect(device.freshRequests, 2);
    expect(later.latitude, 39.9);
  });

  test(
    'falls back to an old location when a fresh one takes too long',
    () async {
      device
        ..current = null
        ..lastKnown = _positionAt(39.7, now.subtract(const Duration(days: 1)));

      final here = await service.currentLocation();

      expect(here.latitude, 39.7);
    },
  );

  test('says so when there is no location at all', () {
    device.current = null;

    expect(
      service.currentLocation(),
      throwsA(
        isA<LocationException>().having(
          (error) => error.message,
          'message',
          contains("couldn't be found"),
        ),
      ),
    );
  });
}
