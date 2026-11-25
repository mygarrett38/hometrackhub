import 'package:flutter/foundation.dart';

import '../data/assist_chat_repository.dart';
import '../models/app_settings.dart';
import '../models/assist_chat.dart';
import '../services/home_assistant_client.dart';
import '../utils/date_utils.dart';
import '../utils/id_generator.dart';
import 'settings_controller.dart';

/// Holds the user's Assist chats, saves every change, and deletes chats that
/// have had no new messages for [keepFor], unless they're
/// pinned.
class AssistChatController extends ChangeNotifier {
  AssistChatController(
    this._repository,
    this._settings, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       _chats = _repository.load(),
       _keepFor = _keepForIn(_settings.settings) {
    _settings.addListener(_onSettingsChanged);
    // Chats that expired while the app was closed are deleted on startup.
    if (_chats.any((chat) => chat.isExpiredAt(_clock(), _keepFor))) {
      _saveAndNotify();
    }
  }

  final AssistChatRepository _repository;
  final SettingsController _settings;
  final DateTime Function() _clock;
  List<AssistChat> _chats;
  Duration _keepFor;
  bool _disposed = false;

  /// The ids of the chats whose last question the assistant is answering.
  final _answering = <String>{};

  /// Why the assistant couldn't answer each chat's last question, by chat
  /// id, until it's asked again.
  final _answerErrors = <String, String>{};

  static Duration _keepForIn(AppSettings settings) =>
      Duration(days: settings.keepChatsDays);

  /// How long chats are kept after their last message, as chosen in
  /// Assistant settings. Pinned chats are kept however long it's been.
  Duration get keepFor => _keepFor;

  /// When [chat] will be deleted if it gets no new messages.
  DateTime expiresAt(AssistChat chat) => chat.expiresAt(_keepFor);

  /// How many chats would be deleted straight away if chats were only kept
  /// for [keepFor].
  int countExpiredIfKeptFor(Duration keepFor) {
    final now = _clock();
    return chats.where((chat) => chat.isExpiredAt(now, keepFor)).length;
  }

  /// Deletes chats right away when the user shortens how long they're kept,
  /// and updates when the rest will be deleted.
  void _onSettingsChanged() {
    final keepFor = _keepForIn(_settings.settings);
    if (keepFor == _keepFor) return;
    _keepFor = keepFor;
    _saveAndNotify();
  }

  @override
  void dispose() {
    _disposed = true;
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  /// Chats that haven't expired: pinned chats first, then the rest, each
  /// most recently active first.
  List<AssistChat> get chats {
    final now = _clock();
    final active =
        [
          for (final chat in _chats)
            if (!chat.isExpiredAt(now, _keepFor)) chat,
        ]..sort((a, b) {
          if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
          return b.lastActiveAt.compareTo(a.lastActiveAt);
        });
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
  /// another [keepFor]. Does nothing if the chat is gone,
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

  /// Whether the assistant is working on an answer to the last question in
  /// the chat with [chatId]. Kept here rather than by the chat's screen, so
  /// the chat still shows it's waiting if the user leaves and comes back.
  bool isAnswering(String chatId) => _answering.contains(chatId);

  /// Why the assistant couldn't answer the last question in the chat with
  /// [chatId], if it couldn't.
  String? answerErrorOf(String chatId) => _answerErrors[chatId];

  /// Asks [assistant] to answer the last question in a chat, at the user's
  /// technical level, and adds its answer to the chat. If it can't, says
  /// why in [answerErrorOf].
  ///
  /// Does nothing while the chat is already being answered, so a question
  /// is never answered twice, or if it has no question waiting.
  Future<void> answer(String chatId, HomeAssistantClient assistant) async {
    final chat = chatById(chatId);
    if (chat == null || !chat.isAwaitingAnswer || isAnswering(chatId)) return;
    _answering.add(chatId);
    _answerErrors.remove(chatId);
    notifyListeners();
    try {
      final reply = await assistant.ask(
        chat.recentMessages(),
        technicalLevel: _settings.settings.technicalLevel,
      );
      if (_disposed) return;
      final reason = reply.professionalReason?.trim() ?? '';
      // Saved even if the user has left the chat, so it's there when they
      // come back to it.
      await addMessage(
        chatId,
        AssistChatMessage.assistant(
          reply.answer,
          professionalNote: reply.recommendProfessional
              ? (reason.isEmpty ? 'This is a job for a professional.' : reason)
              : null,
          professionalService: reply.recommendProfessional
              ? reply.professionalService
              : null,
        ),
      );
    } on AssistantConnectionException catch (error) {
      _answerErrors[chatId] = error.message;
    } finally {
      _answering.remove(chatId);
      if (!_disposed) notifyListeners();
    }
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

  /// Pins or unpins the chats with [chatIds]. Pinned chats are listed first
  /// and never expire. Unpinning gives a chat another
  /// [keepFor] before it's deleted.
  Future<void> setPinned(Iterable<String> chatIds, bool pinned) async {
    final ids = chatIds.toSet();
    final now = _clock();
    _chats = [
      for (final chat in _chats)
        if (!ids.contains(chat.id) || chat.pinned == pinned)
          chat
        else if (pinned)
          chat.copyWith(pinned: true)
        else
          chat.copyWith(pinned: false, unpinnedAt: now),
    ];
    await _saveAndNotify();
  }

  Future<void> delete(String chatId) => deleteChats([chatId]);

  Future<void> deleteChats(Iterable<String> chatIds) async {
    final ids = chatIds.toSet();
    _answerErrors.removeWhere((id, _) => ids.contains(id));
    _chats = [
      for (final chat in _chats)
        if (!ids.contains(chat.id)) chat,
    ];
    await _saveAndNotify();
  }

  /// Replaces every chat with [chats], for example when the user loads their
  /// data from a file. Chats that have already expired are left out.
  Future<void> replaceAll(List<AssistChat> chats) async {
    _chats = [...chats];
    _answerErrors.clear();
    await _saveAndNotify();
  }

  /// Deletes every chat, for example when the user deletes all their data.
  Future<void> deleteAll() async {
    _chats = [];
    _answerErrors.clear();
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
        if (!chat.isExpiredAt(now, _keepFor)) chat,
    ];
    notifyListeners();
    await _repository.save(_chats);
  }
}
