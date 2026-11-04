import 'package:flutter/material.dart' show ThemeMode, immutable;

import 'calendar_period.dart';
import 'task_reminder.dart';

/// How often the overview notification summarizing upcoming maintenance is
/// sent.
enum OverviewFrequency {
  off('Off'),
  weekly('Weekly'),
  monthly('Monthly');

  const OverviewFrequency(this.label);

  final String label;
}

/// Every preference the user can change on the settings screen.
///
/// Reminders for individual tasks are set on each task (see
/// [TaskReminder]). The only app-wide notification is the optional overview.
@immutable
class AppSettings {
  const AppSettings({
    this.overviewFrequency = OverviewFrequency.off,
    this.overviewWeekday = DateTime.monday,
    this.overviewHour = 8,
    this.overviewMinute = 0,
    this.themeMode = ThemeMode.system,
    this.calendarPeriod = CalendarPeriod.month,
    this.networkDiscoveryEnabled = true,
    this.hideDetailsInNotifications = false,
    this.calendarSyncEnabled = false,
    this.syncCalendarId,
    this.syncCalendarName,
  });

  // Notifications
  /// Whether to send a weekly or monthly overview of upcoming maintenance.
  final OverviewFrequency overviewFrequency;

  /// The day weekly overviews are sent, from [DateTime.monday] (1) to
  /// [DateTime.sunday] (7). Monthly overviews are sent on the 1st.
  final int overviewWeekday;

  /// The time of day (24 hour clock) overviews are sent.
  final int overviewHour;
  final int overviewMinute;

  // Appearance
  final ThemeMode themeMode;

  /// What the calendar shows when the app opens, and the time the
  /// Overview's Completed and Spent cards count: this week, month or year.
  final CalendarPeriod calendarPeriod;

  // Privacy
  /// Whether the app may scan the local network for smart devices.
  final bool networkDiscoveryEnabled;

  /// When true, notifications only say that maintenance is due, without
  /// naming the home item or task. Useful because notifications can appear
  /// on a locked screen.
  final bool hideDetailsInNotifications;

  // Calendar
  /// Whether each task is added to [syncCalendarId] as an all-day event on
  /// its due date.
  final bool calendarSyncEnabled;

  /// The device calendar tasks are added to. Kept when calendar sync is
  /// turned off so the same calendar is used if it's turned back on.
  final String? syncCalendarId;

  /// The name of [syncCalendarId], shown on the settings list.
  final String? syncCalendarName;

  AppSettings copyWith({
    OverviewFrequency? overviewFrequency,
    int? overviewWeekday,
    int? overviewHour,
    int? overviewMinute,
    ThemeMode? themeMode,
    CalendarPeriod? calendarPeriod,
    bool? networkDiscoveryEnabled,
    bool? hideDetailsInNotifications,
    bool? calendarSyncEnabled,
    String? syncCalendarId,
    String? syncCalendarName,
  }) {
    return AppSettings(
      overviewFrequency: overviewFrequency ?? this.overviewFrequency,
      overviewWeekday: overviewWeekday ?? this.overviewWeekday,
      overviewHour: overviewHour ?? this.overviewHour,
      overviewMinute: overviewMinute ?? this.overviewMinute,
      themeMode: themeMode ?? this.themeMode,
      calendarPeriod: calendarPeriod ?? this.calendarPeriod,
      networkDiscoveryEnabled:
          networkDiscoveryEnabled ?? this.networkDiscoveryEnabled,
      hideDetailsInNotifications:
          hideDetailsInNotifications ?? this.hideDetailsInNotifications,
      calendarSyncEnabled: calendarSyncEnabled ?? this.calendarSyncEnabled,
      syncCalendarId: syncCalendarId ?? this.syncCalendarId,
      syncCalendarName: syncCalendarName ?? this.syncCalendarName,
    );
  }

  Map<String, dynamic> toJson() => {
    'overviewFrequency': overviewFrequency.name,
    'overviewWeekday': overviewWeekday,
    'overviewHour': overviewHour,
    'overviewMinute': overviewMinute,
    'themeMode': themeMode.name,
    'calendarPeriod': calendarPeriod.name,
    'networkDiscoveryEnabled': networkDiscoveryEnabled,
    'hideDetailsInNotifications': hideDetailsInNotifications,
    'calendarSyncEnabled': calendarSyncEnabled,
    'syncCalendarId': syncCalendarId,
    'syncCalendarName': syncCalendarName,
  };

  /// Reads settings saved by [toJson]. Missing values fall back to the
  /// defaults so older saved data keeps working after settings change.
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    const defaults = AppSettings();
    final themeName = json['themeMode'] as String?;
    final periodName = json['calendarPeriod'] as String?;
    final overviewName = json['overviewFrequency'] as String?;
    return AppSettings(
      overviewFrequency: overviewName == null
          ? defaults.overviewFrequency
          : OverviewFrequency.values.byName(overviewName),
      overviewWeekday:
          json['overviewWeekday'] as int? ?? defaults.overviewWeekday,
      overviewHour: json['overviewHour'] as int? ?? defaults.overviewHour,
      overviewMinute: json['overviewMinute'] as int? ?? defaults.overviewMinute,
      themeMode: themeName == null
          ? defaults.themeMode
          : ThemeMode.values.byName(themeName),
      calendarPeriod: periodName == null
          ? defaults.calendarPeriod
          : CalendarPeriod.values.byName(periodName),
      networkDiscoveryEnabled:
          json['networkDiscoveryEnabled'] as bool? ??
          defaults.networkDiscoveryEnabled,
      hideDetailsInNotifications:
          json['hideDetailsInNotifications'] as bool? ??
          defaults.hideDetailsInNotifications,
      calendarSyncEnabled:
          json['calendarSyncEnabled'] as bool? ?? defaults.calendarSyncEnabled,
      syncCalendarId: json['syncCalendarId'] as String?,
      syncCalendarName: json['syncCalendarName'] as String?,
    );
  }
}
