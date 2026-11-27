import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometrackhub/data/settings_repository.dart';
import 'package:hometrackhub/models/app_settings.dart';
import 'package:hometrackhub/models/service_provider.dart';
import 'package:hometrackhub/models/service_sort.dart';
import 'package:hometrackhub/models/service_type.dart';
import 'package:hometrackhub/services/location_service.dart';
import 'package:hometrackhub/services/nearby_services_client.dart';
import 'package:hometrackhub/state/nearby_services_controller.dart';
import 'package:hometrackhub/state/settings_controller.dart';
import 'package:hometrackhub/ui/screens/assist/nearby_services_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Open all day and night, every day.
const _openAllDay = {
  DateTime.monday: DayHours.allDay(),
  DateTime.tuesday: DayHours.allDay(),
  DateTime.wednesday: DayHours.allDay(),
  DateTime.thursday: DayHours.allDay(),
  DateTime.friday: DayHours.allDay(),
  DateTime.saturday: DayHours.allDay(),
  DateTime.sunday: DayHours.allDay(),
};

/// Open from 8 AM to 5:30 PM on weekdays, and closed at the weekend.
const _officeHours = {
  DateTime.monday: DayHours(
    TimeOfDay(hour: 8, minute: 0),
    TimeOfDay(hour: 17, minute: 30),
  ),
  DateTime.tuesday: DayHours(
    TimeOfDay(hour: 8, minute: 0),
    TimeOfDay(hour: 17, minute: 30),
  ),
  DateTime.wednesday: DayHours(
    TimeOfDay(hour: 8, minute: 0),
    TimeOfDay(hour: 17, minute: 30),
  ),
  DateTime.thursday: DayHours(
    TimeOfDay(hour: 8, minute: 0),
    TimeOfDay(hour: 17, minute: 30),
  ),
  DateTime.friday: DayHours(
    TimeOfDay(hour: 8, minute: 0),
    TimeOfDay(hour: 17, minute: 30),
  ),
};

const _plumber = ServiceProvider(
  id: 'plumber',
  name: 'Pipe Pros',
  services: [ServiceType.plumbing],
  address: '1 Main St',
  rating: 4.2,
  ratingCount: 300,
  distanceMiles: 5,
  hours: _openAllDay,
);

const _electrician = ServiceProvider(
  id: 'electrician',
  name: 'Spark Electric',
  services: [ServiceType.electrical],
  address: '2 Main St',
  rating: 4.9,
  ratingCount: 40,
  distanceMiles: 1,
  // Closed every day.
  hours: {},
);

const _handyman = ServiceProvider(
  id: 'handyman',
  name: 'Fix It All',
  services: [ServiceType.handyman, ServiceType.plumbing],
  address: '3 Main St',
  ratingCount: 0,
  distanceMiles: 2,
);

/// A client whose searches finish only when the test completes them, and
/// which records what was searched for.
class _ControlledClient implements NearbyServicesClient {
  final searches = <({String query, ServiceType? service})>[];

  /// The area each search was around, in the same order as [searches].
  final areas = <SearchArea?>[];
  final _pending = <Completer<List<ServiceProvider>>>[];

  @override
  bool get isSample => false;

  @override
  Future<List<ServiceProvider>> search({
    String query = '',
    ServiceType? service,
    SearchArea? area,
  }) {
    searches.add((query: query, service: service));
    areas.add(area);
    final completer = Completer<List<ServiceProvider>>();
    _pending.add(completer);
    return completer.future;
  }

  void finish(int index, List<ServiceProvider> results) =>
      _pending[index].complete(results);
}

class _FailingClient implements NearbyServicesClient {
  @override
  bool get isSample => false;

  @override
  Future<List<ServiceProvider>> search({
    String query = '',
    ServiceType? service,
    SearchArea? area,
  }) async => throw const NearbyServicesException('No connection.');
}

/// Real-looking results, as if from Google.
class _GoogleLikeClient implements NearbyServicesClient {
  @override
  bool get isSample => false;

  @override
  Future<List<ServiceProvider>> search({
    String query = '',
    ServiceType? service,
    SearchArea? area,
  }) async => [_plumber, _electrician];
}

