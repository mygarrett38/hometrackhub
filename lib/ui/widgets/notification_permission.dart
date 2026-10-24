import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/notification_service.dart';

/// Asks for permission to show notifications, returning whether they're
/// allowed. Call this when the user turns on a reminder or the overview
/// notification, and show [NotificationsBlockedNotice] if it returns false.
Future<bool> requestNotificationPermission(BuildContext context) =>
    context.read<NotificationService>().requestPermission();

/// Explains, in place on the screen, that notifications are blocked and how
/// to allow them.
class NotificationsBlockedNotice extends StatelessWidget {
  const NotificationsBlockedNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.error;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.notifications_off_outlined, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Notifications are blocked. Allow them for HomeTrackHub in your '
              'device settings to receive reminders.',
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
