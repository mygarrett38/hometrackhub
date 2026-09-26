import 'package:flutter/material.dart' show ThemeMode, immutable;

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

/// Every preference the user can change on the settings screen.
@immutable
class AppSettings {
  const AppSettings({
    this.notificationsEnabled = true,
    this.reminderHour = 9,
    this.reminderMinute = 0,
    this.reminderDaysBefore = 0,
    this.themeMode = ThemeMode.system,
    this.networkDiscoveryEnabled = true,
    this.hideDetailsInNotifications = false,
    this.homeLocation = const HomeLocation(),
  });

  // Notifications
  final bool notificationsEnabled;

  /// The time of day (24 hour clock) reminders are delivered.
  final int reminderHour;
  final int reminderMinute;

  /// How many days before a task is due the reminder is sent.
  /// 0 means on the due date itself.
  final int reminderDaysBefore;

  // Appearance
  final ThemeMode themeMode;

  // Privacy
  /// Whether the app may scan the local network for smart devices.
  final bool networkDiscoveryEnabled;

  /// When true, reminders only say that maintenance is due, without naming
  /// the equipment or task. Useful because notifications can appear on a
  /// locked screen.
  final bool hideDetailsInNotifications;

  // Home
  final HomeLocation homeLocation;

  AppSettings copyWith({
    bool? notificationsEnabled,
    int? reminderHour,
    int? reminderMinute,
    int? reminderDaysBefore,
    ThemeMode? themeMode,
    bool? networkDiscoveryEnabled,
    bool? hideDetailsInNotifications,
    HomeLocation? homeLocation,
  }) {
    return AppSettings(
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      reminderHour: reminderHour ?? this.reminderHour,
      reminderMinute: reminderMinute ?? this.reminderMinute,
      reminderDaysBefore: reminderDaysBefore ?? this.reminderDaysBefore,
      themeMode: themeMode ?? this.themeMode,
      networkDiscoveryEnabled:
          networkDiscoveryEnabled ?? this.networkDiscoveryEnabled,
      hideDetailsInNotifications:
          hideDetailsInNotifications ?? this.hideDetailsInNotifications,
      homeLocation: homeLocation ?? this.homeLocation,
    );
  }

  Map<String, dynamic> toJson() => {
    'notificationsEnabled': notificationsEnabled,
    'reminderHour': reminderHour,
    'reminderMinute': reminderMinute,
    'reminderDaysBefore': reminderDaysBefore,
    'themeMode': themeMode.name,
    'networkDiscoveryEnabled': networkDiscoveryEnabled,
    'hideDetailsInNotifications': hideDetailsInNotifications,
    'homeLocation': homeLocation.toJson(),
  };

  /// Reads settings saved by [toJson]. Missing values fall back to the
  /// defaults so older saved data keeps working after new settings are added.
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    const defaults = AppSettings();
    final homeLocation = json['homeLocation'] as Map<String, dynamic>?;
    final themeName = json['themeMode'] as String?;
    return AppSettings(
      notificationsEnabled:
          json['notificationsEnabled'] as bool? ??
          defaults.notificationsEnabled,
      reminderHour: json['reminderHour'] as int? ?? defaults.reminderHour,
      reminderMinute: json['reminderMinute'] as int? ?? defaults.reminderMinute,
      reminderDaysBefore:
          json['reminderDaysBefore'] as int? ?? defaults.reminderDaysBefore,
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
