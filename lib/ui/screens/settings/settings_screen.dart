import 'package:flutter/material.dart';

import '../../widgets/screen_padding.dart';
import '../../widgets/settings_card.dart';
import 'appearance_settings_screen.dart';
import 'assistant_settings_screen.dart';
import 'calendar_settings_screen.dart';
import 'notification_settings_screen.dart';
import 'privacy_settings_screen.dart';

/// Settings tab: a card listing each category of settings, each opening its
/// own screen.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const _categories = [
    (
      icon: Icons.notifications_outlined,
      title: 'Notifications',
      screen: NotificationSettingsScreen(),
    ),
    (
      icon: Icons.event_outlined,
      title: 'Calendar sync',
      screen: CalendarSettingsScreen(),
    ),
    (
      icon: Icons.palette_outlined,
      title: 'Appearance',
      screen: AppearanceSettingsScreen(),
    ),
    (
      icon: Icons.forum_outlined,
      title: 'Assistant',
      screen: AssistantSettingsScreen(),
    ),
    (
      icon: Icons.lock_outline,
      title: 'Privacy',
      screen: PrivacySettingsScreen(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: screenPadding(context),
        children: [
          SettingsCard(
            children: [
              for (final category in _categories)
                ListTile(
                  leading: Icon(category.icon),
                  title: Text(category.title),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => category.screen),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
