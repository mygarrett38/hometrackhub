import 'package:flutter/material.dart' show ThemeMode, immutable;

import 'calendar_period.dart';
import 'service_sort.dart';
import 'task_reminder.dart';
import 'technical_level.dart';

/// Where the Nearby services screen searches around.
enum NearbyLocationSource {
  device('My location'),
  zipCode('ZIP code');

  const NearbyLocationSource(this.label);

  final String label;
}

/// Every preference the user can change on the settings screen.
///
/// There are two kinds of notification, each timed here: one listing the
/// upcoming tasks, which is always sent, and one listing the overdue tasks,
/// which can be turned off. Each task also picks how far ahead it's first
/// notified about, or not at all (see [TaskReminder]).
@immutable
class AppSettings {
  const AppSettings({
    this.upcomingHour = 9,
    this.upcomingMinute = 0,
    this.upcomingReminderDays = 1,
    this.overdueEnabled = true,
    this.overdueHour = 9,
    this.overdueMinute = 0,
    this.overdueReminderDays = 1,
    this.themeMode = ThemeMode.system,
    this.calendarPeriod = CalendarPeriod.month,
    this.expensesEnabled = false,
    this.networkDiscoveryEnabled = true,
    this.hideDetailsInNotifications = false,
    this.hideSerialNumbers = true,
    this.calendarSyncEnabled = false,
    this.syncCalendarId,
    this.syncCalendarName,
    this.assistantEnabled = true,
    this.askedAboutAssistant = false,
    this.technicalLevel = TechnicalLevel.someExperience,
    this.keepChatsDays = 14,
    this.nearbyLocationSource = NearbyLocationSource.device,
    this.nearbyZipCode,
    this.nearbySort = ServiceSort.rating,
    this.pinnedBusinessIds = const [],
  });

  /// The choices for [upcomingReminderDays] and [overdueReminderDays], from
  /// every day to every two weeks.
  static const reminderDayChoices = [1, 2, 3, 7, 14];

  /// The choices for [keepChatsDays].
  static const keepChatsDayChoices = [7, 14, 30];

  // Notifications. Times of day use a 24 hour clock.
  // Tasks are always notified about before they're due, as long as the
  // device allows it: starting on the day each task's reminder picks (see
  // [TaskReminder.daysBefore]), every [upcomingReminderDays] days, and on
  // the due date.

  /// The time of day upcoming task notifications are sent.
  final int upcomingHour;
  final int upcomingMinute;

  /// How many days apart upcoming task notifications are. One of
  /// [reminderDayChoices].
  final int upcomingReminderDays;

  /// Whether tasks are notified about once they're overdue: starting the day
  /// after they were due, then every [overdueReminderDays] days until
  /// they're done.
  final bool overdueEnabled;

  /// The time of day overdue task notifications are sent.
  final int overdueHour;
  final int overdueMinute;

  /// How many days apart overdue task notifications are. One of
  /// [reminderDayChoices].
  final int overdueReminderDays;

  // Appearance
  final ThemeMode themeMode;

  /// What the calendar shows when the app opens, and how far ahead and back
  /// the Overview's Upcoming and Recently Completed cards look: a week,
  /// month or year.
  /// The Spent card counts this month or year.
  final CalendarPeriod calendarPeriod;

  /// Whether the user tracks what they spend on their home items: on the
  /// Overview's Spent card, and as the calendar's expenses. Off by default.
  /// Expenses already recorded are kept while it's off.
  final bool expensesEnabled;

  // Privacy
  /// Whether the app may scan the local network for smart devices.
  final bool networkDiscoveryEnabled;

  /// When true, notifications only say that maintenance is due, without
  /// naming the home item or task. Useful because notifications can appear
  /// on a locked screen.
  final bool hideDetailsInNotifications;

  /// When true, the VIN or serial number is always hidden on the home item
  /// form, with no eye button to show it, and can only be typed in when
  /// adding a home item. When false, it's shown, with an eye button to hide
  /// it.
  final bool hideSerialNumbers;

  // Calendar
  /// Whether each task is added to [syncCalendarId] as an all-day event on
  /// its due date.
  final bool calendarSyncEnabled;

  /// The device calendar tasks are added to. Kept when calendar sync is
  /// turned off so the same calendar is used if it's turned back on.
  final String? syncCalendarId;

  /// The name of [syncCalendarId], shown on the settings list.
  final String? syncCalendarName;

  // Assistant
  /// Whether the Assist tab offers the AI assistant. When it's off, the tab
  /// only searches for nearby services.
  final bool assistantEnabled;

  /// Whether the user has been asked, when they first opened the app, if
  /// they want to use the AI assistant.
  final bool askedAboutAssistant;

