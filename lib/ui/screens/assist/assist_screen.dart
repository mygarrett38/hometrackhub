import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../services/home_assistant_client.dart';
import '../../home_shell.dart';

/// Assist tab: a chat with an AI assistant for home maintenance questions.
/// The conversation is kept only while the app is open.
class AssistScreen extends StatefulWidget {
  const AssistScreen({super.key});

  /// Example questions shown before the first message. Tapping one asks it.
  static const suggestions = [
    'How often should I replace my furnace filter?',
    "My dishwasher isn't draining. What should I check?",
    'How do I get my outdoor faucets ready for winter?',
  ];

  /// Longest question the user can type, well under the server's limit.
  static const maxQuestionLength = 2000;

  @override
  State<AssistScreen> createState() => _AssistScreenState();
}

/// One message in the conversation, with the assistant's suggestion to hire
/// a professional if it made one.
typedef _ChatEntry = ({AssistantMessage message, String? professionalNote});

class _AssistScreenState extends State<AssistScreen> {
  final _entries = <_ChatEntry>[];
  final _input = TextEditingController();

  bool _sending = false;

  /// Shown on screen when the last question couldn't be answered.
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final configured = context.read<HomeAssistantClient>().isConfigured;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Assist'),
        actions: [
          if (_entries.isNotEmpty)
            IconButton(
              tooltip: 'New conversation',
              icon: const Icon(Icons.add_comment_outlined),
              onPressed: _sending ? null : _newConversation,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _entries.isEmpty
                ? _Intro(configured: configured, onSuggestion: _send)
                : _Conversation(entries: _entries, waiting: _sending),
          ),
          if (_error case final error?)
            _ErrorRow(message: error, onRetry: _retry),
          if (configured)
            _Composer(controller: _input, sending: _sending, onSend: _send),
        ],
      ),
    );
  }

  void _send(String text) {
    final question = text.trim();
    if (question.isEmpty || _sending) return;
    setState(() {
      _entries.add((
        message: AssistantMessage.user(question),
        professionalNote: null,
      ));
      _input.clear();
    });
    _ask();
  }

  void _retry() => _ask();

  Future<void> _ask() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    final client = context.read<HomeAssistantClient>();
    try {
      final reply = await client.ask([
        for (final entry in _entries) entry.message,
      ]);
      if (!mounted) return;
      final reason = reply.professionalReason?.trim() ?? '';
      setState(() {
        _entries.add((
          message: AssistantMessage.assistant(reply.answer),
          professionalNote: reply.recommendProfessional
              ? (reason.isEmpty ? 'This is a job for a professional.' : reason)
              : null,
        ));
      });
    } on AssistantConnectionException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _newConversation() {
    setState(() {
      _entries.clear();
      _error = null;
    });
  }
}

/// What the tab shows before the first question: what the assistant is for,
/// a few example questions, and where the questions are sent.
class _Intro extends StatelessWidget {
  const _Intro({required this.configured, required this.onSuggestion});

  final bool configured;
  final ValueChanged<String> onSuggestion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(
              Icons.forum_outlined,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Ask about home maintenance',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              configured
                  ? 'Get help with upkeep, cleaning and troubleshooting for '
                        'your home, appliances and vehicles.'
                  : "The assistant isn't available in this version of the "
                        'app.',
              textAlign: TextAlign.center,
            ),
            if (configured) ...[
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final suggestion in AssistScreen.suggestions)
                    ActionChip(
                      label: Text(suggestion),
                      onPressed: () => onSuggestion(suggestion),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                "Your questions are sent to Anthropic's Claude AI to get an "
                "answer, so don't include personal details. Answers can be "
                'wrong. For anything involving gas, electrical wiring or your '
                'safety, check with a professional.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The messages so far, newest at the bottom, with a placeholder while the
/// assistant is working on an answer.
class _Conversation extends StatelessWidget {
  const _Conversation({required this.entries, required this.waiting});

  final List<_ChatEntry> entries;
  final bool waiting;

  @override
  Widget build(BuildContext context) {
    final bubbles = [
      for (final entry in entries)
        _MessageBubble(
          message: entry.message,
          professionalNote: entry.professionalNote,
        ),
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
  const _MessageBubble({required this.message, this.professionalNote});

  final AssistantMessage message;
  final String? professionalNote;

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
          SelectableText(message.content, style: TextStyle(color: textColor)),
          if (professionalNote case final note?) ...[
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

/// The text field and send button at the bottom of the tab.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) {
    final isPhone =
        MediaQuery.sizeOf(context).width < HomeShell.wideLayoutBreakpoint;
    // On phones, leave room for the Overview button, which rises over the
    // bottom of the tab. With the side rail, leave room for the system
    // navigation bar instead.
    final bottom =
        8 +
        (isPhone
            ? HomeShell.overviewButtonRise
            : MediaQuery.paddingOf(context).bottom);

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 8, bottom),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              inputFormatters: [
                LengthLimitingTextInputFormatter(
                  AssistScreen.maxQuestionLength,
                ),
              ],
              decoration: const InputDecoration(
                hintText: 'Ask a maintenance question',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(24)),
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Rebuilds as the user types, so the button is only enabled when
          // there's a question to send.
          ValueListenableBuilder(
            valueListenable: controller,
            builder: (context, value, _) => IconButton.filled(
              tooltip: 'Send',
              icon: const Icon(Icons.send),
              onPressed: sending || value.text.trim().isEmpty
                  ? null
                  : () => onSend(value.text),
            ),
          ),
        ],
      ),
    );
  }
}
