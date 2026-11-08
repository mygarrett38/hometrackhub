import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/app_settings.dart';
import '../models/service_provider.dart';
import '../models/service_sort.dart';
import '../models/service_type.dart';
import '../services/location_service.dart';
import '../services/nearby_services_client.dart';

/// Searches for nearby businesses as the user types or picks a service, and
/// filters and sorts the results.
///
/// The search text and service are sent with each search. The minimum
/// rating, open now and sort order only change which results are shown and
/// in what order, so changing them doesn't search again.
class NearbyServicesController extends ChangeNotifier {
  /// [debounce] is how long typing has to pause before a search is made, so
  /// there isn't a search for every letter. The results start in
  /// [initialSort] order.
  ///
  /// [locate] finds the area to search around, such as with
  /// [searchAreaFor]. It's called before the first search and then reused,
  /// unless it fails or [relocate] is called. Sample searches don't need it.
  NearbyServicesController(
    this._client, {
    this.debounce = const Duration(milliseconds: 400),
    DateTime Function()? clock,
    ServiceSort initialSort = ServiceSort.rating,
    this._locate,
  }) : _clock = clock ?? DateTime.now,
       _sort = initialSort;

  final NearbyServicesClient _client;
  final Duration debounce;
  final DateTime Function() _clock;
  final Future<SearchArea> Function()? _locate;

  /// The area being searched around, once [_locate] has been asked for it.
  Future<SearchArea>? _area;

  String _query = '';
  ServiceType? _service;
  double? _minRating;
  bool _openNowOnly = false;
  ServiceSort _sort;

  List<ServiceProvider> _results = const [];
  bool _loading = false;
  bool _searched = false;
  String? _error;
  bool _errorFixInSettings = false;

  /// Counts searches, so the results of an older search that finishes late
  /// don't replace those of a newer one.
  int _latestSearch = 0;
  Timer? _typingTimer;
  bool _disposed = false;

  /// The choices for [minRating], besides `null` for any rating.
  static const minRatingChoices = [3.5, 4.0, 4.5];

  bool get isSample => _client.isSample;

  /// The current time, used to tell which businesses are open.
  DateTime get now => _clock();
  String get query => _query;
  ServiceType? get service => _service;

  /// Businesses rated lower than this, or not rated yet, are hidden.
  double? get minRating => _minRating;
  bool get openNowOnly => _openNowOnly;
  ServiceSort get sort => _sort;

  /// Whether a search is in progress. The previous results stay until it
  /// finishes.
  bool get loading => _loading;

  /// Whether a search has finished yet, successfully or not.
  bool get searched => _searched;

  /// Why the last search failed, if it did.
  String? get error => _error;

  /// Whether changing the Nearby services settings could fix [error], such
  /// as by adding a ZIP code or allowing location access.
  bool get errorFixInSettings => _errorFixInSettings;

  /// Whether the minimum rating or open now is hiding any businesses.
  bool get hasFilters => _minRating != null || _openNowOnly;

  /// The results of the last search that match the filters, in [sort]
  /// order.
  List<ServiceProvider> get providers {
    final shown = [
      for (final provider in _results)
        if (_matchesFilters(provider)) provider,
    ]..sort(_compare);
    return List.unmodifiable(shown);
  }

  /// How many results of the last search the filters are hiding.
  int get hiddenCount => _results.length - providers.length;

  /// Searches for [text] once the user stops typing for [debounce].
  void setQuery(String text) {
    final query = text.trim();
    if (query == _query) return;
    _query = query;
    _typingTimer?.cancel();
    _typingTimer = Timer(debounce, search);
  }

  /// Searches straight away, such as when the user presses search on the
  /// keyboard.
  void searchNow() {
    _typingTimer?.cancel();
    search();
  }

  /// Searches for businesses that offer [service], or any service when
  /// it's `null`.
  void setService(ServiceType? service) {
    if (service == _service) return;
    _service = service;
    searchNow();
  }

  void setMinRating(double? rating) {
    if (rating == _minRating) return;
    _minRating = rating;
    notifyListeners();
  }

  void setOpenNowOnly(bool value) {
    if (value == _openNowOnly) return;
    _openNowOnly = value;
    notifyListeners();
  }

