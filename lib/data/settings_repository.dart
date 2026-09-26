import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';

/// Saves and loads the user's [AppSettings] on the device.
class SettingsRepository {
  SettingsRepository(this._preferences);

  static const _storageKey = 'settings_v1';

  final SharedPreferences _preferences;

  AppSettings load() {
    final stored = _preferences.getString(_storageKey);
    if (stored == null) return const AppSettings();
    return AppSettings.fromJson(jsonDecode(stored) as Map<String, dynamic>);
  }

  Future<void> save(AppSettings settings) async {
    await _preferences.setString(_storageKey, jsonEncode(settings.toJson()));
  }

  Future<void> deleteAll() => _preferences.remove(_storageKey);
}
