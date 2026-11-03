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

  /// Example questions. A few are picked at random each time the screen
  /// opens, and tapping one asks it.
  static const questions = [
    'How often should I replace my furnace filter?',
    "My dishwasher isn't draining. What should I check?",
    'How do I get my outdoor faucets ready for winter?',
    'How often should I clean my dryer vent?',
    'Why does my water heater make popping noises?',
    'How do I test my smoke and carbon monoxide alarms?',
    "What should I check if my air conditioner isn't cooling?",
    'How often should my gutters be cleaned?',
    'How do I clean the coils on my refrigerator?',
    'My garbage disposal hums but won\'t spin. What can I do?',
    'How often should I rotate my car\'s tires?',
    'How do I unclog a slow bathroom sink?',
    'When should I flush my water heater?',
    'How do I reset a GFCI outlet that keeps tripping?',
    'What should I check on my roof after a storm?',
  ];

  /// How many example questions are shown.
  static const suggestionCount = 3;

  @override
  State<AssistNewChatScreen> createState() => _AssistNewChatScreenState();
}

class _AssistNewChatScreenState extends State<AssistNewChatScreen> {
  final _input = TextEditingController();

  /// The example questions picked for this visit. Picked once, so they don't
  /// change while the screen is open.
  final _suggestions = (List.of(
    AssistNewChatScreen.questions,
  )..shuffle()).take(AssistNewChatScreen.suggestionCount).toList();

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
      appBar: AppBar(
        title: const Text('New conversation'),
        actions: [
          IconButton(
            tooltip: 'About the assistant',
            icon: const Icon(Icons.info_outline),
            onPressed: _showInfo,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _Intro(
              configured: configured,
              suggestions: _suggestions,
              onSuggestion: _startChat,
            ),
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

  /// Explains where questions are sent and how far to trust the answers.
  void _showInfo() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About the assistant'),
        content: const Text(
          "Your questions are sent to Anthropic's Claude AI to get an answer, "
          "so don't include personal details. Answers can be wrong. For "
          'anything involving gas, electrical wiring or your safety, check '
          'with a professional.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
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

/// What the screen shows above the text field: what the assistant is for
/// and a few example questions.
class _Intro extends StatelessWidget {
  const _Intro({
    required this.configured,
    required this.suggestions,
    required this.onSuggestion,
  });

  final bool configured;
  final List<String> suggestions;
  final ValueChanged<String> onSuggestion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    ? 'Try these examples to get started.'
                    : "The assistant isn't available in this version of the "
                          'app.',
                textAlign: TextAlign.center,
              ),
              if (configured) ...[
                const SizedBox(height: 24),
                // Full-width buttons whose text wraps, so long questions are
                // never cut off.
                for (final suggestion in suggestions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton(
                      onPressed: () => onSuggestion(suggestion),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(suggestion, textAlign: TextAlign.center),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
