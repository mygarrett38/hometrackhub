import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart'
    show ImageProvider, NetworkImage, TimeOfDay;

import '../models/service_provider.dart';
import '../models/service_type.dart';
import 'nearby_services_client.dart';

/// Searches Google Places for real businesses, through the `/places` route
/// of the server in `assist/`, so the Google API key stays on that server
/// and never ships in this app.
///
/// Configure with --dart-define=NEARBY_SERVICES_API_URL (the server's
/// address ending in `/places`) and the same
/// --dart-define=HOME_ASSISTANT_API_TOKEN the assistant uses.
class GooglePlacesClient implements NearbyServicesClient {
  GooglePlacesClient({
    String endpoint = _configuredEndpoint,
    String token = _configuredToken,
  }) : _endpoint = Uri.tryParse(endpoint.trim()),
       _token = token.trim();

  static const String _configuredEndpoint = String.fromEnvironment(
    'NEARBY_SERVICES_API_URL',
  );

  /// Must match the APP_TOKEN secret on the server.
  static const String _configuredToken = String.fromEnvironment(
    'HOME_ASSISTANT_API_TOKEN',
  );

  final Uri? _endpoint;
  final String _token;

  /// Whether a valid HTTPS address and token were given, so real searches
  /// can be made.
  bool get isConfigured {
    final endpoint = _endpoint;
    return endpoint != null &&
        endpoint.scheme == 'https' &&
        endpoint.hasAuthority &&
        _token.isNotEmpty;
  }

  @override
  bool get isSample => false;

  @override
  Future<List<ServiceProvider>> search({
    String query = '',
    ServiceType? service,
    SearchArea? area,
  }) async {
    final endpoint = _endpoint;
    if (!isConfigured || endpoint == null) {
      throw const NearbyServicesException(
        'Nearby services have not been set up yet.',
      );
    }
    if (area == null) {
      throw const NearbyServicesException(
        'Choose where to search in Nearby services settings.',
        fixInSettings: true,
      );
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client
          .postUrl(endpoint)
          .timeout(const Duration(seconds: 20));
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
      request.write(
        jsonEncode({
          'textQuery': searchText(query, service),
          'location': switch (area) {
            SearchAroundPoint(:final latitude, :final longitude) => {
              'latitude': latitude,
              'longitude': longitude,
            },
            SearchAroundZipCode(:final zipCode) => {'zipCode': zipCode},
          },
        }),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        // The server explains what went wrong in "error" when it can.
        String? serverMessage;
        try {
          final payload = jsonDecode(body);
          if (payload is Map<String, dynamic>) {
            serverMessage = payload['error'] as String?;
          }
        } on FormatException {
          // Not JSON, for example a proxy's error page.
        }
        throw NearbyServicesException(
          serverMessage ??
              'The nearby services search returned status '
                  '${response.statusCode}.',
          // The server can't find a ZIP code that doesn't exist.
          fixInSettings:
              area is SearchAroundZipCode && response.statusCode == 400,
        );
      }
      return providersFromResponse(
        jsonDecode(body) as Map<String, dynamic>,
        service: service,
        photoFor: _photoFor,
      );
    } on NearbyServicesException {
      rethrow;
    } on TimeoutException {
      throw const NearbyServicesException(
        'The search took too long. Please try again.',
      );
    } on SocketException {
      throw const NearbyServicesException(
        'Could not reach the nearby services search. Check your connection.',
      );
    } on FormatException {
      throw const NearbyServicesException(
        'The nearby services search returned an invalid response.',
      );
    } finally {
      client.close(force: true);
    }
  }

  /// The photo named [name] by Google, loaded through the server's
  /// `/places/photo` route.
  ImageProvider _photoFor(String name) {
    final endpoint = _endpoint!;
    return NetworkImage(
      endpoint
          .replace(
            path: '${endpoint.path}/photo',
            queryParameters: {'name': name},
          )
          .toString(),
      headers: {HttpHeaders.authorizationHeader: 'Bearer $_token'},
    );
  }

  /// What to ask Google for: the user's [query] and the words for
  /// [service], or home repair businesses in general when there's neither.
  static String searchText(String query, ServiceType? service) {
    final text = [
      if (query.trim().isNotEmpty) query.trim(),
      ?service?.searchPhrase,
    ].join(' ');
    return text.isEmpty ? 'home repair services' : text;
  }
}

