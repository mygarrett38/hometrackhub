import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/calendar_event_repository.dart';
import 'data/home_item_repository.dart';
import 'data/settings_repository.dart';
import 'services/calendar_service.dart';
import 'services/device_discovery_service.dart';
import 'services/notification_service.dart';
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

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: homeItemController),
        ChangeNotifierProvider.value(value: settingsController),
        Provider<NotificationService>.value(value: notificationService),
        Provider<CalendarService>.value(value: calendarService),
        Provider<DeviceDiscoveryService>.value(
          value: NearbyDeviceDiscoveryService(),
        ),
      ],
      child: const HomeTrackHubApp(),
    ),
  );
}
