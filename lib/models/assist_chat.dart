import 'package:flutter/foundation.dart';

import '../services/home_assistant_client.dart';

/// One message in an [AssistChat].
@immutable
class AssistChatMessage {
  const AssistChatMessage({
    required this.role,
    required this.content,
    this.professionalNote,
  });

  const AssistChatMessage.user(this.content)
    : role = 'user',
      professionalNote = null;

  const AssistChatMessage.assistant(this.content, {this.professionalNote})
    : role = 'assistant';

  /// "user" or "assistant".
  final String role;
  final String content;

  /// Why the assistant suggested hiring a professional, if it did.
  final String? professionalNote;

  bool get isUser => role == 'user';

  AssistantMessage toAssistantMessage() =>
      AssistantMessage(role: role, content: content);

  Map<String, dynamic> toJson() => {
    'role': role,
    'content': content,
    if (professionalNote != null) 'professionalNote': professionalNote,
  };

  factory AssistChatMessage.fromJson(Map<String, dynamic> json) =>
      AssistChatMessage(
        role: json['role'] as String,
        content: json['content'] as String,
        professionalNote: json['professionalNote'] as String?,
      );
}

/// A conversation on the Assist tab, saved on the device so the user can
/// come back to it. Deleted after [expiresAfter] without new messages.
@immutable
class AssistChat {
  const AssistChat({
    required this.id,
    required this.messages,
    required this.createdAt,
    required this.lastActiveAt,
    required this.dayNumber,
    this.name,
  });

  /// How long a chat is kept after its last message.
  static const expiresAfter = Duration(days: 14);

  /// The most messages sent to the assistant with each question. Older ones
  /// are left out so long chats stay under the server's limits.
  static const maxMessagesSent = 20;

  /// The most characters of earlier messages sent with each question.
  static const maxCharactersSent = 30000;

  final String id;

  /// The name the user gave the chat. `null` until they rename it, in which
  /// case it's named after the day it was started. See
  /// `AssistChatController.titleOf`.
  final String? name;

  final List<AssistChatMessage> messages;
  final DateTime createdAt;

  /// Which chat of the day this was: 1 for the first chat started on the
  /// day of [createdAt], 2 for the next, and so on. Used in its default
  /// name, and never changes once given.
  final int dayNumber;

  /// When the last message was added. The chat expires [expiresAfter] later.
  final DateTime lastActiveAt;

  DateTime get expiresAt => lastActiveAt.add(expiresAfter);

  bool isExpiredAt(DateTime now) => !now.isBefore(expiresAt);

  /// Whether the last question is still waiting for an answer, for example
  /// because the assistant couldn't be reached.
  bool get isAwaitingAnswer => messages.isNotEmpty && messages.last.isUser;

  /// The end of the conversation to send with the next question: at most
  /// [maxMessagesSent] messages and [maxCharactersSent] characters, always
  /// starting with one of the user's messages.
  List<AssistantMessage> recentMessages() {
    final recent = <AssistChatMessage>[];
    var characters = 0;
    for (final message in messages.reversed) {
      if (recent.length == maxMessagesSent) break;
      characters += message.content.length;
      // Always keep the latest question, however long it is.
      if (recent.isNotEmpty && characters > maxCharactersSent) break;
      recent.insert(0, message);
    }
    while (recent.isNotEmpty && !recent.first.isUser) {
      recent.removeAt(0);
    }
    return [for (final message in recent) message.toAssistantMessage()];
  }

  AssistChat copyWith({
    String? name,
    bool clearName = false,
    List<AssistChatMessage>? messages,
    DateTime? lastActiveAt,
  }) {
    return AssistChat(
      id: id,
      name: clearName ? null : name ?? this.name,
      messages: messages ?? this.messages,
      createdAt: createdAt,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      dayNumber: dayNumber,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    if (name != null) 'name': name,
    'messages': [for (final message in messages) message.toJson()],
    'createdAt': createdAt.toIso8601String(),
    'lastActiveAt': lastActiveAt.toIso8601String(),
    'dayNumber': dayNumber,
  };

  factory AssistChat.fromJson(Map<String, dynamic> json) => AssistChat(
    id: json['id'] as String,
    name: json['name'] as String?,
    messages: [
      for (final message in json['messages'] as List<dynamic>)
        AssistChatMessage.fromJson(message as Map<String, dynamic>),
    ],
    createdAt: DateTime.parse(json['createdAt'] as String),
    lastActiveAt: DateTime.parse(json['lastActiveAt'] as String),
    dayNumber: json['dayNumber'] as int,
  );
}