/// Turns the server's response, Google's places plus the point searched
/// around, into businesses. [service] is the service searched for, if any,
/// and [photoFor] loads a photo from its Google name.
///
/// Throws a [NearbyServicesException] if the response isn't laid out as
/// expected.
List<ServiceProvider> providersFromResponse(
  Map<String, dynamic> response, {
  ServiceType? service,
  required ImageProvider Function(String name) photoFor,
}) {
  try {
    final origin = response['origin'] as Map<String, dynamic>?;
    final places = (response['places'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    return [
      for (final place in places)
        _providerFrom(place, origin, service, photoFor),
    ];
  } on TypeError {
    throw const NearbyServicesException(
      'The nearby services search returned an invalid response.',
    );
  }
}

ServiceProvider _providerFrom(
  Map<String, dynamic> place,
  Map<String, dynamic>? origin,
  ServiceType? service,
  ImageProvider Function(String name) photoFor,
) {
  final location = place['location'] as Map<String, dynamic>?;
  final photo =
      (place['photos'] as List<dynamic>?)?.firstOrNull as Map<String, dynamic>?;
  final photoName = photo?['name'] as String?;
  final phone = place['nationalPhoneNumber'] as String?;
  final website = place['websiteUri'] as String?;
  final mapsLink = place['googleMapsUri'] as String?;

  return ServiceProvider(
    id: place['id'] as String,
    name:
        (place['displayName'] as Map<String, dynamic>?)?['text'] as String? ??
        'Unnamed business',
    services: _servicesFor(
      (place['types'] as List<dynamic>? ?? const []).cast<String>(),
      service,
    ),
    address: _withoutCountry(place['formattedAddress'] as String? ?? ''),
    city: _cityFrom(
      (place['addressComponents'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>(),
    ),
    rating: (place['rating'] as num?)?.toDouble(),
    ratingCount: place['userRatingCount'] as int? ?? 0,
    distanceMiles: origin == null || location == null
        ? null
        : _milesBetween(origin, location),
    hours: _hoursFrom(place['regularOpeningHours'] as Map<String, dynamic>?),
    photo: photoName == null ? null : photoFor(photoName),
    photoCredits: [
      for (final author
          in (photo?['authorAttributions'] as List<dynamic>? ?? const [])
              .cast<Map<String, dynamic>>())
        if (author['displayName'] case final String name)
          PhotoCredit(name, _link(author['uri'] as String?)),
    ],
    mapsLink: _link(mapsLink),
    phone: phone,
    website: _link(website),
  );
}

/// Google's categories for businesses that match a [ServiceType]. Most
/// trades don't have a category of their own.
const _serviceForType = {
  'plumber': ServiceType.plumbing,
  'electrician': ServiceType.electrical,
  'roofing_contractor': ServiceType.roofing,
  'general_contractor': ServiceType.handyman,
  'painter': ServiceType.handyman,
  'locksmith': ServiceType.handyman,
  'car_repair': ServiceType.auto,
};

/// What a business does: the service searched for first, then any its
/// Google categories show. Handyman when nothing else is known.
List<ServiceType> _servicesFor(List<String> types, ServiceType? searched) {
  final services = <ServiceType>{
    ?searched,
    for (final type in types) ?_serviceForType[type],
  };
  return services.isEmpty ? const [ServiceType.handyman] : services.toList();
}

/// The city and state, such as "Springfield, IL", from the parts of a
/// Google address.
String? _cityFrom(List<Map<String, dynamic>> parts) {
  String? find(String type, String field) {
    for (final part in parts) {
      final types = (part['types'] as List<dynamic>? ?? const []);
      if (types.contains(type)) return part[field] as String?;
    }
    return null;
  }

  final city =
      find('locality', 'longText') ??
      find('postal_town', 'longText') ??
      find('sublocality', 'longText');
  if (city == null) return null;
  final state = find('administrative_area_level_1', 'shortText');
  return state == null ? city : '$city, $state';
}

/// Google's addresses end in the country, which is always the US here.
String _withoutCountry(String address) => address.endsWith(', USA')
    ? address.substring(0, address.length - 5)
    : address;

/// A web address from Google, some of which leave out "https:".
Uri? _link(String? text) {
  if (text == null || text.isEmpty) return null;
  return Uri.tryParse(text.startsWith('//') ? 'https:$text' : text);
}

/// Turns Google's opening periods into hours for each day of the week.
///
/// A day with a break, such as for lunch, is shown from its first opening
/// to its last closing, since only one opening time is kept for each day.
Map<int, DayHours>? _hoursFrom(Map<String, dynamic>? openingHours) {
  final periods = (openingHours?['periods'] as List<dynamic>?)
      ?.cast<Map<String, dynamic>>();
  if (periods == null) return null;

  final hours = <int, DayHours>{};
  for (final period in periods) {
    final open = period['open'] as Map<String, dynamic>?;
    if (open == null) continue;
    final close = period['close'] as Map<String, dynamic>?;
    // Google describes a business that's always open as one period that
    // opens at midnight on Sunday and never closes.
    if (close == null) {
      return {
        for (var day = DateTime.monday; day <= DateTime.sunday; day++)
          day: const DayHours.allDay(),
      };
    }

    final day = _weekday(open['day'] as int? ?? 0);
    final opens = _timeOf(open);
    final closes = _timeOf(close);
    final midnight = opens.hour == 0 && opens.minute == 0;
    final closesAtEnd =
        (closes.hour == 0 && closes.minute == 0) ||
        (closes.hour == 23 && closes.minute == 59);
    final today = midnight && closesAtEnd
        ? const DayHours.allDay()
        : DayHours(opens, closes);

    final earlier = hours[day];
    hours[day] = earlier == null
        ? today
        : earlier.allDay || today.allDay
        ? const DayHours.allDay()
        : DayHours(earlier.opens, today.closes);
  }
  return hours;
}

/// Google numbers days from 0 for Sunday, while [DateTime.weekday] runs
/// from 1 for Monday to 7 for Sunday.
int _weekday(int googleDay) => googleDay == 0 ? DateTime.sunday : googleDay;

/// The time in one of Google's opening or closing points. Google leaves out
/// values that are zero, such as the minutes on the hour.
TimeOfDay _timeOf(Map<String, dynamic> point) => TimeOfDay(
  hour: point['hour'] as int? ?? 0,
  minute: point['minute'] as int? ?? 0,
);

/// The distance in miles between two points, along the Earth's surface.
double _milesBetween(Map<String, dynamic> a, Map<String, dynamic> b) {
  const earthRadiusMiles = 3958.8;
  double radians(Object? degrees) => (degrees as num) * math.pi / 180;
  final lat1 = radians(a['latitude']);
  final lat2 = radians(b['latitude']);
  final dLat = lat2 - lat1;
  final dLng = radians(b['longitude']) - radians(a['longitude']);
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLng / 2), 2);
  return 2 * earthRadiusMiles * math.asin(math.sqrt(h));
}
