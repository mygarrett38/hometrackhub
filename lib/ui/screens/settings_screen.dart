import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/app_settings.dart';
import '../../services/notification_service.dart';
import '../../state/home_item_controller.dart';
import '../../state/settings_controller.dart';
import '../widgets/notification_permission.dart';
import '../widgets/section_header.dart';
import 'home_location_screen.dart';

/// Settings tab: notifications, appearance, privacy and home location.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  /// Weekday names for the weekly overview, keyed by [DateTime.weekday].
  static const _weekdays = {
    DateTime.monday: 'Monday',
    DateTime.tuesday: 'Tuesday',
    DateTime.wednesday: 'Wednesday',
    DateTime.thursday: 'Thursday',
    DateTime.friday: 'Friday',
    DateTime.saturday: 'Saturday',
    DateTime.sunday: 'Sunday',
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
          const SectionHeader('Notifications'),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Reminders for each task are set on that task. You can also get '
              'an overview of the maintenance coming up each week or month.',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.summarize_outlined),
            title: const Text('Maintenance overview'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SegmentedButton<OverviewFrequency>(
                segments: [
                  for (final frequency in OverviewFrequency.values)
                    ButtonSegment(
                      value: frequency,
                      label: Text(frequency.label),
                    ),
                ],
                selected: {settings.overviewFrequency},
                onSelectionChanged: (selection) => _setOverviewFrequency(
                  context,
                  controller,
                  selection.single,
                ),
              ),
            ),
          ),
          if (settings.overviewFrequency == OverviewFrequency.weekly)
            ListTile(
              leading: const Icon(Icons.calendar_view_week),
              title: const Text('Overview day'),
              trailing: DropdownButton<int>(
                value: settings.overviewWeekday,
                onChanged: (weekday) =>
                    update(settings.copyWith(overviewWeekday: weekday)),
                items: [
                  for (final MapEntry(key: weekday, value: name)
                      in _weekdays.entries)
                    DropdownMenuItem(value: weekday, child: Text(name)),
                ],
              ),
            ),
          if (settings.overviewFrequency == OverviewFrequency.monthly)
            const ListTile(
              leading: Icon(Icons.calendar_month),
              title: Text('Overview day'),
              trailing: Text('1st of each month'),
            ),
          if (settings.overviewFrequency != OverviewFrequency.off)
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Overview time'),
              trailing: Text(
                TimeOfDay(
                  hour: settings.overviewHour,
                  minute: settings.overviewMinute,
                ).format(context),
              ),
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay(
                    hour: settings.overviewHour,
                    minute: settings.overviewMinute,
                  ),
                );
                if (picked != null) {
                  update(
                    settings.copyWith(
                      overviewHour: picked.hour,
                      overviewMinute: picked.minute,
                    ),
                  );
                }
              },
            ),
          ListTile(
            leading: const Icon(Icons.notification_add_outlined),
            title: const Text('Send a test notification'),
            onTap: () =>
                context.read<NotificationService>().showTestNotification(),
          ),
          ListTile(
            leading: const Icon(Icons.phone_android),
            title: const Text('Notification settings'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => _openDeviceSettings(context),
          ),

          const SectionHeader('Appearance'),
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

          const SectionHeader('Privacy'),
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

          const SectionHeader('Home'),
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

  Future<void> _openDeviceSettings(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final opened = await context
        .read<NotificationService>()
        .openDeviceNotificationSettings();
    if (!opened) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            "Could not open notification settings. Open your device's "
            'Settings app and find HomeTrackHub instead.',
          ),
        ),
      );
    }
  }

  Future<void> _setOverviewFrequency(
    BuildContext context,
    SettingsController controller,
    OverviewFrequency frequency,
  ) async {
    await controller.update(
      controller.settings.copyWith(overviewFrequency: frequency),
    );
    if (frequency != OverviewFrequency.off && context.mounted) {
      await requestNotificationPermission(context);
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