  void setSort(ServiceSort sort) {
    if (sort == _sort) return;
    _sort = sort;
    notifyListeners();
  }

  /// Turns off the minimum rating and open now.
  void clearFilters() {
    if (!hasFilters) return;
    _minRating = null;
    _openNowOnly = false;
    notifyListeners();
  }

  /// Searches for the current [query] and [service].
  Future<void> search() async {
    final searchId = ++_latestSearch;
    _loading = true;
    _error = null;
    notifyListeners();

    NearbyServicesException? error;
    List<ServiceProvider>? results;
    try {
      // Only waits when there's an area to find, so other searches start
      // straight away.
      final finding = _searchArea();
      results = await _client.search(
        query: _query,
        service: _service,
        area: finding == null ? null : await finding,
      );
    } on NearbyServicesException catch (exception) {
      error = exception;
    }
    if (_disposed || searchId != _latestSearch) return;

    _results = results ?? const [];
    _error = error?.message;
    _errorFixInSettings = error?.fixInSettings ?? false;
    _loading = false;
    _searched = true;
    notifyListeners();
  }

  /// Finds the area to search around again, such as after the user changes
  /// where to search in settings, and searches there.
  Future<void> relocate() {
    _area = null;
    return search();
  }

  /// The area to search around, found the first time it's needed, or
  /// `null` when no area is needed, such as for sample searches.
  Future<SearchArea>? _searchArea() {
    final locate = _locate;
    if (_client.isSample || locate == null) return null;
    final area = _area ??= locate();
    return area.catchError((Object error) {
      // Tries again next time, in case the user has fixed the problem.
      if (identical(_area, area)) _area = null;
      throw error;
    });
  }

  bool _matchesFilters(ServiceProvider provider) {
    final minRating = _minRating;
    if (minRating != null && (provider.rating ?? 0) < minRating) return false;
    if (_openNowOnly && provider.isOpenAt(now) != true) return false;
    return true;
  }

  /// Orders businesses by [sort]. Businesses missing what's being sorted by
  /// go last, and ties are broken by name.
  int _compare(ServiceProvider a, ServiceProvider b) {
    final bySort = switch (_sort) {
      ServiceSort.rating => _missingLast(
        a.rating,
        b.rating,
        (a, b) => b.compareTo(a),
      ).then(b.ratingCount.compareTo(a.ratingCount)),
      ServiceSort.distance => _missingLast(
        a.distanceMiles,
        b.distanceMiles,
        (a, b) => a.compareTo(b),
      ),
      ServiceSort.reviews => b.ratingCount.compareTo(a.ratingCount),
    };
    return bySort.then(a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// Compares [a] and [b] with [compare], putting a missing value after any
  /// other.
  static int _missingLast(
    double? a,
    double? b,
    int Function(double a, double b) compare,
  ) {
    if (a == null || b == null) {
      return (a == null ? 1 : 0) - (b == null ? 1 : 0);
    }
    return compare(a, b);
  }

  @override
  void dispose() {
    _disposed = true;
    _typingTimer?.cancel();
    super.dispose();
  }
}

extension on int {
  /// This comparison, or [tieBreak] when it's a tie.
  int then(int tieBreak) => this == 0 ? tieBreak : this;
}

/// The area to search around, as chosen in the Nearby services [settings]:
/// the device's location from [location], or the user's ZIP code.
///
/// Throws a [NearbyServicesException] that can be fixed in settings if
/// there's no ZIP code yet or the location can't be found.
Future<SearchArea> searchAreaFor(
  AppSettings settings,
  LocationService location,
) async {
  switch (settings.nearbyLocationSource) {
    case NearbyLocationSource.zipCode:
      final zipCode = settings.nearbyZipCode;
      if (zipCode == null) {
        throw const NearbyServicesException(
          'Add the ZIP code to search near in Nearby services settings.',
          fixInSettings: true,
        );
      }
      return SearchAroundZipCode(zipCode);
    case NearbyLocationSource.device:
      try {
        final here = await location.currentLocation();
        return SearchAroundPoint(here.latitude, here.longitude);
      } on LocationException catch (exception) {
        throw NearbyServicesException(exception.message, fixInSettings: true);
      }
  }
}
