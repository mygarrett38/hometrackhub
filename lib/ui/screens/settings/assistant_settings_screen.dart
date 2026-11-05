import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/app_settings.dart';
import '../../../models/technical_level.dart';
import '../../../state/assist_chat_controller.dart';
import '../../../state/settings_controller.dart';
import '../../widgets/screen_padding.dart';
import '../../widgets/settings_card.dart';
import '../../widgets/settings_dropdown_row.dart';

/// Settings for the Assist tab's AI assistant: a switch in the top bar that
/// turns it on or off, how much it explains, and how long chats are kept.
/// When it's off, the Assist tab only searches for nearby services.
class AssistantSettingsScreen extends StatelessWidget {
  const AssistantSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final settings = controller.settings;
    final chats = context.watch<AssistChatController>().chats;
    final errorColor = Theme.of(context).colorScheme.error;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Assistant'),
        actions: [
          // The switch has no label of its own on screen, so its tooltip
          // says what it does, and screen readers read that.
          Padding(
            // Lines up with the cards' right edge below rather than
            // crowding the screen's edge.
            padding: const EdgeInsets.only(right: 16),
            child: Tooltip(
              message: 'Use the AI assistant',
              child: Switch(
                value: settings.assistantEnabled,
                onChanged: (enabled) => controller.update(
                  settings.copyWith(assistantEnabled: enabled),
                ),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: screenPadding(context),
        children: [
          // While the assistant is off, its other settings are hidden and
          // only this message is shown.
          if (!settings.assistantEnabled)
            const SettingsCard(
              children: [
                ListTile(
                  leading: Icon(Icons.location_on_outlined),
                  title: Text('The assistant is off'),
                  subtitle: Text(
                    'The Assist tab only searches for nearby services, and '
                    'nothing is sent to the AI assistant. Your saved chats '
                    'are kept.',
                  ),
                ),
              ],
            )
          else ...[
            SettingsCard(
              children: [
                SettingsDropdownRow<TechnicalLevel>(
                  icon: Icons.handyman_outlined,
                  title: 'Technical level',
                  description:
                      'How much the assistant explains. Beginners get simple '
                      'step-by-step answers, and handy users get shorter ones.',
                  value: settings.technicalLevel,
                  choices: {
                    for (final level in TechnicalLevel.values)
                      level: level.label,
                  },
                  onChanged: (level) => controller.update(
                    settings.copyWith(technicalLevel: level),
                  ),
                ),
              ],
            ),
            SettingsCard(
              children: [
                SettingsDropdownRow<int>(
                  icon: Icons.history,
                  title: 'Keep chats for',
                  description:
                      'Chats without a new message for this long are deleted. '
                      'Pinned chats are kept until you unpin them.',
                  value: settings.keepChatsDays,
                  choices: {
                    for (final days in AppSettings.keepChatsDayChoices)
                      days: '$days days',
                  },
                  onChanged: (days) => _changeKeepChats(context, days),
                ),
                ListTile(
                  leading: Icon(
                    Icons.delete_forever_outlined,
                    color: chats.isEmpty ? null : errorColor,
                  ),
                  title: Text(
                    'Delete chats',
                    style: chats.isEmpty ? null : TextStyle(color: errorColor),
                  ),
                  // Greyed out when there's nothing to delete.
                  enabled: chats.isNotEmpty,
                  onTap: () => _confirmDeleteChats(context, chats.length),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Keeps chats for [days], first checking with the user if that deletes
  /// chats that are older than that.
  Future<void> _changeKeepChats(BuildContext context, int days) async {
    final controller = context.read<SettingsController>();
    final deleted = context.read<AssistChatController>().countExpiredIfKeptFor(
      Duration(days: days),
    );
    if (deleted > 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Keep chats for $days days?'),
          content: Text(
            deleted == 1
                ? "1 chat hasn't had a new message in $days days, so it "
                      'will be deleted now.'
                : "$deleted chats haven't had a new message in $days days, "
                      'so they will be deleted now.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete and change'),
            ),
          ],
        ),
      );
      if (!(confirmed ?? false)) return;
    }
    await controller.update(controller.settings.copyWith(keepChatsDays: days));
  }

  Future<void> _confirmDeleteChats(BuildContext context, int count) async {
    final chats = context.read<AssistChatController>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all chats?'),
        content: Text(
          count == 1
              ? 'This permanently deletes your saved chat, even if it is '
                    'pinned.'
              : 'This permanently deletes all $count saved chats, including '
                    'pinned ones.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete chats'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await chats.deleteAll();
  }
}
