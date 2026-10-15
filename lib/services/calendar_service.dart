import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter/material.dart' show Color, immutable;

/// A calendar on the device that the app is allowed to add events to, such as
/// the user's Google or iCloud calendar.
@immutable
class UserCalendar {
  const UserCalendar({
    required this.id,
    required this.name,
    this.accountName,
    this.color,
    this.isPrimary = false,
  });

  final String id;
  final String name;

  /// The account the calendar belongs to, for example an email address.
  final String? accountName;
  final Color? color;

  /// Whether this is the account's main calendar.
  final bool isPrimary;
}

/// What the calendar event for one maintenance task shows. Tasks are added as
/// all-day events on their due date.
@immutable
class CalendarEventDetails {
  const CalendarEventDetails({
    required this.title,
    required this.description,
    required this.date,
  });

  final String title;
  final String description;

  /// The due date, without a time of day.
  final DateTime date;

  Map<String, dynamic> toJson() => {
    'title': title,
    'description': description,
    'date': date.toIso8601String(),
  };

  factory CalendarEventDetails.fromJson(Map<String, dynamic> json) {
    return CalendarEventDetails(
      title: json['title'] as String,
      description: json['description'] as String,
      date: DateTime.parse(json['date'] as String),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CalendarEventDetails &&
      other.title == title &&
      other.description == description &&
      other.date == date;

  @override
  int get hashCode => Object.hash(title, description, date);
}

/// Reads the device's calendars and adds, changes and removes the app's
/// events in them.
///
/// This is an interface so tests can supply a fake implementation.
abstract interface class CalendarService {
  /// Whether the user has allowed the app to read and change their calendars.
  /// Never asks the user.
  Future<bool> hasAccess();

  /// Asks the user for access to their calendars. Returns `true` if access
  /// is allowed.
  Future<bool> requestAccess();

  /// Opens this app's page in the device settings, where the user can allow
  /// calendar access after turning it down.
  Future<void> openAppSettings();

  /// Calendars the app can add events to. Read-only calendars, such as
  /// holidays and birthdays, are left out, as are calendars switched off in
  /// the calendar app.
  Future<List<UserCalendar>> listWritableCalendars();

  /// Adds an event to the calendar and returns the new event's id.
  Future<String> createEvent(String calendarId, CalendarEventDetails details);

  /// Changes an event the app added. Returns `false` if the event no longer
  /// exists, for example because the user deleted it in their calendar app.
  Future<bool> updateEvent(String eventId, CalendarEventDetails details);

  /// Removes an event the app added. Does nothing if it was already removed.
  Future<void> deleteEvent(String eventId);
}

/// [CalendarService] that uses the calendars stored on the phone through the
/// device_calendar_plus plugin. Calendars synced from an online account,
/// such as Google Calendar, pass events on to that account.
class DeviceCalendarService implements CalendarService {
  final _plugin = DeviceCalendar.instance;

  @override
  Future<bool> hasAccess() async =>
      await _plugin.hasPermissions() == CalendarPermissionStatus.granted;

  @override
  Future<bool> requestAccess() async =>
      await _plugin.requestPermissions() == CalendarPermissionStatus.granted;

  @override
  Future<void> openAppSettings() => _plugin.openAppSettings();

  @override
  Future<List<UserCalendar>> listWritableCalendars() async {
    final calendars = await _plugin.listCalendars();
    return [
      for (final calendar in calendars)
        if (!calendar.readOnly && !calendar.hidden)
          UserCalendar(
            id: calendar.id,
            name: calendar.name,
            accountName: calendar.accountName,
            color: calendar.color,
            isPrimary: calendar.isPrimary,
          ),
    ];
  }

  @override
  Future<String> createEvent(String calendarId, CalendarEventDetails details) {
    return _plugin.createEvent(
      calendarId: calendarId,
      title: details.title,
      description: details.description,
      startDate: details.date,
      endDate: _dayAfter(details.date),
      isAllDay: true,
      // Shown as free so maintenance doesn't block time in the calendar.
      availability: EventAvailability.free,
    );
  }

  @override
  Future<bool> updateEvent(String eventId, CalendarEventDetails details) async {
    try {
      await _plugin.updateEvent(
        instanceId: eventId,
        title: details.title,
        description: Patch.set(details.description),
        startDate: details.date,
        endDate: _dayAfter(details.date),
      );
      return true;
    } on DeviceCalendarException catch (error) {
      if (error.errorCode == DeviceCalendarError.notFound) return false;
      rethrow;
    }
  }

  @override
  Future<void> deleteEvent(String eventId) async {
    try {
      await _plugin.deleteEvent(instanceId: eventId);
    } on DeviceCalendarException catch (error) {
      if (error.errorCode != DeviceCalendarError.notFound) rethrow;
    }
  }

  /// All-day events end at the start of the following day.
  static DateTime _dayAfter(DateTime date) =>
      DateTime(date.year, date.month, date.day + 1);
}
