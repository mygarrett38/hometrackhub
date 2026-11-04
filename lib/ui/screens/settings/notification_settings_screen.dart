import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/app_settings.dart';
import '../../../services/notification_service.dart';
import '../../../state/settings_controller.dart';
import '../../widgets/notification_permission.dart';
import '../../widgets/screen_padding.dart';
import '../../widgets/settings_card.dart';

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
    // List rows draw text on their right very small, so the day and time
    // are given the same size as the menus beside them.
    final valueStyle = Theme.of(context).textTheme.titleMedium;

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        padding: screenPadding(context),
        children: [
          // The device's own settings for this app.
          SettingsCard(
            children: [
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
          // The overview and when it's sent.
          SettingsCard(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _OverviewRow(
                    frequency: settings.overviewFrequency,
                    onChanged: (frequency) =>
                        _setOverviewFrequency(controller, frequency),
                  ),
                  if (_blocked &&
                      settings.overviewFrequency != OverviewFrequency.off)
                    const NotificationsBlockedNotice(),
                ],
              ),
              if (settings.overviewFrequency == OverviewFrequency.weekly)
                ListTile(
                  leading: const Icon(Icons.calendar_view_week),
                  title: const Text('Overview day'),
                  trailing: DropdownButton<int>(
                    value: settings.overviewWeekday,
                    // Like the overview menu, the day sits against the
                    // right edge.
                    alignment: AlignmentDirectional.centerEnd,
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
                ListTile(
                  leading: const Icon(Icons.calendar_month),
                  title: const Text('Overview day'),
                  trailing: Text('1st of each month', style: valueStyle),
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
                    style: valueStyle,
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
            ],
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

/// Asks whether to receive overviews, with the menu in the top right and a
/// description below that runs the full width after the icon. A [ListTile]
/// would squeeze the description in beside the menu.
class _OverviewRow extends StatelessWidget {
  const _OverviewRow({required this.frequency, required this.onChanged});

  final OverviewFrequency frequency;
  final ValueChanged<OverviewFrequency> onChanged;

  /// As tall as the menu, so the question lines up with it.
  static const _menuHeight = 48.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // The same spacing and text styles as the list rows around it.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(
            height: _menuHeight,
            child: Icon(Icons.summarize_outlined),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // At least as tall as the menu, but taller for large text.
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: _menuHeight),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Receive overviews?',
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                      DropdownButton<OverviewFrequency>(
                        value: frequency,
                        // The choice sits against the right edge, however
                        // short it is.
                        alignment: AlignmentDirectional.centerEnd,
                        onChanged: (frequency) {
                          if (frequency != null) onChanged(frequency);
                        },
                        items: [
                          for (final frequency in OverviewFrequency.values)
                            DropdownMenuItem(
                              value: frequency,
                              child: Text(frequency.label),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Text(
                  'A notification summarizing the maintenance coming up each '
                  'week or month.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
