import 'package:flutter/foundation.dart';

import '../data/calendar_event_repository.dart';
import '../models/home_item.dart';
import '../services/calendar_service.dart';
import '../utils/date_utils.dart';
import 'home_item_controller.dart';
import 'settings_controller.dart';

/// The calendar event each task should have, by task id.
Map<String, CalendarEventDetails> plannedCalendarEvents(
  List<HomeItem> homeItems,
) {
  return {
    for (final item in homeItems)
      for (final task in item.tasks)
        task.id: CalendarEventDetails(
          title: '${item.name}: ${task.title}',
          description: [
            if (task.description.trim().isNotEmpty) task.description.trim(),
            'Added by HomeTrackHub. Change this task in the app, since '
                'edits made here are replaced when the task changes.',
          ].join('\n\n'),
          date: dateOnly(task.nextDueDate),
        ),
  };
}

/// Keeps the calendar the user picked in step with their maintenance tasks:
/// each task is an all-day event on its due date.
///
/// Whenever home items or settings change, the events are compared with the
/// tasks. Only events whose task was added, changed or deleted are written.
/// Turning calendar sync off, or picking another calendar, removes the
/// events from the old calendar.
class CalendarSync {
  CalendarSync({
    required this._homeItems,
    required this._settings,
    required this._calendar,
    required this._repository,
  });

  final HomeItemController _homeItems;
  final SettingsController _settings;
  final CalendarService _calendar;
  final CalendarEventRepository _repository;

  bool _isSyncing = false;
  bool _needsAnotherSync = false;

  /// Syncs the calendar now and again after every change.
  void start() {
    _homeItems.addListener(sync);
    _settings.addListener(sync);
    sync();
  }

  void dispose() {
    _homeItems.removeListener(sync);
    _settings.removeListener(sync);
  }

  /// Brings the calendar up to date. If a sync is already running, another
  /// one runs once it finishes so the latest changes are always applied.
  Future<void> sync() async {
    if (_isSyncing) {
      _needsAnotherSync = true;
      return;
    }
    _isSyncing = true;
    try {
      do {
        _needsAnotherSync = false;
        await _syncOnce();
      } while (_needsAnotherSync);
    } catch (error) {
      debugPrint('Could not sync the calendar: $error');
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _syncOnce() async {
    // Without access nothing can be read or changed. This happens before
    // calendar sync is first turned on, or if the user takes access away.
    if (!await _calendar.hasAccess()) return;

    final settings = _settings.settings;
    final calendarId = settings.calendarSyncEnabled
        ? settings.syncCalendarId
        : null;
    final planned = calendarId == null
        ? const <String, CalendarEventDetails>{}
        : plannedCalendarEvents(_homeItems.homeItems);
    final synced = _repository.load();

    try {
      // Remove events for deleted tasks, and events in a calendar that is no
      // longer being synced to.
      for (final MapEntry(key: taskId, value: event) in [...synced.entries]) {
        if (planned.containsKey(taskId) && event.calendarId == calendarId) {
          continue;
        }
        try {
          await _calendar.deleteEvent(event.eventId);
          synced.remove(taskId);
        } catch (error) {
          debugPrint('Could not remove calendar event for $taskId: $error');
        }
      }

      for (final MapEntry(key: taskId, value: details) in planned.entries) {
        final existing = synced[taskId];
        if (existing?.details == details) continue;
        try {
          var eventId = existing?.eventId;
          if (eventId == null ||
              !await _calendar.updateEvent(eventId, details)) {
            eventId = await _calendar.createEvent(calendarId!, details);
          }
          synced[taskId] = SyncedCalendarEvent(
            calendarId: calendarId!,
            eventId: eventId,
            details: details,
          );
        } catch (error) {
          debugPrint('Could not add calendar event for $taskId: $error');
        }
      }
    } finally {
      await _repository.save(synced);
    }
  }
}
