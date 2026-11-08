import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometrackhub/data/settings_repository.dart';
import 'package:hometrackhub/models/app_settings.dart';
import 'package:hometrackhub/models/service_sort.dart';
import 'package:hometrackhub/models/service_type.dart';
import 'package:hometrackhub/services/google_places_client.dart';
import 'package:hometrackhub/services/nearby_services_client.dart';
import 'package:hometrackhub/state/nearby_services_controller.dart';
import 'package:hometrackhub/state/settings_controller.dart';
import 'package:hometrackhub/ui/screens/settings/nearby_services_settings_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'nearby_services_test.dart' show FakeLocationService;

/// A plumber in Springfield as the server sends it: Google's fields, with
/// zero values left out as Google does.
const _plumberPlace = {
  'id': 'abc123',
  'displayName': {'text': 'Lincoln Land Plumbing', 'languageCode': 'en'},
  'formattedAddress': '100 S 5th St, Springfield, IL 62701, USA',
  'addressComponents': [
    {
      'longText': 'Springfield',
      'shortText': 'Springfield',
      'types': ['locality', 'political'],
    },
    {
      'longText': 'Illinois',
      'shortText': 'IL',
      'types': ['administrative_area_level_1', 'political'],
    },
  ],
  'location': {'latitude': 39.80, 'longitude': -89.65},
  'types': ['plumber', 'point_of_interest', 'establishment'],
  'rating': 4.6,
  'userRatingCount': 212,
  'regularOpeningHours': {
    'periods': [
      // Monday, with a lunch break.
      {
        'open': {'day': 1, 'hour': 8},
        'close': {'day': 1, 'hour': 12},
      },
      {
        'open': {'day': 1, 'hour': 13},
        'close': {'day': 1, 'hour': 17, 'minute': 30},
      },
      // Friday night, closing after midnight.
      {
        'open': {'day': 5, 'hour': 18},
        'close': {'day': 6, 'hour': 2},
      },
      // All of Sunday, which Google numbers 0.
      {
        'open': {},
        'close': {'day': 0, 'hour': 23, 'minute': 59},
      },
    ],
  },
  'nationalPhoneNumber': '(217) 555-0123',
  'websiteUri': 'https://example.com/plumbing',
  'googleMapsUri': 'https://maps.google.com/?cid=1',
  'photos': [
    {
      'name': 'places/abc123/photos/photo1',
      'authorAttributions': [
        {
          'displayName': 'Jamie Rivera',
          'uri': '//maps.google.com/maps/contrib/1',
        },
      ],
    },
  ],
};

