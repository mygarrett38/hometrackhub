import 'package:flutter/material.dart' show TimeOfDay;

import '../models/service_provider.dart';
import '../models/service_type.dart';

/// Where to search for businesses around.
sealed class SearchArea {
  const SearchArea();
}

/// Around a point on the map, such as the device's location.
class SearchAroundPoint extends SearchArea {
  const SearchAroundPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

/// Around the middle of a US ZIP code.
class SearchAroundZipCode extends SearchArea {
  const SearchAroundZipCode(this.zipCode);

  final String zipCode;
}

/// Finds home maintenance businesses near the user.
abstract class NearbyServicesClient {
  /// Whether the results are made-up businesses for trying out the app,
  /// rather than real listings. Sample searches don't need a [SearchArea].
  bool get isSample;

  /// Businesses around [area] matching [query], such as a company's name,
  /// that offer [service]. Either may be left out to search more broadly.
  ///
  /// Throws a [NearbyServicesException] if the search couldn't be done.
  Future<List<ServiceProvider>> search({
    String query = '',
    ServiceType? service,
    SearchArea? area,
  });
}

class NearbyServicesException implements Exception {
  const NearbyServicesException(this.message, {this.fixInSettings = false});

  /// Why the search failed, written to be shown to the user.
  final String message;

  /// Whether changing the Nearby services settings could fix it, such as by
  /// adding a ZIP code.
  final bool fixInSettings;

  @override
  String toString() => message;
}

/// Searches a fixed list of made-up businesses, so the Nearby services
/// screen can be tried out before it's connected to real listings.
class SampleNearbyServicesClient implements NearbyServicesClient {
  /// [delay] is how long each search pretends to take, so loading can be
  /// seen in the app.
  SampleNearbyServicesClient({
    this.delay = const Duration(milliseconds: 600),
    List<ServiceProvider>? providers,
  }) : providers = providers ?? sampleProviders;

  final Duration delay;
  final List<ServiceProvider> providers;

  @override
  bool get isSample => true;

  @override
  Future<List<ServiceProvider>> search({
    String query = '',
    ServiceType? service,
    SearchArea? area,
  }) async {
    await Future<void>.delayed(delay);
    final words = query.toLowerCase().split(RegExp(r'\s+'))
      ..removeWhere((word) => word.isEmpty);
    return [
      for (final provider in providers)
        if ((service == null || provider.services.contains(service)) &&
            words.every(_searchableText(provider).contains))
          provider,
    ];
  }

