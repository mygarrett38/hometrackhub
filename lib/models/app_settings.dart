import 'package:flutter/material.dart' show ThemeMode, immutable;

import 'task_reminder.dart';

/// The user's home address. Every field is optional.
@immutable
class HomeLocation {
  const HomeLocation({
    this.streetAddress = '',
    this.city = '',
    this.region = '',
    this.postalCode = '',
    this.country = '',
  });

  final String streetAddress;
  final String city;

  /// State, province, or county.
  final String region;
  final String postalCode;
  final String country;

  bool get isEmpty => [
    streetAddress,
    city,
    region,
    postalCode,
    country,
  ].every((field) => field.trim().isEmpty);

  /// A single line summary such as "Springfield, IL 62701, USA".
  String get summary {
    final regionAndPostal = [
      region,
      postalCode,
    ].where((part) => part.isNotEmpty).join(' ');
    return [
      streetAddress,
      city,
      regionAndPostal,
      country,
    ].where((part) => part.isNotEmpty).join(', ');
  }

  Map<String, dynamic> toJson() => {
    'streetAddress': streetAddress,
    'city': city,
    'region': region,
    'postalCode': postalCode,
    'country': country,
  };

  factory HomeLocation.fromJson(Map<String, dynamic> json) {
    return HomeLocation(
      streetAddress: json['streetAddress'] as String? ?? '',
      city: json['city'] as String? ?? '',
      region: json['region'] as String? ?? '',
      postalCode: json['postalCode'] as String? ?? '',
      country: json['country'] as String? ?? '',
    );
  }
}

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
    this.networkDiscoveryEnabled = true,
    this.hideDetailsInNotifications = false,
    this.homeLocation = const HomeLocation(),
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

  // Privacy
  /// Whether the app may scan the local network for smart devices.
  final bool networkDiscoveryEnabled;

  /// When true, notifications only say that maintenance is due, without
  /// naming the home item or task. Useful because notifications can appear
  /// on a locked screen.
  final bool hideDetailsInNotifications;

  // Home
  final HomeLocation homeLocation;

  AppSettings copyWith({
    OverviewFrequency? overviewFrequency,
    int? overviewWeekday,
    int? overviewHour,
    int? overviewMinute,
    ThemeMode? themeMode,
    bool? networkDiscoveryEnabled,
    bool? hideDetailsInNotifications,
    HomeLocation? homeLocation,
  }) {
    return AppSettings(
      overviewFrequency: overviewFrequency ?? this.overviewFrequency,
      overviewWeekday: overviewWeekday ?? this.overviewWeekday,
      overviewHour: overviewHour ?? this.overviewHour,
      overviewMinute: overviewMinute ?? this.overviewMinute,
      themeMode: themeMode ?? this.themeMode,
      networkDiscoveryEnabled:
          networkDiscoveryEnabled ?? this.networkDiscoveryEnabled,
      hideDetailsInNotifications:
          hideDetailsInNotifications ?? this.hideDetailsInNotifications,
      homeLocation: homeLocation ?? this.homeLocation,
    );
  }

  Map<String, dynamic> toJson() => {
    'overviewFrequency': overviewFrequency.name,
    'overviewWeekday': overviewWeekday,
    'overviewHour': overviewHour,
    'overviewMinute': overviewMinute,
    'themeMode': themeMode.name,
    'networkDiscoveryEnabled': networkDiscoveryEnabled,
    'hideDetailsInNotifications': hideDetailsInNotifications,
    'homeLocation': homeLocation.toJson(),
  };

  /// Reads settings saved by [toJson]. Missing values fall back to the
  /// defaults so older saved data keeps working after settings change.
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    const defaults = AppSettings();
    final homeLocation = json['homeLocation'] as Map<String, dynamic>?;
    final themeName = json['themeMode'] as String?;
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
      networkDiscoveryEnabled:
          json['networkDiscoveryEnabled'] as bool? ??
          defaults.networkDiscoveryEnabled,
      hideDetailsInNotifications:
          json['hideDetailsInNotifications'] as bool? ??
          defaults.hideDetailsInNotifications,
      homeLocation: homeLocation == null
          ? defaults.homeLocation
          : HomeLocation.fromJson(homeLocation),
    );
  }
}
