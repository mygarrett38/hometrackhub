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
///
/// Finding a fresh location can take several seconds, so a location found
/// within the last [recentEnough] is used instead when there is one: one
/// this found itself, or the last one the device knows of.
class DeviceLocationService implements LocationService {
  DeviceLocationService({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// How old a location can be and still be used, rather than waiting for
  /// a fresh one. Close enough to find businesses unless the user has
  /// driven a long way since.
  static const recentEnough = Duration(minutes: 10);

  final DateTime Function() _clock;

  /// The location this last found, and when.
  ({Coordinates where, DateTime at})? _lastFound;

  @override
  Future<Coordinates> currentLocation() async {
    try {
      return await _find();
    } on LocationException {
      rethrow;
    } on Exception {
      // Anything else the device's location services report, such as a
      // permission request already being shown.
      throw const LocationException(_notFound);
    }
  }

  static const _notFound =
      "Your location couldn't be found. Try again, or search near a ZIP code "
      'instead.';

  Future<Coordinates> _find() async {
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

    // Checked after the permission, so a location isn't used once the
    // user has taken it away.
    if (_lastFound case final found? when _isRecent(found.at)) {
      return found.where;
    }
    final last = await _lastKnownPosition();
    if (last != null && _isRecent(last.timestamp)) return _remember(last);

    try {
      return _remember(
        await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 15),
          ),
        ),
      );
    } on TimeoutException {
      // Indoors a fresh location can take a while, and where the phone
      // last was, however long ago, is better than nothing. It may have
      // found one while this waited.
      if (await _lastKnownPosition() ?? last case final latest?) {
        return (latitude: latest.latitude, longitude: latest.longitude);
      }
      throw const LocationException(_notFound);
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

  /// The last location the device knows of, or `null` if it doesn't know
  /// one or can't say.
  Future<Position?> _lastKnownPosition() async {
    try {
      return await Geolocator.getLastKnownPosition();
    } on Exception {
      return null;
    }
  }

  bool _isRecent(DateTime time) => _clock().difference(time) <= recentEnough;

  /// Keeps [position] to use again while it's recent, and returns it.
  Coordinates _remember(Position position) {
    final where = (latitude: position.latitude, longitude: position.longitude);
    _lastFound = (where: where, at: position.timestamp);
    return where;
  }
}