  /// How much the assistant explains in its answers.
  final TechnicalLevel technicalLevel;

  /// How many days a chat is kept after its last message, unless it's
  /// pinned. One of [keepChatsDayChoices].
  final int keepChatsDays;

  // Nearby services
  /// Whether nearby services are searched for around the device's location
  /// or around [nearbyZipCode].
  final NearbyLocationSource nearbyLocationSource;

  /// The five-digit US ZIP code to search around. Kept when the user
  /// switches to their location, so it's still there if they switch back.
  final String? nearbyZipCode;

  /// The order businesses are listed in when the Nearby services screen
  /// opens. The user can still change it on the screen.
  final ServiceSort nearbySort;

  /// The businesses the user pinned to the top of the Nearby services
  /// results, by id: Google's place IDs, which are all Google lets the app
  /// keep, or the sample businesses' ids. In the order they were pinned.
  final List<String> pinnedBusinessIds;

  /// These settings with the business with [id] pinned or not.
  AppSettings withBusinessPinned(String id, bool pinned) => copyWith(
    pinnedBusinessIds: [
      for (final pinnedId in pinnedBusinessIds)
        if (pinnedId != id) pinnedId,
      if (pinned) id,
    ],
  );

  /// Whether [zipCode] is a five-digit US ZIP code.
  static bool isValidZipCode(String zipCode) =>
      RegExp(r'^\d{5}$').hasMatch(zipCode);

  AppSettings copyWith({
    int? upcomingHour,
    int? upcomingMinute,
    int? upcomingReminderDays,
    bool? overdueEnabled,
    int? overdueHour,
    int? overdueMinute,
    int? overdueReminderDays,
    ThemeMode? themeMode,
    CalendarPeriod? calendarPeriod,
    bool? expensesEnabled,
    bool? networkDiscoveryEnabled,
    bool? hideDetailsInNotifications,
    bool? hideSerialNumbers,
    bool? calendarSyncEnabled,
    String? syncCalendarId,
    String? syncCalendarName,
    bool? assistantEnabled,
    bool? askedAboutAssistant,
    TechnicalLevel? technicalLevel,
    int? keepChatsDays,
    NearbyLocationSource? nearbyLocationSource,
    String? nearbyZipCode,
    bool clearNearbyZipCode = false,
    ServiceSort? nearbySort,
    List<String>? pinnedBusinessIds,
  }) {
    return AppSettings(
      upcomingHour: upcomingHour ?? this.upcomingHour,
      upcomingMinute: upcomingMinute ?? this.upcomingMinute,
      upcomingReminderDays: upcomingReminderDays ?? this.upcomingReminderDays,
      overdueEnabled: overdueEnabled ?? this.overdueEnabled,
      overdueHour: overdueHour ?? this.overdueHour,
      overdueMinute: overdueMinute ?? this.overdueMinute,
      overdueReminderDays: overdueReminderDays ?? this.overdueReminderDays,
      themeMode: themeMode ?? this.themeMode,
      calendarPeriod: calendarPeriod ?? this.calendarPeriod,
      expensesEnabled: expensesEnabled ?? this.expensesEnabled,
      networkDiscoveryEnabled:
          networkDiscoveryEnabled ?? this.networkDiscoveryEnabled,
      hideDetailsInNotifications:
          hideDetailsInNotifications ?? this.hideDetailsInNotifications,
      hideSerialNumbers: hideSerialNumbers ?? this.hideSerialNumbers,
      calendarSyncEnabled: calendarSyncEnabled ?? this.calendarSyncEnabled,
      syncCalendarId: syncCalendarId ?? this.syncCalendarId,
      syncCalendarName: syncCalendarName ?? this.syncCalendarName,
      assistantEnabled: assistantEnabled ?? this.assistantEnabled,
      askedAboutAssistant: askedAboutAssistant ?? this.askedAboutAssistant,
      technicalLevel: technicalLevel ?? this.technicalLevel,
      keepChatsDays: keepChatsDays ?? this.keepChatsDays,
      nearbyLocationSource: nearbyLocationSource ?? this.nearbyLocationSource,
      nearbyZipCode: clearNearbyZipCode
          ? null
          : nearbyZipCode ?? this.nearbyZipCode,
      nearbySort: nearbySort ?? this.nearbySort,
      pinnedBusinessIds: pinnedBusinessIds ?? this.pinnedBusinessIds,
    );
  }

