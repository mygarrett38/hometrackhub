import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/equipment.dart';

/// Saves and loads the user's equipment on the device.
class EquipmentRepository {
  EquipmentRepository(this._preferences);

  static const _storageKey = 'equipment_v1';

  final SharedPreferences _preferences;

  List<Equipment> load() {
    final stored = _preferences.getString(_storageKey);
    if (stored == null) return [];
    final decoded = jsonDecode(stored) as List<dynamic>;
    return [
      for (final item in decoded)
        Equipment.fromJson(item as Map<String, dynamic>),
    ];
  }

  Future<void> save(List<Equipment> equipment) async {
    final encoded = jsonEncode([for (final item in equipment) item.toJson()]);
    await _preferences.setString(_storageKey, encoded);
  }

  Future<void> deleteAll() => _preferences.remove(_storageKey);
}
