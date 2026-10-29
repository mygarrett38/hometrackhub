import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/assist_chat.dart';
import '../../../state/assist_chat_controller.dart';
import '../../../utils/date_utils.dart';
import '../../widgets/screen_padding.dart';
import 'assist_chat_screen.dart';

/// The user's saved Assist chats as cards, most recently active first.
/// Tapping one opens it on its own screen, where it can be renamed or
/// deleted.
class AssistHistoryScreen extends StatelessWidget {
  const AssistHistoryScreen({super.key});

  static final _expiryNote =
      'Chats are saved only on this device and are deleted after '
      '${AssistChat.expiresAfter.inDays} days without new messages.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = context.watch<AssistChatController>();
    final chats = controller.chats;
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(title: const Text('Chat history')),
      body: chats.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'You have no saved chats yet.\n\n$_expiryNote',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: screenPadding(context),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_expiryNote, style: theme.textTheme.bodySmall),
                ),
                for (final chat in chats)
                  Card(
                    key: ValueKey(chat.id),
                    clipBehavior: Clip.antiAlias,
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: const Icon(Icons.chat_bubble_outline),
                      title: Text(
                        controller.titleOf(chat),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(_describe(chat, now)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => AssistChatScreen(chatId: chat.id),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  /// When the chat was last active and when it will be deleted, for example
  /// "Active 3 days ago · Deleted in 11 days".
  static String _describe(AssistChat chat, DateTime now) {
    final daysAgo = calendarDaysBetween(chat.lastActiveAt, now);
    final active = switch (daysAgo) {
      <= 0 => 'Active today',
      1 => 'Active yesterday',
      _ => 'Active $daysAgo days ago',
    };
    final daysLeft = calendarDaysBetween(now, chat.expiresAt);
    final deleted = switch (daysLeft) {
      <= 0 => 'Deleted today',
      1 => 'Deleted tomorrow',
      _ => 'Deleted in $daysLeft days',
    };
    return '$active · $deleted';
  }
}
