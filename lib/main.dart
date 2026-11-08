import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/assist_chat_repository.dart';
import 'data/calendar_event_repository.dart';
import 'data/home_item_repository.dart';
import 'data/settings_repository.dart';
import 'services/calendar_service.dart';
import 'services/data_export_service.dart';
import 'services/device_discovery_service.dart';
import 'services/google_places_client.dart';
import 'services/home_assistant_client.dart';
import 'services/location_service.dart';
import 'services/nearby_services_client.dart';
import 'services/notification_service.dart';
import 'state/assist_chat_controller.dart';
import 'state/calendar_sync.dart';
import 'state/home_item_controller.dart';
import 'state/reminder_sync.dart';
import 'state/settings_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final preferences = await SharedPreferences.getInstance();
  final homeItemController = HomeItemController(
    HomeItemRepository(preferences),
  );
  final settingsController = SettingsController(
    SettingsRepository(preferences),
  );
  final assistChatController = AssistChatController(
    AssistChatRepository(preferences),
    settingsController,
  );

  final notificationService = LocalNotificationService();
  try {
    await notificationService.initialize();
  } catch (error) {
    // The app is still usable without notifications.
    debugPrint('Notifications could not be initialized: $error');
  }

  ReminderSync(
    homeItems: homeItemController,
    settings: settingsController,
    notifications: notificationService,
  ).start();

  final calendarService = DeviceCalendarService();
  CalendarSync(
    homeItems: homeItemController,
    settings: settingsController,
    calendar: calendarService,
    repository: CalendarEventRepository(preferences),
  ).start();

  final googlePlaces = GooglePlacesClient();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: homeItemController),
        ChangeNotifierProvider.value(value: settingsController),
        ChangeNotifierProvider.value(value: assistChatController),
        Provider<NotificationService>.value(value: notificationService),
        Provider<CalendarService>.value(value: calendarService),
        Provider<DeviceDiscoveryService>.value(
          value: NearbyDeviceDiscoveryService(),
        ),
        Provider<HomeAssistantClient>.value(value: HomeAssistantClient()),
        // Real businesses from Google once its address is configured, and
        // made-up ones until then.
        Provider<NearbyServicesClient>.value(
          value: googlePlaces.isConfigured
              ? googlePlaces
              : SampleNearbyServicesClient(),
        ),
        Provider<LocationService>.value(value: DeviceLocationService()),
        Provider<DataExportService>.value(value: DeviceDataExportService()),
      ],
      child: const HomeTrackHubApp(),
    ),
  );
}
