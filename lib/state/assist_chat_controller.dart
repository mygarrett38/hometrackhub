import 'package:flutter/foundation.dart';

import '../data/assist_chat_repository.dart';
import '../models/assist_chat.dart';
import '../utils/date_utils.dart';
import '../utils/id_generator.dart';

/// Holds the user's Assist chats, saves every change, and deletes chats that
/// have had no new messages for [AssistChat.expiresAfter].
class AssistChatController extends ChangeNotifier {
  AssistChatController(this._repository, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now,
      _chats = _repository.load() {
    // Chats that expired while the app was closed are deleted on startup.
    if (_chats.any((chat) => chat.isExpiredAt(_clock()))) {
      _saveAndNotify();
    }
  }

  final AssistChatRepository _repository;
  final DateTime Function() _clock;
  List<AssistChat> _chats;

  /// Chats that haven't expired, most recently active first.
  List<AssistChat> get chats {
    final now = _clock();
    final active = [
      for (final chat in _chats)
        if (!chat.isExpiredAt(now)) chat,
    ]..sort((a, b) => b.lastActiveAt.compareTo(a.lastActiveAt));
    return List.unmodifiable(active);
  }

  /// The name to show for [chat]: the one the user gave it, or else the day
  /// it was started and its [AssistChat.dayNumber], such as "October 28th
  /// Chat 3". The first chat of a day has no number while it's the only one
  /// from that day: "October 28th Chat".
  String titleOf(AssistChat chat) {
    if (chat.name case final name? when name.trim().isNotEmpty) {
      return name.trim();
    }
    final day = dateOnly(chat.createdAt);
    final title = '${monthDayOrdinal(day)} Chat';
    final alone = !chats.any(
      (other) => other.id != chat.id && dateOnly(other.createdAt) == day,
    );
    if (chat.dayNumber == 1 && alone) return title;
    return '$title ${chat.dayNumber}';
  }

  /// The chat with [id], or `null` if it was deleted or has expired.
  AssistChat? chatById(String id) {
    for (final chat in chats) {
      if (chat.id == id) return chat;
    }
    return null;
  }

  /// Starts a chat with the user's first [question] and returns its id.
  ///
  /// It's numbered one after the highest-numbered chat started the same
  /// day. So deleting the most recent chat of a day frees its number for
  /// the next one, while deleting an earlier one leaves a gap.
  Future<String> startChat(String question) async {
    final now = _clock();
    final today = dateOnly(now);
    var highest = 0;
    for (final chat in chats) {
      if (dateOnly(chat.createdAt) == today && chat.dayNumber > highest) {
        highest = chat.dayNumber;
      }
    }
    final chat = AssistChat(
      id: generateId(),
      messages: [AssistChatMessage.user(question)],
      createdAt: now,
      lastActiveAt: now,
      dayNumber: highest + 1,
    );
    _chats = [..._chats, chat];
    await _saveAndNotify();
    return chat.id;
  }

  /// Adds [message] to the end of a chat, which keeps it from expiring for
  /// another [AssistChat.expiresAfter]. Does nothing if the chat is gone,
  /// for example because it was deleted while waiting for an answer.
  Future<void> addMessage(String chatId, AssistChatMessage message) async {
    final chat = chatById(chatId);
    if (chat == null) return;
    _replace(
      chat.copyWith(
        messages: [...chat.messages, message],
        lastActiveAt: _clock(),
      ),
    );
    await _saveAndNotify();
  }

  /// Gives a chat the user's own [name]. An empty name, or the default name
  /// unchanged, goes back to naming it after its day. Renaming doesn't count
  /// as activity, so it doesn't keep the chat from expiring.
  Future<void> rename(String chatId, String name) async {
    final chat = chatById(chatId);
    if (chat == null) return;
    final trimmed = name.trim();
    final unnamed = chat.copyWith(clearName: true);
    _replace(
      trimmed.isEmpty || trimmed == titleOf(unnamed)
          ? unnamed
          : chat.copyWith(name: trimmed),
    );
    await _saveAndNotify();
  }

  Future<void> delete(String chatId) async {
    _chats = [
      for (final chat in _chats)
        if (chat.id != chatId) chat,
    ];
    await _saveAndNotify();
  }

  /// Deletes every chat, for example when the user deletes all their data.
  Future<void> deleteAll() async {
    _chats = [];
    await _repository.deleteAll();
    notifyListeners();
  }

  void _replace(AssistChat updated) {
    _chats = [
      for (final chat in _chats)
        if (chat.id == updated.id) updated else chat,
    ];
  }

  /// Saves the chats, leaving out any that have expired.
  Future<void> _saveAndNotify() async {
    final now = _clock();
    _chats = [
      for (final chat in _chats)
        if (!chat.isExpiredAt(now)) chat,
    ];
    notifyListeners();
    await _repository.save(_chats);
  }
}
