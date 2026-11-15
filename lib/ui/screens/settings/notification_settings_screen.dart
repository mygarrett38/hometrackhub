import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/app_settings.dart';
import '../../../services/notification_service.dart';
import '../../../state/settings_controller.dart';
import '../../widgets/form_rows.dart';
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

/// For example "every day", "every 3 days" or "every 2 weeks", following a
/// time as in "9:00 AM every day".
String reminderIntervalLabel(int days) => switch (days) {
  1 => 'every day',
  7 => 'every week',
  _ when days % 7 == 0 => 'every ${days ~/ 7} weeks',
  _ => 'every $days days',
};

/// The kinds of notification that can be turned off.
enum _NotificationKind { overdue, overview }

/// Settings for each kind of notification: upcoming tasks, which are always
/// sent, and overdue tasks and overviews, which can be turned off. Each has
/// its own time and how often it repeats. How far ahead each task is first
/// notified about is set on the task.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  /// The kinds of notification that were turned on while notifications
  /// turned out to be blocked.
  final Set<_NotificationKind> _blocked = {};

  /// Whether the device's notification settings couldn't be opened.
  bool _couldNotOpenSettings = false;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final settings = controller.settings;

    // Changes the latest settings, which may be newer than [settings] after
    // a picker has been open.
    void update(AppSettings Function(AppSettings) change) =>
        controller.update(change(controller.settings));

    final repeatChoices = {
      for (final days in AppSettings.reminderDayChoices)
        days: reminderIntervalLabel(days),
    };
    const divider = Divider(height: 1);

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
          // Each kind of notification, and when it arrives.
          Card(
            clipBehavior: Clip.antiAlias,
            margin: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Always sent, as long as the device allows notifications,
                // so it folds open with an arrow rather than a switch.
                ExpansionTile(
                  title: const Text('Upcoming tasks'),
                  // The card draws the outline, so the tile shouldn't add
                  // its own borders when open.
                  shape: const Border(),
                  collapsedShape: const Border(),
                  children: [
                    divider,
                    _ReceiveAtRow<int>(
                      key: const Key('upcomingReceiveAt'),
                      hour: settings.upcomingHour,
                      minute: settings.upcomingMinute,
                      onTimeChanged: (time) => update(
                        (s) => s.copyWith(
                          upcomingHour: time.hour,
                          upcomingMinute: time.minute,
                        ),
                      ),
                      repeat: settings.upcomingReminderDays,
                      repeatChoices: repeatChoices,
                      onRepeatChanged: (days) =>
                          update((s) => s.copyWith(upcomingReminderDays: days)),
                    ),
                  ],
                ),
                divider,
                _SwitchedSection(
                  title: 'Overdue tasks',
                  enabled: settings.overdueEnabled,
                  blocked: _blocked.contains(_NotificationKind.overdue),
                  onChanged: (enabled) => _turnOn(
                    _NotificationKind.overdue,
                    enabled,
                    settings.copyWith(overdueEnabled: enabled),
                  ),
                  children: [
                    _ReceiveAtRow<int>(
                      key: const Key('overdueReceiveAt'),
                      hour: settings.overdueHour,
                      minute: settings.overdueMinute,
                      onTimeChanged: (time) => update(
                        (s) => s.copyWith(
                          overdueHour: time.hour,
                          overdueMinute: time.minute,
                        ),
                      ),
                      repeat: settings.overdueReminderDays,
                      repeatChoices: repeatChoices,
                      onRepeatChanged: (days) =>
                          update((s) => s.copyWith(overdueReminderDays: days)),
                    ),
                  ],
                ),
                divider,
                _SwitchedSection(
                  title: 'Overviews',
                  enabled: settings.overviewEnabled,
                  blocked: _blocked.contains(_NotificationKind.overview),
                  onChanged: (enabled) => _turnOn(
                    _NotificationKind.overview,
                    enabled,
                    settings.copyWith(overviewEnabled: enabled),
                  ),
                  children: [
                    _ReceiveAtRow<OverviewFrequency>(
                      key: const Key('overviewReceiveAt'),
                      hour: settings.overviewHour,
                      minute: settings.overviewMinute,
                      onTimeChanged: (time) => update(
                        (s) => s.copyWith(
                          overviewHour: time.hour,
                          overviewMinute: time.minute,
                        ),
                      ),
                      repeat: settings.overviewFrequency,
                      repeatChoices: {
                        for (final frequency in OverviewFrequency.values)
                          frequency: frequency.label,
                      },
                      onRepeatChanged: (frequency) => update(
                        (s) => s.copyWith(overviewFrequency: frequency),
                      ),
                    ),
                    _SubRow(
                      label: 'Day',
                      // Monthly overviews have no menu, so the text needs
                      // the space the menu's arrow would take.
                      endPadding:
                          settings.overviewFrequency == OverviewFrequency.weekly
                          ? 4
                          : 16,
                      trailing: switch (settings.overviewFrequency) {
                        OverviewFrequency.weekly => ChoiceMenuButton<int>(
                          tooltip: 'Choose overview day',
                          value: settings.overviewWeekday,
                          choices: weekdayNames,
                          onChanged: (weekday) => update(
                            (s) => s.copyWith(overviewWeekday: weekday),
                          ),
                        ),
                        OverviewFrequency.monthly => Text(
                          '1st of each month',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      },
                    ),
                  ],
                ),
              ],
            ),
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

  /// Saves [newSettings], with [kind] turned on or off. Turning one on asks
  /// for permission to show notifications, if it hasn't been given yet.
  Future<void> _turnOn(
    _NotificationKind kind,
    bool enabled,
    AppSettings newSettings,
  ) async {
    await context.read<SettingsController>().update(newSettings);
    if (!enabled) {
      setState(() => _blocked.remove(kind));
      return;
    }
    if (!mounted) return;
    final allowed = await requestNotificationPermission(context);
    if (mounted) {
      setState(() => allowed ? _blocked.remove(kind) : _blocked.add(kind));
    }
  }
}

