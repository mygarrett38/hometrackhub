import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/notification_service.dart';

/// Asks for permission to show notifications, and explains how to allow
/// them if the user has blocked them. Call this when the user turns on a
/// reminder or the overview notification.
Future<void> requestNotificationPermission(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final granted = await context.read<NotificationService>().requestPermission();
  if (granted) return;

  messenger.showSnackBar(
    const SnackBar(
      content: Text(
        'Notifications are blocked. Allow them for HomeTrackHub in your '
        'device settings to receive reminders.',
      ),
    ),
  );
}
