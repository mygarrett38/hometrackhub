import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/home_assistant_client.dart';
import '../../../state/assist_chat_controller.dart';
import 'assist_chat_screen.dart';
import 'assist_widgets.dart';

/// Starts a new chat with an AI assistant for home maintenance questions.
/// Each chat opens on its own screen.
class AssistNewChatScreen extends StatefulWidget {
  const AssistNewChatScreen({super.key});

  /// Example questions shown before the first message. Tapping one asks it.
  static const suggestions = [
    'How often should I replace my furnace filter?',
    "My dishwasher isn't draining. What should I check?",
    'How do I get my outdoor faucets ready for winter?',
  ];

  @override
  State<AssistNewChatScreen> createState() => _AssistNewChatScreenState();
}

class _AssistNewChatScreenState extends State<AssistNewChatScreen> {
  final _input = TextEditingController();

  /// Whether a new chat is being saved, so a double tap starts only one.
  bool _starting = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final configured = context.read<HomeAssistantClient>().isConfigured;

    return Scaffold(
      appBar: AppBar(title: const Text('New conversation')),
      body: Column(
        children: [
          Expanded(
            child: _Intro(configured: configured, onSuggestion: _startChat),
          ),
          AssistComposer(
            controller: _input,
            sending: _starting,
            onSend: _startChat,
            enabled: configured,
          ),
        ],
      ),
    );
  }

  /// Starts a chat with [text] as its first question and opens it.
  Future<void> _startChat(String text) async {
    final question = text.trim();
    if (question.isEmpty || _starting) return;
    final chats = context.read<AssistChatController>();
    setState(() => _starting = true);
    final chatId = await chats.startChat(question);
    if (!mounted) return;
    // The chat takes this screen's place, so back from it goes to the
    // Assist tab rather than to an empty new conversation.
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => AssistChatScreen(chatId: chatId, askOnOpen: true),
      ),
    );
  }
}

/// What the screen shows above the text field: what the assistant is for, a
/// few example questions, and where the questions are sent.
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
                  for (final suggestion in AssistNewChatScreen.suggestions)
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
