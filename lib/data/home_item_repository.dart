import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/home_item.dart';

/// Saves and loads the user's home items on the device.
class HomeItemRepository {
  HomeItemRepository(this._preferences);

  static const _storageKey = 'home_items_v1';

  /// Key used before "equipment" was renamed to "home items". Data saved
  /// under it is still loaded so existing users keep their home items.
  static const _legacyStorageKey = 'equipment_v1';

  final SharedPreferences _preferences;

  List<HomeItem> load() {
    final stored =
        _preferences.getString(_storageKey) ??
        _preferences.getString(_legacyStorageKey);
    if (stored == null) return [];
    final decoded = jsonDecode(stored) as List<dynamic>;
    return [
      for (final item in decoded)
        HomeItem.fromJson(item as Map<String, dynamic>),
    ];
  }

  Future<void> save(List<HomeItem> homeItems) async {
    final encoded = jsonEncode([for (final item in homeItems) item.toJson()]);
    await _preferences.setString(_storageKey, encoded);
    await _preferences.remove(_legacyStorageKey);
  }

  Future<void> deleteAll() async {
    await _preferences.remove(_storageKey);
    await _preferences.remove(_legacyStorageKey);
  }
}
