import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/app_settings.dart';
import '../../../services/notification_service.dart';
import '../../../state/settings_controller.dart';
import '../../widgets/notification_permission.dart';

/// Weekday names for the weekly overview, keyed by [DateTime.weekday].
const weekdayNames = {
  DateTime.monday: 'Monday',
  DateTime.tuesday: 'Tuesday',
  DateTime.wednesday: 'Wednesday',
  DateTime.thursday: 'Thursday',
  DateTime.friday: 'Friday',
  DateTime.saturday: 'Saturday',
  DateTime.sunday: 'Sunday',
};

/// Settings for the weekly or monthly maintenance overview notification.
/// Reminders for individual tasks are set on each task.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  /// Whether notifications turned out to be blocked when the overview was
  /// turned on.
  bool _blocked = false;

  /// Whether the device's notification settings couldn't be opened.
  bool _couldNotOpenSettings = false;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final settings = controller.settings;

    void update(AppSettings newSettings) => controller.update(newSettings);

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
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
                onSelectionChanged: (selection) =>
                    _setOverviewFrequency(controller, selection.single),
              ),
            ),
          ),
          if (_blocked && settings.overviewFrequency != OverviewFrequency.off)
            const NotificationsBlockedNotice(),
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
                      in weekdayNames.entries)
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
            leading: const Icon(Icons.phone_android),
            title: const Text('Notification settings'),
            subtitle: _couldNotOpenSettings
                ? Text(
                    "Could not open notification settings. Open your "
                    "device's Settings app and find HomeTrackHub instead.",
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  )
                : null,
            trailing: const Icon(Icons.open_in_new),
            onTap: _openDeviceSettings,
          ),
          ListTile(
            leading: const Icon(Icons.notification_add_outlined),
            title: const Text('Send a test notification'),
            onTap: () =>
                context.read<NotificationService>().showTestNotification(),
          ),
          
        ],
      ),
    );
  }

  Future<void> _openDeviceSettings() async {
    final opened = await context
        .read<NotificationService>()
        .openDeviceNotificationSettings();
    if (mounted) setState(() => _couldNotOpenSettings = !opened);
  }

  Future<void> _setOverviewFrequency(
    SettingsController controller,
    OverviewFrequency frequency,
  ) async {
    await controller.update(
      controller.settings.copyWith(overviewFrequency: frequency),
    );
    if (frequency != OverviewFrequency.off && mounted) {
      final allowed = await requestNotificationPermission(context);
      if (mounted) setState(() => _blocked = !allowed);
    }
  }
}