/// [value] as it arrives from the server: decoded JSON, with its maps and
/// lists typed the way [jsonDecode] types them.
Map<String, dynamic> _json(Map<String, Object?> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

ImageProvider _fakePhoto(String name) =>
    AssetImage('test/$name', package: 'photos');

void main() {
  group('providersFromResponse', () {
    test('turns a Google place into a business', () {
      final providers = providersFromResponse(
        _json({
          'origin': {'latitude': 39.78, 'longitude': -89.65},
          'places': [_plumberPlace],
        }),
        photoFor: _fakePhoto,
      );
      final plumber = providers.single;

      expect(plumber.id, 'abc123');
      expect(plumber.name, 'Lincoln Land Plumbing');
      expect(plumber.address, '100 S 5th St, Springfield, IL 62701');
      expect(plumber.city, 'Springfield, IL');
      expect(plumber.services, [ServiceType.plumbing]);
      expect(plumber.rating, 4.6);
      expect(plumber.ratingCount, 212);
      expect(plumber.phone, '(217) 555-0123');
      expect(plumber.website, Uri.parse('https://example.com/plumbing'));
      expect(plumber.mapsLink, Uri.parse('https://maps.google.com/?cid=1'));
      // 0.02 degrees of latitude is about 1.4 miles.
      expect(plumber.distanceMiles, closeTo(1.38, 0.01));

      expect(
        plumber.photo,
        const AssetImage('test/places/abc123/photos/photo1', package: 'photos'),
      );
      expect(plumber.photoCredits.single.name, 'Jamie Rivera');
      expect(
        plumber.photoCredits.single.link,
        Uri.parse('https://maps.google.com/maps/contrib/1'),
      );
    });

    test('reads opening hours, breaks and all', () {
      final hours = providersFromResponse(
        _json({
          'places': [_plumberPlace],
        }),
        photoFor: _fakePhoto,
      ).single.hours!;

      // The lunch break is left out: open from the first opening to the
      // last closing.
      expect(
        hours[DateTime.monday]!.opens,
        const TimeOfDay(hour: 8, minute: 0),
      );
      expect(
        hours[DateTime.monday]!.closes,
        const TimeOfDay(hour: 17, minute: 30),
      );
      expect(
        hours[DateTime.friday]!.isOpenAt(const TimeOfDay(hour: 1, minute: 0)),
        isTrue,
      );
      expect(hours[DateTime.sunday]!.allDay, isTrue);
      expect(hours.containsKey(DateTime.tuesday), isFalse);
    });

    test('a business that never closes is open all day every day', () {
      final hours = providersFromResponse(
        _json({
          'places': [
            {
              ..._plumberPlace,
              'regularOpeningHours': {
                'periods': [
                  {'open': {}},
                ],
              },
            },
          ],
        }),
        photoFor: _fakePhoto,
      ).single.hours!;

      expect(hours.length, 7);
      expect(hours.values.every((day) => day.allDay), isTrue);
    });

    test('leaves out what Google doesn\'t know', () {
      final provider = providersFromResponse(
        _json({
          'places': [
            {
              'id': 'bare',
              'displayName': {'text': 'Bare Bones Repair'},
            },
          ],
        }),
        service: ServiceType.appliance,
        photoFor: _fakePhoto,
      ).single;

      expect(provider.services, [ServiceType.appliance]);
      expect(provider.rating, isNull);
      expect(provider.hours, isNull);
      expect(provider.city, isNull);
      expect(provider.distanceMiles, isNull);
      expect(provider.photo, isNull);
    });

    test('a response laid out differently is an error', () {
      expect(
        () => providersFromResponse(
          _json({
            'places': [
              {'id': 7},
            ],
          }),
          photoFor: _fakePhoto,
        ),
        throwsA(isA<NearbyServicesException>()),
      );
    });
  });

  group('GooglePlacesClient', () {
    test('searches for the text and the service together', () {
      expect(
        GooglePlacesClient.searchText('Acme', ServiceType.plumbing),
        'Acme plumber',
      );
      expect(GooglePlacesClient.searchText('  ', null), 'home repair services');
    });

    test('is only set up with an HTTPS address and a token', () {
      expect(
        GooglePlacesClient(
          endpoint: 'https://example.com/places',
          token: 'secret',
        ).isConfigured,
        isTrue,
      );
      expect(
        GooglePlacesClient(
          endpoint: 'http://example.com/places',
          token: 'secret',
        ).isConfigured,
        isFalse,
      );
      expect(
        GooglePlacesClient(
          endpoint: 'https://example.com/places',
          token: '',
        ).isConfigured,
        isFalse,
      );
    });
  });

  group('searchAreaFor', () {
    test('searches around the ZIP code when that is chosen', () async {
      final area = await searchAreaFor(
        const AppSettings(
          nearbyLocationSource: NearbyLocationSource.zipCode,
          nearbyZipCode: '62701',
        ),
        FakeLocationService(),
      );
      expect((area as SearchAroundZipCode).zipCode, '62701');
    });

    test('asks for a ZIP code when there is none', () {
      expect(
        searchAreaFor(
          const AppSettings(nearbyLocationSource: NearbyLocationSource.zipCode),
          FakeLocationService(),
        ),
        throwsA(
          isA<NearbyServicesException>().having(
            (exception) => exception.fixInSettings,
            'fixInSettings',
            isTrue,
          ),
        ),
      );
    });

    test("searches around the device's location by default", () async {
      final area = await searchAreaFor(
        const AppSettings(),
        FakeLocationService((latitude: 40.1, longitude: -88.2)),
      );
      area as SearchAroundPoint;
      expect((area.latitude, area.longitude), (40.1, -88.2));
    });
  });

  group('Nearby services settings', () {
    test('are saved and loaded again', () {
      const settings = AppSettings(
        nearbyLocationSource: NearbyLocationSource.zipCode,
        nearbyZipCode: '62701',
        nearbySort: ServiceSort.distance,
      );
      final loaded = AppSettings.fromJson(settings.toJson());

      expect(loaded.nearbyLocationSource, NearbyLocationSource.zipCode);
      expect(loaded.nearbyZipCode, '62701');
      expect(loaded.nearbySort, ServiceSort.distance);
      expect(
        AppSettings.fromJson({'nearbyZipCode': '627'}).nearbyZipCode,
        isNull,
      );
    });

    Future<SettingsController> pumpSettings(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final controller = SettingsController(
        SettingsRepository(await SharedPreferences.getInstance()),
      );
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: controller,
          child: const MaterialApp(home: NearbyServicesSettingsScreen()),
        ),
      );
      return controller;
    }

    Future<void> choose(
      WidgetTester tester,
      String current,
      String choice,
    ) async {
      await tester.tap(find.text(current));
      await tester.pumpAndSettle();
      await tester.tap(find.text(choice).last);
      await tester.pumpAndSettle();
    }

    testWidgets('a ZIP code can be searched near instead', (tester) async {
      final controller = await pumpSettings(tester);
      expect(find.byType(TextField), findsNothing);

      await choose(tester, 'My location', 'ZIP code');
      expect(
        controller.settings.nearbyLocationSource,
        NearbyLocationSource.zipCode,
      );

      // Not saved until it's all five digits, and only letters are kept out.
      await tester.enterText(find.byType(TextField), '62a7');
      expect(controller.settings.nearbyZipCode, isNull);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(find.text('Enter all 5 digits of the ZIP code.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '62701');
      expect(controller.settings.nearbyZipCode, '62701');

      await tester.enterText(find.byType(TextField), '');
      expect(controller.settings.nearbyZipCode, isNull);
    });

    testWidgets('the default sort can be changed', (tester) async {
      final controller = await pumpSettings(tester);

      await choose(tester, 'Top rated', 'Closest');
      expect(controller.settings.nearbySort, ServiceSort.distance);
    });
  });
}