  /// Everything a search can match for [provider]: its name, address and
  /// the services it offers.
  static String _searchableText(ServiceProvider provider) => [
    provider.name,
    provider.address,
    for (final service in provider.services) ...[
      service.label,
      service.searchPhrase,
    ],
  ].join(' ').toLowerCase();
}

TimeOfDay _at(int hour, [int minute = 0]) =>
    TimeOfDay(hour: hour, minute: minute);

/// The same [hours] on every day of the week.
Map<int, DayHours> _everyDay(DayHours hours) => {
  for (var day = DateTime.monday; day <= DateTime.sunday; day++) day: hours,
};

/// [hours] from Monday to Friday, and the weekend days given. The business
/// is closed on any other day.
Map<int, DayHours> _weekdays(
  DayHours hours, {
  DayHours? saturday,
  DayHours? sunday,
}) => {
  for (var day = DateTime.monday; day <= DateTime.friday; day++) day: hours,
  DateTime.saturday: ?saturday,
  DateTime.sunday: ?sunday,
};

/// Made-up businesses used by [SampleNearbyServicesClient]. The phone
/// numbers are in the 555-01xx range kept for fiction, and the websites are
/// on example.com. They have no pictures, so each card shows its service's
/// icon instead.
final sampleProviders = <ServiceProvider>[
  ServiceProvider(
    id: 'sample-riverbend',
    name: 'Riverbend Plumbing & Drain',
    services: const [ServiceType.plumbing],
    address: '1420 Elm St, Springfield, IL',
    city: 'Springfield, IL',
    rating: 4.8,
    ratingCount: 312,
    distanceMiles: 1.2,
    hours: _everyDay(const DayHours.allDay()),
    phone: '(555) 555-0101',
    website: Uri.parse('https://example.com/riverbend-plumbing'),
  ),
  ServiceProvider(
    id: 'sample-summit',
    name: 'Summit Heating & Air',
    services: const [ServiceType.hvac],
    address: '88 Ridge Rd, Chatham, IL',
    city: 'Chatham, IL',
    rating: 4.6,
    ratingCount: 198,
    distanceMiles: 3.4,
    hours: _weekdays(
      DayHours(_at(7, 30), _at(18)),
      saturday: DayHours(_at(8), _at(14)),
    ),
    phone: '(555) 555-0102',
    website: Uri.parse('https://example.com/summit-heating'),
  ),
  ServiceProvider(
    id: 'sample-brightline',
    name: 'BrightLine Electric',
    services: const [ServiceType.electrical],
    address: '503 Main St, Springfield, IL',
    city: 'Springfield, IL',
    rating: 4.9,
    ratingCount: 87,
    distanceMiles: 2.1,
    hours: _weekdays(DayHours(_at(8), _at(16, 30))),
    phone: '(555) 555-0103',
    website: Uri.parse('https://example.com/brightline-electric'),
  ),
  ServiceProvider(
    id: 'sample-maple',
    name: 'Maple Street Appliance Repair',
    services: const [ServiceType.appliance],
    address: '27 Maple St, Sherman, IL',
    city: 'Sherman, IL',
    rating: 4.3,
    ratingCount: 64,
    distanceMiles: 0.8,
    hours: _weekdays(
      DayHours(_at(9), _at(17)),
      saturday: DayHours(_at(9), _at(13)),
    ),
    phone: '(555) 555-0104',
  ),
  ServiceProvider(
    id: 'sample-oak-iron',
    name: 'Oak & Iron Handyman Services',
    services: const [
      ServiceType.handyman,
      ServiceType.plumbing,
      ServiceType.electrical,
    ],
    address: '1150 Cedar Ave, Rochester, IL',
    city: 'Rochester, IL',
    rating: 4.5,
    ratingCount: 141,
    distanceMiles: 4.7,
    hours: _weekdays(
      DayHours(_at(7), _at(19)),
      saturday: DayHours(_at(8), _at(17)),
      sunday: DayHours(_at(10), _at(16)),
    ),
    phone: '(555) 555-0105',
    website: Uri.parse('https://example.com/oak-and-iron'),
  ),
  ServiceProvider(
    id: 'sample-greenscape',
    name: 'GreenScape Lawn Care',
    services: const [ServiceType.landscaping],
    address: '9 Meadow Ln, Riverton, IL',
    city: 'Riverton, IL',
    rating: 4.1,
    ratingCount: 53,
    distanceMiles: 5.9,
    hours: _weekdays(
      DayHours(_at(8), _at(17)),
      saturday: DayHours(_at(8), _at(12)),
    ),
    phone: '(555) 555-0106',
    website: Uri.parse('https://example.com/greenscape'),
  ),
  ServiceProvider(
    id: 'sample-topcoat',
    name: 'TopCoat Roofing',
    services: const [ServiceType.roofing],
    address: '640 Industrial Pkwy, Springfield, IL',
    city: 'Springfield, IL',
    rating: 3.8,
    ratingCount: 29,
    distanceMiles: 7.3,
    hours: _weekdays(DayHours(_at(7), _at(17))),
    phone: '(555) 555-0107',
    website: Uri.parse('https://example.com/topcoat-roofing'),
  ),
  ServiceProvider(
    id: 'sample-clearwater',
    name: 'Clearwater Water Heater Pros',
    services: const [ServiceType.plumbing, ServiceType.hvac],
    address: '311 Lake Dr, Chatham, IL',
    city: 'Chatham, IL',
    rating: 4.4,
    ratingCount: 76,
    distanceMiles: 2.9,
    hours: _everyDay(DayHours(_at(6), _at(22))),
    phone: '(555) 555-0108',
  ),
  ServiceProvider(
    id: 'sample-guardian',
    name: 'Guardian Pest Solutions',
    services: const [ServiceType.pestControl],
    address: '72 Birch St, Auburn, IL',
    city: 'Auburn, IL',
    rating: 4.7,
    ratingCount: 220,
    distanceMiles: 3.8,
    hours: _weekdays(DayHours(_at(8), _at(18))),
    phone: '(555) 555-0109',
    website: Uri.parse('https://example.com/guardian-pest'),
  ),
  ServiceProvider(
    id: 'sample-precision',
    name: 'Precision Auto Care',
    services: const [ServiceType.auto],
    address: '2001 Highway 9, Springfield, IL',
    city: 'Springfield, IL',
    rating: 4.2,
    ratingCount: 405,
    distanceMiles: 6.2,
    hours: _weekdays(
      DayHours(_at(7, 30), _at(18)),
      saturday: DayHours(_at(8), _at(16)),
    ),
    phone: '(555) 555-0110',
    website: Uri.parse('https://example.com/precision-auto'),
  ),
  ServiceProvider(
    id: 'sample-comfort-zone',
    name: 'Comfort Zone HVAC',
    services: const [ServiceType.hvac],
    address: '415 Pine St, Springfield, IL',
    city: 'Springfield, IL',
    rating: 3.6,
    ratingCount: 18,
    distanceMiles: 1.9,
    phone: '(555) 555-0111',
  ),
  ServiceProvider(
    id: 'sample-handy-hank',
    name: 'Handy Neighbor Home Repair',
    services: const [
      ServiceType.handyman,
      ServiceType.appliance,
      ServiceType.roofing,
    ],
    address: '58 Willow Ct, Sherman, IL',
    city: 'Sherman, IL',
    rating: 4.6,
    ratingCount: 39,
    distanceMiles: 2.4,
    hours: _weekdays(
      DayHours(_at(8), _at(18)),
      saturday: DayHours(_at(9), _at(15)),
    ),
    phone: '(555) 555-0112',
    website: Uri.parse('https://example.com/handy-neighbor'),
  ),
  ServiceProvider(
    id: 'sample-volt',
    name: 'Volt Masters Electrical',
    services: const [ServiceType.electrical],
    address: '980 Commerce Blvd, Williamsville, IL',
    city: 'Williamsville, IL',
    rating: 4.0,
    ratingCount: 112,
    distanceMiles: 8.6,
    hours: _weekdays(DayHours(_at(8), _at(17))),
    phone: '(555) 555-0113',
  ),
  ServiceProvider(
    id: 'sample-new',
    name: 'Fresh Start Drain Cleaning',
    services: const [ServiceType.plumbing],
    address: '12 Spring St, Rochester, IL',
    city: 'Rochester, IL',
    distanceMiles: 3.1,
    hours: _everyDay(DayHours(_at(7), _at(21))),
    phone: '(555) 555-0114',
  ),
];
