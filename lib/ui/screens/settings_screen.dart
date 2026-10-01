import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_settings.dart';
import '../../state/settings_controller.dart';
import 'appearance_settings_screen.dart';
import 'home_location_screen.dart';
import 'notification_settings_screen.dart';
import 'privacy_settings_screen.dart';

/// Settings tab: one row per category of settings, each opening its own
/// screen. Each row's subtitle summarizes the current choices.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>().settings;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notifications'),
            subtitle: Text(_describeOverview(context, settings)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(context, const NotificationSettingsScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Appearance'),
            subtitle: Text(themeModeLabels[settings.themeMode]!),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(context, const AppearanceSettingsScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Privacy'),
            subtitle: const Text(
              'Network scanning, notification details and your data',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(context, const PrivacySettingsScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.home_outlined),
            title: const Text('Home location'),
            subtitle: Text(
              settings.homeLocation.isEmpty
                  ? 'Not set'
                  : settings.homeLocation.summary,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(context, const HomeLocationScreen()),
          ),
        ],
      ),
    );
  }

  /// For example "Weekly overview on Monday at 8:00 AM".
  String _describeOverview(BuildContext context, AppSettings settings) {
    final time = TimeOfDay(
      hour: settings.overviewHour,
      minute: settings.overviewMinute,
    ).format(context);
    return switch (settings.overviewFrequency) {
      OverviewFrequency.off => 'Overview off',
      OverviewFrequency.weekly =>
        'Weekly overview on ${weekdayNames[settings.overviewWeekday]} '
            'at $time',
      OverviewFrequency.monthly => 'Monthly overview on the 1st at $time',
    };
  }
}
