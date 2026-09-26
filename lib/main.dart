import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/equipment_repository.dart';
import 'data/settings_repository.dart';
import 'services/device_discovery_service.dart';
import 'services/notification_service.dart';
import 'state/equipment_controller.dart';
import 'state/reminder_sync.dart';
import 'state/settings_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final preferences = await SharedPreferences.getInstance();
  final equipmentController = EquipmentController(
    EquipmentRepository(preferences),
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
    equipment: equipmentController,
    settings: settingsController,
    notifications: notificationService,
  ).start();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: equipmentController),
        ChangeNotifierProvider.value(value: settingsController),
        Provider<NotificationService>.value(value: notificationService),
        Provider<DeviceDiscoveryService>.value(
          value: NetworkDeviceDiscoveryService(),
        ),
      ],
      child: const HomeTrackHubApp(),
    ),
  );
}
