import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// A point on the map, in degrees.
typedef Coordinates = ({double latitude, double longitude});

/// Finds roughly where the device is, for searching nearby services.
abstract class LocationService {
  /// The device's approximate location. Asks the user for permission the
  /// first time.
  ///
  /// Throws a [LocationException] if the location can't be found.
  Future<Coordinates> currentLocation();
}

class LocationException implements Exception {
  const LocationException(this.message);

  /// Why the location couldn't be found, written to be shown to the user.
  final String message;

  @override
  String toString() => message;
}

/// Finds the device's location with its location services. Only an
/// approximate location is asked for, since that's enough to find
/// businesses nearby.
class DeviceLocationService implements LocationService {
  @override
  Future<Coordinates> currentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException(
        "Location is turned off on this device. Turn it on, or search near "
        'a ZIP code instead.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    switch (permission) {
      case LocationPermission.denied:
        throw const LocationException(
          'HomeTrack Hub needs your location to find services near you. '
          'Allow it, or search near a ZIP code instead.',
        );
      case LocationPermission.deniedForever:
        throw const LocationException(
          'Location access is turned off for HomeTrack Hub. Allow it in your '
          "phone's settings, or search near a ZIP code instead.",
        );
      case LocationPermission.whileInUse ||
          LocationPermission.always ||
          LocationPermission.unableToDetermine:
        break;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return (latitude: position.latitude, longitude: position.longitude);
    } on TimeoutException {
      // Indoors a fresh location can take a while, and where the phone
      // last was is close enough to find businesses.
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        return (latitude: last.latitude, longitude: last.longitude);
      }
      throw const LocationException(
        "Your location couldn't be found. Try again, or search near a ZIP "
        'code instead.',
      );
    } on LocationServiceDisabledException {
      throw const LocationException(
        "Location is turned off on this device. Turn it on, or search near "
        'a ZIP code instead.',
      );
    } on PermissionDeniedException {
      throw const LocationException(
        'HomeTrack Hub needs your location to find services near you. '
        'Allow it, or search near a ZIP code instead.',
      );
    }
  }
}
