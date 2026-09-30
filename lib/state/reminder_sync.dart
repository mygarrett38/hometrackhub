import 'package:flutter/foundation.dart';

import '../services/notification_service.dart';
import '../services/reminder_planner.dart';
import 'home_item_controller.dart';
import 'settings_controller.dart';

/// Keeps the operating system's scheduled notifications in step with the
/// user's home items and settings.
///
/// Whenever home items or settings change, every reminder is planned again
/// from scratch. This is simpler and less error prone than updating
/// individual reminders, and the number of reminders is small.
class ReminderSync {
  ReminderSync({
    required this._homeItems,
    required this._settings,
    required this._notifications,
  });

  final HomeItemController _homeItems;
  final SettingsController _settings;
  final NotificationService _notifications;

  bool _isSyncing = false;
  bool _needsAnotherSync = false;

  /// Schedules reminders now and again after every change.
  void start() {
    _homeItems.addListener(sync);
    _settings.addListener(sync);
    sync();
  }

  void dispose() {
    _homeItems.removeListener(sync);
    _settings.removeListener(sync);
  }

  /// Reschedules all reminders. If a sync is already running, another one
  /// runs once it finishes so the latest changes are always applied.
  Future<void> sync() async {
    if (_isSyncing) {
      _needsAnotherSync = true;
      return;
    }
    _isSyncing = true;
    try {
      do {
        _needsAnotherSync = false;
        final reminders = planReminders(
          homeItems: _homeItems.homeItems,
          settings: _settings.settings,
          now: DateTime.now(),
        );
        await _notifications.replaceScheduledReminders(reminders);
      } while (_needsAnotherSync);
    } catch (error) {
      debugPrint('Could not schedule reminders: $error');
    } finally {
      _isSyncing = false;
    }
  }
}