  Map<String, dynamic> toJson() => {
    'upcomingHour': upcomingHour,
    'upcomingMinute': upcomingMinute,
    'upcomingReminderDays': upcomingReminderDays,
    'overdueEnabled': overdueEnabled,
    'overdueHour': overdueHour,
    'overdueMinute': overdueMinute,
    'overdueReminderDays': overdueReminderDays,
    'themeMode': themeMode.name,
    'calendarPeriod': calendarPeriod.name,
    'expensesEnabled': expensesEnabled,
    'networkDiscoveryEnabled': networkDiscoveryEnabled,
    'hideDetailsInNotifications': hideDetailsInNotifications,
    'hideSerialNumbers': hideSerialNumbers,
    'calendarSyncEnabled': calendarSyncEnabled,
    'syncCalendarId': syncCalendarId,
    'syncCalendarName': syncCalendarName,
    'assistantEnabled': assistantEnabled,
    'askedAboutAssistant': askedAboutAssistant,
    'technicalLevel': technicalLevel.name,
    'keepChatsDays': keepChatsDays,
    'nearbyLocationSource': nearbyLocationSource.name,
    'nearbyZipCode': nearbyZipCode,
    'nearbySort': nearbySort.name,
    'pinnedBusinessIds': pinnedBusinessIds,
  };

  /// Reads settings saved by [toJson]. Missing values fall back to the
  /// defaults so older saved data keeps working after settings change.
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    const defaults = AppSettings();
    final themeName = json['themeMode'] as String?;
    final periodName = json['calendarPeriod'] as String?;
    final levelName = json['technicalLevel'] as String?;
    final keepChatsDays = json['keepChatsDays'] as int?;
    final upcomingReminderDays = json['upcomingReminderDays'] as int?;
    final overdueReminderDays = json['overdueReminderDays'] as int?;
    final locationSourceName = json['nearbyLocationSource'] as String?;
    final zipCode = json['nearbyZipCode'] as String?;
    final sortName = json['nearbySort'] as String?;
    return AppSettings(
      upcomingHour: json['upcomingHour'] as int? ?? defaults.upcomingHour,
      upcomingMinute: json['upcomingMinute'] as int? ?? defaults.upcomingMinute,
      upcomingReminderDays: reminderDayChoices.contains(upcomingReminderDays)
          ? upcomingReminderDays!
          : defaults.upcomingReminderDays,
      overdueEnabled:
          json['overdueEnabled'] as bool? ?? defaults.overdueEnabled,
      overdueHour: json['overdueHour'] as int? ?? defaults.overdueHour,
      overdueMinute: json['overdueMinute'] as int? ?? defaults.overdueMinute,
      overdueReminderDays: reminderDayChoices.contains(overdueReminderDays)
          ? overdueReminderDays!
          : defaults.overdueReminderDays,
      themeMode: themeName == null
          ? defaults.themeMode
          : ThemeMode.values.byName(themeName),
      calendarPeriod: periodName == null
          ? defaults.calendarPeriod
          : CalendarPeriod.values.byName(periodName),
      expensesEnabled:
          json['expensesEnabled'] as bool? ?? defaults.expensesEnabled,
      networkDiscoveryEnabled:
          json['networkDiscoveryEnabled'] as bool? ??
          defaults.networkDiscoveryEnabled,
      hideDetailsInNotifications:
          json['hideDetailsInNotifications'] as bool? ??
          defaults.hideDetailsInNotifications,
      hideSerialNumbers:
          json['hideSerialNumbers'] as bool? ?? defaults.hideSerialNumbers,
      calendarSyncEnabled:
          json['calendarSyncEnabled'] as bool? ?? defaults.calendarSyncEnabled,
      syncCalendarId: json['syncCalendarId'] as String?,
      syncCalendarName: json['syncCalendarName'] as String?,
      assistantEnabled:
          json['assistantEnabled'] as bool? ?? defaults.assistantEnabled,
      askedAboutAssistant:
          json['askedAboutAssistant'] as bool? ?? defaults.askedAboutAssistant,
      technicalLevel: levelName == null
          ? defaults.technicalLevel
          : TechnicalLevel.values.byName(levelName),
      keepChatsDays: keepChatsDayChoices.contains(keepChatsDays)
          ? keepChatsDays!
          : defaults.keepChatsDays,
      nearbyLocationSource: locationSourceName == null
          ? defaults.nearbyLocationSource
          : NearbyLocationSource.values.byName(locationSourceName),
      nearbyZipCode: zipCode != null && isValidZipCode(zipCode)
          ? zipCode
          : null,
      nearbySort: sortName == null
          ? defaults.nearbySort
          : ServiceSort.values.byName(sortName),
      pinnedBusinessIds: [
        for (final id in json['pinnedBusinessIds'] as List<dynamic>? ?? [])
          if (id is String) id,
      ],
    );
  }
}
