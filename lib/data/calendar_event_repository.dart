import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/calendar_service.dart';

/// A calendar event the app added for a maintenance task, and what it showed
/// when it was last written. Comparing [details] with the task lets the app
/// skip events that haven't changed.
@immutable
class SyncedCalendarEvent {
  const SyncedCalendarEvent({
    required this.calendarId,
    required this.eventId,
    required this.details,
  });

  final String calendarId;
  final String eventId;
  final CalendarEventDetails details;

  Map<String, dynamic> toJson() => {
    'calendarId': calendarId,
    'eventId': eventId,
    'details': details.toJson(),
  };

  factory SyncedCalendarEvent.fromJson(Map<String, dynamic> json) {
    return SyncedCalendarEvent(
      calendarId: json['calendarId'] as String,
      eventId: json['eventId'] as String,
      details: CalendarEventDetails.fromJson(
        json['details'] as Map<String, dynamic>,
      ),
    );
  }
}

/// Saves which calendar event belongs to which maintenance task, so events
/// can be moved or removed when their task changes.
class CalendarEventRepository {
  CalendarEventRepository(this._preferences);

  static const _storageKey = 'calendar_events_v1';

  final SharedPreferences _preferences;

  /// Events the app has added, by task id.
  Map<String, SyncedCalendarEvent> load() {
    final stored = _preferences.getString(_storageKey);
    if (stored == null) return {};
    final decoded = jsonDecode(stored) as Map<String, dynamic>;
    return {
      for (final MapEntry(key: taskId, value: event) in decoded.entries)
        taskId: SyncedCalendarEvent.fromJson(event as Map<String, dynamic>),
    };
  }

  Future<void> save(Map<String, SyncedCalendarEvent> events) async {
    final encoded = jsonEncode({
      for (final MapEntry(key: taskId, value: event) in events.entries)
        taskId: event.toJson(),
    });
    await _preferences.setString(_storageKey, encoded);
  }
}