/// Like [_GoogleLikeClient], also recording the area of each search.
class _AreaRecordingClient extends _GoogleLikeClient {
  final areas = <SearchArea?>[];

  @override
  Future<List<ServiceProvider>> search({
    String query = '',
    ServiceType? service,
    SearchArea? area,
  }) {
    areas.add(area);
    return super.search(query: query, service: service, area: area);
  }
}

/// A client that fails in a way it doesn't explain, as a dropped connection
/// might.
class _BrokenClient implements NearbyServicesClient {
  @override
  bool get isSample => false;

  @override
  Future<List<ServiceProvider>> search({
    String query = '',
    ServiceType? service,
    SearchArea? area,
  }) async => throw Exception('Connection closed while receiving data.');
}

/// A device that's at [location], or whose location can't be found when
/// it's `null`. Counts how often it's asked.
class FakeLocationService implements LocationService {
  FakeLocationService([this.location = (latitude: 39.8, longitude: -89.6)]);

  Coordinates? location;
  int requests = 0;

  @override
  Future<Coordinates> currentLocation() async {
    requests++;
    return location ??
        (throw const LocationException('Location is turned off.'));
  }
}

void main() {
  NearbyServicesController createController([NearbyServicesClient? client]) =>
      NearbyServicesController(
        client ??
            SampleNearbyServicesClient(
              delay: Duration.zero,
              providers: const [_plumber, _electrician, _handyman],
            ),
        debounce: Duration.zero,
      );

  List<String> ids(NearbyServicesController controller) => [
    for (final provider in controller.providers) provider.id,
  ];

  group('NearbyServicesController', () {
    test('lists businesses top rated first, unrated last', () async {
      final controller = createController();
      await controller.search();

      expect(controller.searched, isTrue);
      expect(ids(controller), ['electrician', 'plumber', 'handyman']);
    });

    test('sorts by distance and by number of reviews', () async {
      final controller = createController();
      await controller.search();

      controller.setSort(ServiceSort.distance);
      expect(ids(controller), ['electrician', 'handyman', 'plumber']);

      controller.setSort(ServiceSort.reviews);
      expect(ids(controller), ['plumber', 'electrician', 'handyman']);
    });

    test('pinned businesses come first in any order, still filtered', () async {
      final controller = createController();
      await controller.search();
      expect(ids(controller), ['electrician', 'plumber', 'handyman']);

      controller.setPinnedIds({'handyman'});
      expect(ids(controller), ['handyman', 'electrician', 'plumber']);
      controller.setSort(ServiceSort.reviews);
      expect(ids(controller), ['handyman', 'plumber', 'electrician']);

      // Pinned businesses are in the sort order among themselves.
      controller.setPinnedIds({'handyman', 'electrician'});
      expect(ids(controller), ['electrician', 'handyman', 'plumber']);

      // The filters still hide them.
      controller.setMinRating(4.0);
      expect(ids(controller), ['electrician', 'plumber']);
    });

    test('can start out searching for a service', () async {
      final client = _ControlledClient();
      final controller = NearbyServicesController(
        client,
        debounce: Duration.zero,
        initialService: ServiceType.plumbing,
      );

      controller.search();
      expect(controller.service, ServiceType.plumbing);
      expect(client.searches.single.service, ServiceType.plumbing);
    });

    test('picking a service searches for businesses that offer it', () async {
      final client = _ControlledClient();
      final controller = createController(client);

      controller.setService(ServiceType.plumbing);
      expect(client.searches.single.service, ServiceType.plumbing);
      client.finish(0, [_plumber, _handyman]);
      await pumpEventQueue();

      expect(ids(controller), ['plumber', 'handyman']);
    });

    test('typing searches once the user pauses', () async {
      final client = _ControlledClient();
      final controller = createController(client);

      controller.setQuery('s');
      controller.setQuery('spark ');
      await pumpEventQueue();

      expect(client.searches, [(query: 'spark', service: null)]);
    });

    test('filters hide unrated, low rated and closed businesses', () async {
      final controller = createController();
      await controller.search();

      controller.setMinRating(4.5);
      expect(ids(controller), ['electrician']);
      expect(controller.hiddenCount, 2);

      controller.setMinRating(null);
      controller.setOpenNowOnly(true);
      expect(ids(controller), ['plumber']);

      controller.clearFilters();
      expect(controller.hasFilters, isFalse);
      expect(controller.hiddenCount, 0);
    });

    test('open now follows the time of day', () async {
      var now = DateTime(2026, 11, 2, 9); // A Monday morning.
      final controller = NearbyServicesController(
        SampleNearbyServicesClient(
          delay: Duration.zero,
          providers: const [
            _plumber,
            ServiceProvider(
              id: 'office',
              name: 'Desk Hours Repair',
              services: [ServiceType.appliance],
              address: '5 Main St',
              hours: _officeHours,
            ),
          ],
        ),
        debounce: Duration.zero,
        clock: () => now,
      );
      await controller.search();
      controller.setOpenNowOnly(true);
      expect(ids(controller), ['plumber', 'office']);

      now = DateTime(2026, 11, 2, 17, 30); // Closing time.
      expect(ids(controller), ['plumber']);

      now = DateTime(2026, 11, 7, 10); // Saturday.
      expect(ids(controller), ['plumber']);
    });

    test('starts in the sort order it was given', () async {
      final controller = NearbyServicesController(
        SampleNearbyServicesClient(
          delay: Duration.zero,
          providers: const [_plumber, _electrician, _handyman],
        ),
        initialSort: ServiceSort.distance,
      );
      await controller.search();

      expect(controller.sort, ServiceSort.distance);
      expect(ids(controller), ['electrician', 'handyman', 'plumber']);
    });

    test(
      'finds the area to search around once, and again after failing',
      () async {
        final client = _ControlledClient();
        final location = FakeLocationService(null);
        final settings = const AppSettings();
        final controller = NearbyServicesController(
          client,
          debounce: Duration.zero,
          locate: () => searchAreaFor(settings, location),
        );

        await controller.search();
        expect(controller.error, 'Location is turned off.');
        expect(controller.errorFixInSettings, isTrue);
        expect(client.searches, isEmpty);

        location.location = (latitude: 39.8, longitude: -89.6);
        final first = controller.search();
        await pumpEventQueue();
        client.finish(0, [_plumber]);
        await first;
        final second = controller.search();
        await pumpEventQueue();
        client.finish(1, [_plumber]);
        await second;

        expect(location.requests, 2);
        expect(
          client.areas.map((area) => (area! as SearchAroundPoint).latitude),
          [39.8, 39.8],
        );
        expect(controller.error, isNull);

        final third = controller.relocate();
        await pumpEventQueue();
        client.finish(2, [_plumber]);
        await third;
        expect(location.requests, 3);
      },
    );

    test('sample searches never ask where the device is', () async {
      final location = FakeLocationService();
      final controller = NearbyServicesController(
        SampleNearbyServicesClient(delay: Duration.zero),
        locate: () => searchAreaFor(const AppSettings(), location),
      );
      await controller.search();

      expect(location.requests, 0);
      expect(controller.providers, isNotEmpty);
    });

    test('a search that finishes late is ignored', () async {
      final client = _ControlledClient();
      final controller = createController(client);

      controller.search();
      controller.setService(ServiceType.electrical);
      client.finish(1, [_electrician]);
      client.finish(0, [_plumber, _electrician, _handyman]);
      await pumpEventQueue();

      expect(ids(controller), ['electrician']);
      expect(controller.loading, isFalse);
    });

    test('a search that fails unexpectedly still finishes', () async {
      final controller = createController(_BrokenClient());
      await controller.search();

      expect(controller.loading, isFalse);
      expect(controller.searched, isTrue);
      expect(
        controller.error,
        'The search ran into a problem. Please try again.',
      );
    });

    test('a failed search shows why', () async {
      final controller = createController(_FailingClient());
      await controller.search();

      expect(controller.error, 'No connection.');
      expect(controller.providers, isEmpty);
    });
  });

  group('DayHours', () {
    test('is open from opening time until closing time', () {
      const hours = DayHours(
        TimeOfDay(hour: 8, minute: 0),
        TimeOfDay(hour: 17, minute: 30),
      );
      expect(hours.isOpenAt(const TimeOfDay(hour: 7, minute: 59)), isFalse);
      expect(hours.isOpenAt(const TimeOfDay(hour: 8, minute: 0)), isTrue);
      expect(hours.isOpenAt(const TimeOfDay(hour: 17, minute: 29)), isTrue);
      expect(hours.isOpenAt(const TimeOfDay(hour: 17, minute: 30)), isFalse);
    });

    test('hours can run past midnight', () {
      const hours = DayHours(
        TimeOfDay(hour: 18, minute: 0),
        TimeOfDay(hour: 2, minute: 0),
      );
      expect(hours.isOpenAt(const TimeOfDay(hour: 23, minute: 0)), isTrue);
      expect(hours.isOpenAt(const TimeOfDay(hour: 1, minute: 0)), isTrue);
      expect(hours.isOpenAt(const TimeOfDay(hour: 12, minute: 0)), isFalse);
    });
  });

  group('SampleNearbyServicesClient', () {
    test('matches every word against names and services', () async {
      final client = SampleNearbyServicesClient(delay: Duration.zero);

      final heaters = await client.search(query: 'water heater');
      expect(heaters.map((provider) => provider.name), [
        'Clearwater Water Heater Pros',
      ]);

      final electricians = await client.search(service: ServiceType.electrical);
      expect(
        electricians.every(
          (provider) => provider.services.contains(ServiceType.electrical),
        ),
        isTrue,
      );
      expect(electricians, hasLength(3));
    });
  });

  group('NearbyServicesScreen', () {
    Future<void> pumpScreen(
      WidgetTester tester, {
      List<ServiceProvider>? providers,
      NearbyServicesClient? client,
      AppSettings settings = const AppSettings(),
    }) async {
      SharedPreferences.setMockInitialValues({});
      final repository = SettingsRepository(
        await SharedPreferences.getInstance(),
      );
      await repository.save(settings);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => SettingsController(repository),
            ),
            Provider<LocationService>.value(value: FakeLocationService()),
            Provider<NearbyServicesClient>.value(
              value:
                  client ??
                  SampleNearbyServicesClient(
                    delay: Duration.zero,
                    providers: providers,
                  ),
            ),
          ],
          child: const MaterialApp(home: NearbyServicesScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// Scrolls the row of service chips to [label]'s chip and taps it. The
    /// row scrolls toward the end unless [backward].
    Future<void> tapService(
      WidgetTester tester,
      String label, {
      bool backward = false,
    }) async {
      final chip = find.widgetWithText(ChoiceChip, label);
      await tester.dragUntilVisible(
        chip,
        find.byWidgetPredicate(
          (widget) =>
              widget is ListView && widget.scrollDirection == Axis.horizontal,
        ),
        Offset(backward ? 200 : -200, 0),
      );
      await tester.tap(chip);
      await tester.pumpAndSettle();
    }

    Future<void> toggleFilters(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();
    }

    testWidgets('follows changes to where to search and the default sort', (
      tester,
    ) async {
      final client = _AreaRecordingClient();
      await pumpScreen(
        tester,
        client: client,
        settings: const AppSettings(
          nearbyLocationSource: NearbyLocationSource.zipCode,
          nearbyZipCode: '62701',
        ),
      );
      final settings = Provider.of<SettingsController>(
        tester.element(find.byType(NearbyServicesScreen)),
        listen: false,
      );
      List<String> zipCodes() => [
        for (final area in client.areas) (area! as SearchAroundZipCode).zipCode,
      ];
      double top(String name) => tester.getTopLeft(find.text(name)).dy;
      expect(zipCodes(), ['62701']);
      expect(top('Spark Electric'), lessThan(top('Pipe Pros')));

      // As when it's changed from the Settings tab while this stays open.
      await settings.update(settings.settings.copyWith(nearbyZipCode: '62702'));
      await tester.pumpAndSettle();
      expect(zipCodes(), ['62701', '62702']);

      // The default sort reorders the results without searching again.
      await settings.update(
        settings.settings.copyWith(nearbySort: ServiceSort.reviews),
      );
      await tester.pumpAndSettle();
      expect(top('Pipe Pros'), lessThan(top('Spark Electric')));

      // Other settings change nothing here.
      await settings.update(
        settings.settings.copyWith(assistantEnabled: false),
      );
      await tester.pumpAndSettle();
      expect(client.areas, hasLength(2));
    });

    testWidgets('lists sample businesses with their ratings', (tester) async {
      await pumpScreen(tester);

      expect(find.textContaining('sample businesses'), findsOneWidget);
      expect(find.text('BrightLine Electric'), findsOneWidget);
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('Summit Heating & Air'),
            matching: find.byType(Card),
          ),
          matching: find.text('Chatham, IL'),
        ),
        findsOneWidget,
      );
      // Without pictures, the cards show their service's icon, and no
      // distance.
      expect(find.text('2.1 mi'), findsNothing);
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('BrightLine Electric'),
            matching: find.byType(Card),
          ),
          matching: find.byIcon(Icons.electrical_services),
        ),
        findsOneWidget,
      );
      // Sample results aren't from Google.
      expect(find.bySemanticsLabel('Google Maps'), findsNothing);
      expect(find.text('87 reviews'), findsOneWidget);
      expect(
        // Read aloud as part of the whole card.
        find.bySemanticsLabel(RegExp('Rated 4.9 out of 5 from 87 reviews')),
        findsOneWidget,
      );
      // The card doesn't list the services, and the filters start hidden.
      expect(find.text('Electrical'), findsNothing);
      expect(find.byTooltip('Show filters'), findsOneWidget);
    });

    testWidgets('filters by service and searches by name', (tester) async {
      await pumpScreen(tester);
      await toggleFilters(tester);

      await tapService(tester, 'Pest control');
      expect(find.text('Guardian Pest Solutions'), findsOneWidget);
      expect(find.text('BrightLine Electric'), findsNothing);

      // The filters button counts the filters in use once they're hidden.
      await toggleFilters(tester);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.text('1'), findsOneWidget);
      await toggleFilters(tester);

      await tapService(tester, 'All', backward: true);
      await tester.enterText(find.byType(SearchBar), 'riverbend');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('Riverbend Plumbing & Drain'), findsOneWidget);
      expect(find.text('Guardian Pest Solutions'), findsNothing);
    });

    testWidgets('every card is the same height, however long the name', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      const longName =
          'The Very Long Name Home Repair, Plumbing, Heating and Cooling '
          'Company of Greater Springfield';
      await pumpScreen(
        tester,
        providers: const [
          _plumber,
          // No opening hours.
          _handyman,
          ServiceProvider(
            id: 'long',
            name: longName,
            services: [ServiceType.hvac],
            address: '4 Main St',
            rating: 4,
            ratingCount: 10,
            hours: _openAllDay,
          ),
        ],
      );

      double cardHeight(String name) => tester
          .getSize(
            find.ancestor(of: find.text(name), matching: find.byType(Card)),
          )
          .height;
      final height = cardHeight('Pipe Pros');
      expect(cardHeight('Fix It All'), height);
      expect(cardHeight(longName), height);

      // Businesses without a picture show their main service's icon.
      expect(find.byIcon(Icons.plumbing), findsOneWidget);
      expect(find.byIcon(Icons.hvac), findsOneWidget);

      final longText = tester.widget<Text>(find.text(longName));
      expect(longText.maxLines, 2);
      expect(longText.overflow, TextOverflow.ellipsis);
    });

    testWidgets(
      'details say whether a business is open, with hours for today',
      (tester) async {
        final today = DateTime.now().weekday;
        await pumpScreen(
          tester,
          providers: [
            _plumber,
            _electrician,
            _handyman,
            ServiceProvider(
              id: 'office',
              name: 'Desk Hours Repair',
              services: const [ServiceType.appliance],
              address: '5 Main St',
              hours: {
                today: const DayHours(
                  TimeOfDay(hour: 8, minute: 0),
                  TimeOfDay(hour: 17, minute: 30),
                ),
              },
            ),
          ],
        );

        // Fix It All has no reviews, so its card shows no rating at all.
        expect(find.textContaining('review'), findsNWidgets(2));
        // The cards leave out the hours.
        expect(find.text('Open 24 hours'), findsNothing);

        Future<void> expectInDetails(String name, Finder hours) async {
          await tester.tap(find.text(name));
          await tester.pumpAndSettle();
          expect(hours, findsOneWidget);
          // Closes the details by tapping above them.
          await tester.tapAt(const Offset(20, 20));
          await tester.pumpAndSettle();
        }

        await expectInDetails('Pipe Pros', find.text('Open 24 hours'));
        await expectInDetails('Spark Electric', find.text('Closed today'));
        // Open or closed depending on when the test runs, but always with
        // today's hours.
        await expectInDetails('Desk Hours Repair', find.text('8 AM – 5:30 PM'));
      },
    );

    testWidgets('tapping a business shows its details', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('BrightLine Electric'));
      await tester.pumpAndSettle();

      expect(find.text('503 Main St, Springfield, IL'), findsOneWidget);
      // The call button shows the number, and directions the distance, so
      // they aren't listed separately too.
      final call = find.text('(555) 555-0103');
      final directions = find.text('2.1 miles');
      final website = find.text('Website');
      final pin = find.text('Pin to top');
      expect(call, findsOneWidget);
      expect(directions, findsOneWidget);
      expect(find.textContaining('away'), findsNothing);
      // Read aloud with what they do.
      expect(find.bySemanticsLabel('Call (555) 555-0103'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Directions, 2.1 miles away'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Pin to top of results'), findsOneWidget);
      // What it does is said by the rating and its name, not by tags.
      expect(find.byType(Chip), findsNothing);

      // One card: what the business is, then under a line, where it is.
      Finder inDetails(Finder finder) =>
          find.descendant(of: find.byType(BottomSheet), matching: finder);
      final cards = inDetails(find.byType(Card));
      expect(cards, findsOneWidget);
      Finder inCard(Finder finder) =>
          find.descendant(of: cards, matching: finder);
      final name = inCard(find.text('BrightLine Electric'));
      final address = inCard(find.text('503 Main St, Springfield, IL'));
      final line = inCard(find.byType(Divider));
      expect(inCard(find.text('4.9')), findsOneWidget);
      expect(line, findsOneWidget);
      expect(
        tester.getCenter(line).dy,
        allOf(
          greaterThan(tester.getBottomLeft(name).dy),
          lessThan(tester.getTopLeft(address).dy),
        ),
      );

      // The buttons are below the cards. Calling and directions share the
      // first line, half each, and the others are on lines of their own,
      // as wide as the cards.
      final detailsWidth = tester.getSize(cards).width;
      Rect button(Finder label) => tester.getRect(
        find.ancestor(of: label, matching: find.byType(FilledButton)),
      );
      expect(button(directions).center.dy, button(call).center.dy);
      expect(button(directions).left, greaterThan(button(call).right));
      expect(
        button(call).width + button(directions).width,
        lessThan(detailsWidth),
      );
      expect(button(call).top, greaterThan(tester.getRect(cards).bottom));
      expect(button(website).top, greaterThan(button(call).bottom));
      expect(button(pin).top, greaterThan(button(website).bottom));
      expect(button(website).width, detailsWidth);
      expect(button(pin).width, detailsWidth);
      for (final label in [call, directions, website, pin]) {
        expect(
          inDetails(find.ancestor(of: label, matching: find.byType(Card))),
          findsNothing,
        );
      }

      // The rating and number of reviews are above the stars, and whether
      // it's open is on the right.
      final rating = inDetails(find.text('4.9'));
      final status = inDetails(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              ['Open now', 'Closed', 'Closed today'].contains(widget.data),
        ),
      );
      expect(
        tester.getCenter(rating).dy,
        lessThan(tester.getCenter(inDetails(find.byIcon(Icons.star)).first).dy),
      );
      final reviews = inDetails(find.text(' (87)'));
      expect(
        tester.getBottomLeft(reviews).dy,
        closeTo(tester.getBottomLeft(rating).dy, 4),
      );
      expect(
        tester.getTopLeft(reviews).dx,
        greaterThanOrEqualTo(tester.getTopRight(rating).dx),
      );
      expect(
        tester.getTopLeft(status).dx,
        greaterThan(tester.getTopRight(reviews).dx),
      );
    });

    testWidgets('a business without a known distance or phone still has '
        'directions', (tester) async {
      await pumpScreen(
        tester,
        providers: const [
          ServiceProvider(
            id: 'far',
            name: 'Somewhere Repairs',
            services: [ServiceType.handyman],
            address: '9 Far Rd',
          ),
        ],
      );

      await tester.tap(find.text('Somewhere Repairs'));
      await tester.pumpAndSettle();

      expect(find.text('Directions'), findsOneWidget);
      expect(find.byIcon(Icons.call), findsNothing);
    });

    testWidgets('a business pinned from its details is listed first', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        providers: const [_plumber, _electrician, _handyman],
      );
      double top(String name) => tester.getTopLeft(find.text(name)).dy;
      final settings = Provider.of<SettingsController>(
        tester.element(find.byType(NearbyServicesScreen)),
        listen: false,
      );
      Future<void> togglePin(String name, String button) async {
        await tester.tap(find.text(name));
        await tester.pumpAndSettle();
        await tester.tap(find.text(button));
        await tester.pumpAndSettle();
        Navigator.of(tester.element(find.text(name).last)).pop();
        await tester.pumpAndSettle();
      }

      // Unrated, so it starts last.
      expect(top('Fix It All'), greaterThan(top('Pipe Pros')));
      expect(find.byIcon(Icons.push_pin), findsNothing);

      await togglePin('Fix It All', 'Pin to top');
      expect(top('Fix It All'), lessThan(top('Spark Electric')));
      // Read out with the card.
      expect(find.bySemanticsLabel(RegExp('Pinned')), findsOneWidget);
      // Kept in the settings, so it stays pinned in later searches.
      expect(settings.settings.pinnedBusinessIds, ['handyman']);

      await togglePin('Fix It All', 'Unpin');
      expect(top('Fix It All'), greaterThan(top('Pipe Pros')));
      expect(find.bySemanticsLabel(RegExp('Pinned')), findsNothing);
      expect(settings.settings.pinnedBusinessIds, isEmpty);
    });

    testWidgets("Google's results end with Google's logo", (tester) async {
      await pumpScreen(tester, client: _GoogleLikeClient());

      expect(find.textContaining('sample businesses'), findsNothing);
      expect(find.bySemanticsLabel('Google Maps'), findsOneWidget);
      final logo = tester.widget<Image>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.image is AssetImage &&
              (widget.image as AssetImage).assetName.contains('google_maps'),
        ),
      );
      expect(logo.height, inInclusiveRange(16, 19));
    });

    testWidgets('starts in the default sort from settings', (tester) async {
      await pumpScreen(
        tester,
        settings: const AppSettings(nearbySort: ServiceSort.reviews),
      );
      await toggleFilters(tester);

      // The sort button shows the order the results are in.
      expect(find.text(ServiceSort.reviews.label), findsOneWidget);
    });

    testWidgets('a missing ZIP code can be added from the error', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        client: _FailingClient(),
        settings: const AppSettings(
          nearbyLocationSource: NearbyLocationSource.zipCode,
        ),
      );

      expect(find.textContaining('Add the ZIP code'), findsOneWidget);
      await tester.tap(find.text('Nearby services settings'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '62701');
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Searches again near the new ZIP code, which this client fails.
      expect(find.text('No connection.'), findsOneWidget);
    });

    testWidgets('says when filters hide every business', (tester) async {
      await pumpScreen(tester, providers: const [_plumber, _electrician]);
      await toggleFilters(tester);

      await tapService(tester, 'Electrical');
      await tester.tap(find.text('Any rating'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('4.5 stars and up'));
      await tester.pumpAndSettle();
      expect(find.text('Spark Electric'), findsOneWidget);

      // The only electrician is closed.
      await tester.tap(find.text('Open now'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No businesses match'), findsOneWidget);

      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(find.text('Spark Electric'), findsOneWidget);
      expect(find.text('Any rating'), findsOneWidget);
    });
  });
}
