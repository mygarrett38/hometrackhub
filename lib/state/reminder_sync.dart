import 'package:flutter/foundation.dart';

import '../services/notification_service.dart';
import '../services/reminder_planner.dart';
import 'equipment_controller.dart';
import 'settings_controller.dart';

/// Keeps the operating system's scheduled notifications in step with the
/// user's equipment and settings.
///
/// Whenever equipment or settings change, every reminder is planned again
/// from scratch. This is simpler and less error prone than updating
/// individual reminders, and the number of reminders is small.
class ReminderSync {
  ReminderSync({
    required this._equipment,
    required this._settings,
    required this._notifications,
  });

  final EquipmentController _equipment;
  final SettingsController _settings;
  final NotificationService _notifications;

  bool _isSyncing = false;
  bool _needsAnotherSync = false;

  /// Schedules reminders now and again after every change.
  void start() {
    _equipment.addListener(sync);
    _settings.addListener(sync);
    sync();
  }

  void dispose() {
    _equipment.removeListener(sync);
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
          equipment: _equipment.equipment,
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
