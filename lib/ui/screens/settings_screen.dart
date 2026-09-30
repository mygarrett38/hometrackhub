import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/app_settings.dart';
import '../../services/notification_service.dart';
import '../../state/home_item_controller.dart';
import '../../state/settings_controller.dart';
import 'home_location_screen.dart';

/// Settings tab: notifications, appearance, privacy and home location.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  /// Choices for how far ahead of the due date reminders are sent.
  static const _reminderLeadOptions = {
    0: 'On the due date',
    1: '1 day before',
    2: '2 days before',
    3: '3 days before',
    7: '1 week before',
    14: '2 weeks before',
  };

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final settings = controller.settings;

    void update(AppSettings newSettings) => controller.update(newSettings);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _SectionHeader('Notifications'),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: const Text('Maintenance reminders'),
            subtitle: const Text('Get notified when maintenance is due'),
            value: settings.notificationsEnabled,
            onChanged: (enabled) =>
                _setNotificationsEnabled(context, controller, enabled),
          ),
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('Reminder time'),
            subtitle: Text(
              TimeOfDay(
                hour: settings.reminderHour,
                minute: settings.reminderMinute,
              ).format(context),
            ),
            enabled: settings.notificationsEnabled,
            onTap: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(
                  hour: settings.reminderHour,
                  minute: settings.reminderMinute,
                ),
              );
              if (picked != null) {
                update(
                  settings.copyWith(
                    reminderHour: picked.hour,
                    reminderMinute: picked.minute,
                  ),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.event_note),
            title: const Text('When to remind me'),
            enabled: settings.notificationsEnabled,
            trailing: DropdownButton<int>(
              value:
                  _reminderLeadOptions.containsKey(settings.reminderDaysBefore)
                  ? settings.reminderDaysBefore
                  : 0,
              onChanged: settings.notificationsEnabled
                  ? (days) =>
                        update(settings.copyWith(reminderDaysBefore: days))
                  : null,
              items: [
                for (final MapEntry(key: days, value: label)
                    in _reminderLeadOptions.entries)
                  DropdownMenuItem(value: days, child: Text(label)),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.notification_add_outlined),
            title: const Text('Send a test notification'),
            enabled: settings.notificationsEnabled,
            onTap: () =>
                context.read<NotificationService>().showTestNotification(),
          ),

          const _SectionHeader('Appearance'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('System'),
                  icon: Icon(Icons.brightness_auto),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('Light'),
                  icon: Icon(Icons.light_mode),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('Dark'),
                  icon: Icon(Icons.dark_mode),
                ),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (selection) =>
                  update(settings.copyWith(themeMode: selection.single)),
            ),
          ),

          const _SectionHeader('Privacy'),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Everything you enter is stored only on this device and is '
              'never uploaded.',
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.wifi_find),
            title: const Text('Find smart devices on my network'),
            subtitle: const Text(
              'Allows scanning your local Wi-Fi network for smart devices',
            ),
            value: settings.networkDiscoveryEnabled,
            onChanged: (enabled) =>
                update(settings.copyWith(networkDiscoveryEnabled: enabled)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.visibility_off_outlined),
            title: const Text('Hide details in notifications'),
            subtitle: const Text(
              'Reminders will not name your home items, for example on a '
              'locked screen',
            ),
            value: settings.hideDetailsInNotifications,
            onChanged: (hide) =>
                update(settings.copyWith(hideDetailsInNotifications: hide)),
          ),
          ListTile(
            leading: const Icon(Icons.copy_all_outlined),
            title: const Text('Export my data'),
            subtitle: const Text('Copy all of your data to the clipboard'),
            onTap: () => _exportData(context),
          ),
          ListTile(
            leading: Icon(
              Icons.delete_forever_outlined,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'Delete all my data',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            subtitle: const Text('Removes all home items and settings'),
            onTap: () => _confirmDeleteAll(context),
          ),

          const _SectionHeader('Home'),
          ListTile(
            leading: const Icon(Icons.home_outlined),
            title: const Text('Home location'),
            subtitle: Text(
              settings.homeLocation.isEmpty
                  ? 'Not set'
                  : settings.homeLocation.summary,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const HomeLocationScreen(),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Future<void> _setNotificationsEnabled(
    BuildContext context,
    SettingsController controller,
    bool enabled,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final notifications = context.read<NotificationService>();

    await controller.update(
      controller.settings.copyWith(notificationsEnabled: enabled),
    );
    if (!enabled) return;

    final granted = await notifications.requestPermission();
    if (!granted) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Notifications are blocked. Allow them for HomeTrackHub in your '
            'device settings to receive reminders.',
          ),
        ),
      );
    }
  }

  Future<void> _exportData(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final export = {
      'exportedAt': DateTime.now().toIso8601String(),
      'settings': context.read<SettingsController>().settings.toJson(),
      'homeItems': [
        for (final item in context.read<HomeItemController>().homeItems)
          item.toJson(),
      ],
    };
    final json = const JsonEncoder.withIndent('  ').convert(export);
    await Clipboard.setData(ClipboardData(text: json));
    messenger.showSnackBar(
      const SnackBar(content: Text('Your data was copied to the clipboard.')),
    );
  }

  Future<void> _confirmDeleteAll(BuildContext context) async {
    final homeItems = context.read<HomeItemController>();
    final settings = context.read<SettingsController>();
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all data?'),
        content: const Text(
          'This permanently deletes all of your home items, maintenance '
          'history, reminders and settings from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await homeItems.deleteAll();
      await settings.reset();
      messenger.showSnackBar(
        const SnackBar(content: Text('All data was deleted.')),
      );
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}