/// A kind of notification that can be turned off: a switch, with its
/// settings below. The settings fold away while it's off.
class _SwitchedSection extends StatelessWidget {
  const _SwitchedSection({
    required this.title,
    required this.enabled,
    required this.blocked,
    required this.onChanged,
    required this.children,
  });

  final String title;
  final bool enabled;

  /// Whether to explain that notifications are blocked, below the switch.
  final bool blocked;
  final ValueChanged<bool> onChanged;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          title: Text(title),
          value: enabled,
          onChanged: onChanged,
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: enabled
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (blocked) const NotificationsBlockedNotice(),
                    for (final child in children) ...[
                      const Divider(height: 1),
                      child,
                    ],
                  ],
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// A setting under a kind of notification: its [label], set in a little from
/// the kind's title above to show it belongs to it, and its value on the
/// right.
class _SubRow extends StatelessWidget {
  const _SubRow({
    required this.label,
    required this.trailing,
    this.endPadding = 4,
  });

  final String label;
  final Widget trailing;

  /// Space after [trailing]. Menus bring their own, so need less.
  final double endPadding;

  /// Twice a [ListTile]'s usual 16 pixel indent.
  static const _indent = 32.0;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: formRowHeight),
      child: Padding(
        padding: EdgeInsets.only(left: _indent, right: endPadding),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}

/// When a kind of notification arrives, read as one phrase: "Receive at
/// 9:00 AM every day". Tapping the time opens a time picker, and tapping
/// the repeat opens a menu of [repeatChoices].
class _ReceiveAtRow<T> extends StatelessWidget {
  const _ReceiveAtRow({
    super.key,
    required this.hour,
    required this.minute,
    required this.onTimeChanged,
    required this.repeat,
    required this.repeatChoices,
    required this.onRepeatChanged,
  });

  final int hour;
  final int minute;
  final ValueChanged<TimeOfDay> onTimeChanged;
  final T repeat;
  final Map<T, String> repeatChoices;
  final ValueChanged<T> onRepeatChanged;

  @override
  Widget build(BuildContext context) {
    final time = TimeOfDay(hour: hour, minute: minute);
    return _SubRow(
      label: 'Receive at',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: 'Change time',
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: time,
                );
                if (picked != null) onTimeChanged(picked);
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 4, 12),
                child: Text(
                  time.format(context),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ),
          ),
          ChoiceMenuButton<T>(
            tooltip: 'Choose how often',
            value: repeat,
            choices: repeatChoices,
            onChanged: onRepeatChanged,
          ),
        ],
      ),
    );
  }
}
