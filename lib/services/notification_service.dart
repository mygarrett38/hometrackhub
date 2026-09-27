import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'reminder_planner.dart';

/// Shows and schedules maintenance reminders.
///
/// This is an interface so tests can supply a fake implementation.
abstract interface class NotificationService {
  Future<void> initialize();

  /// Asks the operating system for permission to show notifications.
  /// Returns `true` if notifications are allowed.
  Future<bool> requestPermission();

  /// Replaces every scheduled reminder with [reminders].
  Future<void> replaceScheduledReminders(List<PlannedReminder> reminders);

  /// Shows a notification right away so the user can check that
  /// notifications work on their device.
  Future<void> showTestNotification();
}

/// [NotificationService] that uses the operating system's notification
/// center through the flutter_local_notifications plugin.
class LocalNotificationService implements NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();

  static const _testNotificationId = 999999;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'maintenance_reminders',
      'Maintenance reminders',
      channelDescription: 'Reminders when home maintenance is due.',
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(''),
    ),
    iOS: DarwinNotificationDetails(),
  );

  @override
  Future<void> initialize() async {
    await _configureLocalTimeZone();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // Permissions are requested later by [requestPermission] so the
        // prompt appears after the app has opened, not during startup.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
  }

  /// Scheduled notifications need to know the device's time zone so that a
  /// reminder set for 9:00 AM fires at 9:00 AM local time.
  Future<void> _configureLocalTimeZone() async {
    tz_data.initializeTimeZones();
    try {
      final timeZone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timeZone.identifier));
    } catch (error) {
      // Fall back to UTC. Reminders still fire, but may be off by the
      // difference between UTC and local time.
      debugPrint('Could not determine local time zone: $error');
    }
  }

  @override
  Future<bool> requestPermission() async {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        return await android?.requestNotificationsPermission() ?? false;
      case TargetPlatform.iOS:
        final ios = _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
        return await ios?.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      default:
        // The app only supports Android and iOS.
        return false;
    }
  }

  @override
  Future<void> replaceScheduledReminders(
    List<PlannedReminder> reminders,
  ) async {
    // Leaves reminders the user has already received in the notification
    // center and only removes ones that have not been shown yet.
    await _plugin.cancelAllPendingNotifications();
    for (final reminder in reminders) {
      await _plugin.zonedSchedule(
        id: reminder.id,
        title: reminder.title,
        body: reminder.body,
        scheduledDate: tz.TZDateTime.from(reminder.time, tz.local),
        notificationDetails: _details,
        // Inexact scheduling avoids needing the "Alarms & reminders"
        // permission. The reminder may arrive a few minutes late, which is
        // fine for home maintenance.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  @override
  Future<void> showTestNotification() {
    return _plugin.show(
      id: _testNotificationId,
      title: 'Notifications are working',
      body: 'You will be reminded here when home maintenance is due.',
      notificationDetails: _details,
    );
  }
}
