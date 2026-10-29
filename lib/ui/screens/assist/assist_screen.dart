import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/home_assistant_client.dart';
import 'assist_history_screen.dart';
import 'assist_new_chat_screen.dart';
import 'nearby_services_screen.dart';

/// Assist tab: asks what the user would like to do, and opens a new chat
/// with the AI assistant, an earlier chat, or the nearby services search.
class AssistScreen extends StatelessWidget {
  const AssistScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final configured = context.read<HomeAssistantClient>().isConfigured;

    return Scaffold(
      body: Center(
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
                  'What would you like to do today?',
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: configured
                      ? () => _open(context, const AssistNewChatScreen())
                      : null,
                  icon: const Icon(Icons.add_comment_outlined),
                  label: const Text('New conversation'),
                ),
                if (!configured) ...[
                  const SizedBox(height: 8),
                  Text(
                    "The assistant is currently unavailable.",
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: () => _open(context, const AssistHistoryScreen()),
                  icon: const Icon(Icons.history),
                  label: const Text('Continue conversation'),
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: () => _open(context, const NearbyServicesScreen()),
                  icon: const Icon(Icons.location_on_outlined),
                  label: const Text('Search nearby services'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }
}
