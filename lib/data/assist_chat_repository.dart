import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/assist_chat.dart';

/// Saves and loads the user's Assist chats on the device.
class AssistChatRepository {
  AssistChatRepository(this._preferences);

  static const _storageKey = 'assist_chats_v1';

  final SharedPreferences _preferences;

  List<AssistChat> load() {
    final stored = _preferences.getString(_storageKey);
    if (stored == null) return [];
    final decoded = jsonDecode(stored) as List<dynamic>;
    return [
      for (final chat in decoded)
        AssistChat.fromJson(chat as Map<String, dynamic>),
    ];
  }

  Future<void> save(List<AssistChat> chats) async {
    final encoded = jsonEncode([for (final chat in chats) chat.toJson()]);
    await _preferences.setString(_storageKey, encoded);
  }

  Future<void> deleteAll() => _preferences.remove(_storageKey);
}
