import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';

import '../../../models/assist_chat.dart';
import '../../../services/home_assistant_client.dart';
import '../../../state/assist_chat_controller.dart';
import '../../../state/settings_controller.dart';
import 'assist_widgets.dart';

/// One Assist chat on its own screen, named after the chat, where the user
/// can ask follow-up questions. Chats are renamed and deleted from the chat
/// history.
class AssistChatScreen extends StatefulWidget {
  const AssistChatScreen({
    super.key,
    required this.chatId,
    this.askOnOpen = false,
  });

  final String chatId;

  /// Whether to ask the assistant to answer the chat's last question as soon
  /// as the screen opens, as when the chat was just started.
  final bool askOnOpen;

  @override
  State<AssistChatScreen> createState() => _AssistChatScreenState();
}

class _AssistChatScreenState extends State<AssistChatScreen> {
  final _input = TextEditingController();

  bool _sending = false;

  /// Shown on screen when the last question couldn't be answered.
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.askOnOpen) {
      _sending = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ask();
      });
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final configured = context.read<HomeAssistantClient>().isConfigured;
    final chats = context.watch<AssistChatController>();
    final chat = chats.chatById(widget.chatId);

    if (chat == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chat')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'This chat has been deleted.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    // A question left without an answer, for example in a chat reopened
    // from the history after the assistant couldn't be reached.
    final unanswered = !_sending && chat.isAwaitingAnswer;

    return Scaffold(
      appBar: AppBar(title: Text(chats.titleOf(chat))),
      body: Column(
        children: [
          Expanded(
            child: _Conversation(messages: chat.messages, waiting: _sending),
          ),
          if (unanswered && configured)
            _ErrorRow(
              message: _error ?? "This question hasn't been answered yet.",
              onRetry: _ask,
            ),
          if (configured)
            AssistComposer(controller: _input, sending: _sending, onSend: _send)
          else
            const _UnavailableNote(),
        ],
      ),
    );
  }

  Future<void> _send(String text) async {
    final question = text.trim();
    if (question.isEmpty || _sending) return;
    final chats = context.read<AssistChatController>();
    setState(() {
      _sending = true;
      _error = null;
      _input.clear();
    });
    await chats.addMessage(widget.chatId, AssistChatMessage.user(question));
    if (mounted) await _ask();
  }

  /// Asks the assistant to answer the last question in the chat, and saves
  /// the answer there.
  Future<void> _ask() async {
    final chats = context.read<AssistChatController>();
    final client = context.read<HomeAssistantClient>();
    final chat = chats.chatById(widget.chatId);
    if (chat == null) {
      setState(() => _sending = false);
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final reply = await client.ask(
        chat.recentMessages(),
        technicalLevel: context
            .read<SettingsController>()
            .settings
            .technicalLevel,
      );
      final reason = reply.professionalReason?.trim() ?? '';
      // Saved even if the user has left this screen, so it's there when
      // they come back to the chat.
      await chats.addMessage(
        widget.chatId,
        AssistChatMessage.assistant(
          reply.answer,
          professionalNote: reply.recommendProfessional
              ? (reason.isEmpty ? 'This is a job for a professional.' : reason)
              : null,
        ),
      );
    } on AssistantConnectionException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}

/// The messages so far, newest at the bottom, with a placeholder while the
/// assistant is working on an answer.
class _Conversation extends StatelessWidget {
  const _Conversation({required this.messages, required this.waiting});

  final List<AssistChatMessage> messages;
  final bool waiting;

  @override
  Widget build(BuildContext context) {
    final bubbles = [
      for (final message in messages) _MessageBubble(message: message),
      if (waiting) const _ThinkingBubble(),
    ];

    // Reversed so the list starts at the bottom and new messages push the
    // older ones up, without having to scroll it by hand.
    return ListView(
      reverse: true,
      padding: const EdgeInsets.all(16),
      children: bubbles.reversed.toList(),
    );
  }
}

/// One message: the user's on the right, the assistant's on the left.
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final AssistChatMessage message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isUser = message.isUser;
    final textColor = isUser ? colors.onPrimaryContainer : colors.onSurface;

    return _Bubble(
      alignEnd: isUser,
      color: isUser ? colors.primaryContainer : colors.surfaceContainerHigh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The user's own words are shown as typed. The assistant's answers
          // are formatted with Markdown, such as bold text and lists.
          if (isUser)
            SelectableText(message.content, style: TextStyle(color: textColor))
          else
            MarkdownBody(
              data: message.content,
              selectable: true,
              styleSheet: _markdownStyle(Theme.of(context), textColor),
            ),
          if (message.professionalNote case final note?) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.tertiaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.engineering_outlined,
                    size: 20,
                    color: colors.onTertiaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Consider a professional: $note',
                      style: TextStyle(color: colors.onTertiaryContainer),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Markdown styles that fit in a chat bubble: the app's usual text in
/// [textColor], with headings only a little larger than the text.
MarkdownStyleSheet _markdownStyle(ThemeData theme, Color textColor) {
  final text = theme.textTheme;
  TextStyle? colored(TextStyle? style) => style?.copyWith(color: textColor);

  return MarkdownStyleSheet.fromTheme(theme).copyWith(
    p: colored(text.bodyMedium),
    listBullet: colored(text.bodyMedium),
    h1: colored(text.titleMedium),
    h2: colored(text.titleMedium),
    h3: colored(text.titleSmall),
    h4: colored(text.titleSmall),
    blockquote: colored(text.bodyMedium),
    blockquoteDecoration: BoxDecoration(
      border: Border(left: BorderSide(color: theme.colorScheme.outline)),
    ),
    blockquotePadding: const EdgeInsets.only(left: 12),
    code: colored(text.bodySmall)?.copyWith(
      fontFamily: 'monospace',
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
    ),
    a: TextStyle(color: theme.colorScheme.primary),
  );
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return _Bubble(
      alignEnd: false,
      color: colors.surfaceContainerHigh,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text('Thinking…', style: TextStyle(color: colors.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// A rounded box on one side of the conversation, at most 85% of its width.
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.alignEnd,
    required this.color,
    required this.child,
  });

  final bool alignEnd;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final alignment = alignEnd ? Alignment.centerRight : Alignment.centerLeft;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: FractionallySizedBox(
        widthFactor: 0.85,
        alignment: alignment,
        // Lets short messages be narrower than the 85%.
        child: Align(
          alignment: alignment,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(16),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Shown instead of the text field when the app was built without the
/// assistant's settings, so saved chats can be read but not continued.
class _UnavailableNote extends StatelessWidget {
  const _UnavailableNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Keeps clear of the system navigation bar, as the text field does.
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          "The assistant is currently unavailable.",
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: errorColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: TextStyle(color: errorColor)),
          ),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}
