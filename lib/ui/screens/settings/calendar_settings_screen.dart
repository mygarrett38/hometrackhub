import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/calendar_service.dart';
import '../../../state/settings_controller.dart';
import '../../widgets/section_header.dart';

/// Lets the user add their maintenance tasks to a calendar on the device and
/// choose which calendar they go in.
class CalendarSettingsScreen extends StatefulWidget {
  const CalendarSettingsScreen({super.key});

  @override
  State<CalendarSettingsScreen> createState() => _CalendarSettingsScreenState();
}

class _CalendarSettingsScreenState extends State<CalendarSettingsScreen>
    with WidgetsBindingObserver {
  /// Whether the app may use the device's calendars, or `null` while
  /// checking.
  bool? _hasAccess;

  /// Calendars tasks can be added to, or `null` before they are loaded.
  List<UserCalendar>? _calendars;

  /// True while turning calendar sync on, which may wait on a permission
  /// prompt.
  bool _isTurningOn = false;

  /// Why calendar sync couldn't be turned on, shown under the switch.
  _TurnOnProblem? _problem;

  CalendarService get _service => context.read<CalendarService>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The user may have allowed or taken away calendar access in the device
    // settings, or added a calendar in another app.
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final service = _service;
    var hasAccess = false;
    List<UserCalendar> calendars = const [];
    try {
      hasAccess = await service.hasAccess();
      if (hasAccess) calendars = await service.listWritableCalendars();
    } catch (error) {
      debugPrint('Could not load calendars: $error');
    }
    if (!mounted) return;
    setState(() {
      _hasAccess = hasAccess;
      _calendars = calendars;
      // Drop a problem the user has since fixed, such as by allowing access
      // in the device settings.
      if ((_problem == _TurnOnProblem.noAccess && hasAccess) ||
          (_problem == _TurnOnProblem.noCalendars && calendars.isNotEmpty)) {
        _problem = null;
      }
    });
  }

  Future<void> _turnOn() async {
    final service = _service;
    final controller = context.read<SettingsController>();
    setState(() {
      _isTurningOn = true;
      _problem = null;
    });
    try {
      if (!await service.requestAccess()) {
        if (mounted) setState(() => _problem = _TurnOnProblem.noAccess);
        return;
      }
      final calendars = await service.listWritableCalendars();
      if (!mounted) return;
      setState(() {
        _hasAccess = true;
        _calendars = calendars;
      });
      if (calendars.isEmpty) {
        setState(() => _problem = _TurnOnProblem.noCalendars);
        return;
      }

      // Use the calendar chosen last time, or else the main one.
      final settings = controller.settings;
      final chosen =
          _findCalendar(calendars, settings.syncCalendarId) ??
          calendars.firstWhere(
            (calendar) => calendar.isPrimary,
            orElse: () => calendars.first,
          );
      await controller.update(
        settings.copyWith(
          calendarSyncEnabled: true,
          syncCalendarId: chosen.id,
          syncCalendarName: chosen.name,
        ),
      );
    } catch (error) {
      debugPrint('Could not turn on calendar sync: $error');
      if (mounted) setState(() => _problem = _TurnOnProblem.failed);
    } finally {
      if (mounted) setState(() => _isTurningOn = false);
    }
  }

  void _turnOff() {
    final controller = context.read<SettingsController>();
    controller.update(controller.settings.copyWith(calendarSyncEnabled: false));
  }

  void _choose(UserCalendar calendar) {
    final controller = context.read<SettingsController>();
    controller.update(
      controller.settings.copyWith(
        syncCalendarId: calendar.id,
        syncCalendarName: calendar.name,
      ),
    );
  }

  static UserCalendar? _findCalendar(List<UserCalendar> calendars, String? id) {
    for (final calendar in calendars) {
      if (calendar.id == id) return calendar;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>().settings;
    final enabled = settings.calendarSyncEnabled;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar sync'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Help',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const _CalendarSyncHelpDialog(),
            ),
          ),
        ],
      ),
      // Pulling down reloads the calendars, for one that was just added in
      // another app and has now synced to the phone.
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.event_outlined),
              title: const Text('Sync tasks with my calendar'),
              value: enabled,
              onChanged: _isTurningOn
                  ? null
                  : (turnOn) => turnOn ? _turnOn() : _turnOff(),
            ),
            if (!enabled && _problem != null) _problemRow(_problem!),
            if (enabled) ..._calendarChoices(settings.syncCalendarId),
          ],
        ),
      ),
    );
  }

  Widget _problemRow(_TurnOnProblem problem) {
    return ListTile(
      leading: Icon(
        Icons.warning_amber_rounded,
        color: Theme.of(context).colorScheme.error,
      ),
      title: Text(switch (problem) {
        _TurnOnProblem.noAccess =>
          'Allow calendar access in Settings to add tasks to your calendar.',
        _TurnOnProblem.noCalendars =>
          'There is no calendar on this device that tasks can be added to. '
              'Add an account in your calendar app, then try again.',
        _TurnOnProblem.failed => 'Could not open your calendars. Try again.',
      }),
      trailing: problem == _TurnOnProblem.noAccess
          ? TextButton(
              onPressed: _service.openAppSettings,
              child: const Text('Settings'),
            )
          : null,
    );
  }

  List<Widget> _calendarChoices(String? selectedId) {
    final calendars = _calendars;
    if (_hasAccess == null || calendars == null) {
      return const [
        Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_hasAccess == false) {
      return [
        ListTile(
          leading: Icon(
            Icons.warning_amber_rounded,
            color: Theme.of(context).colorScheme.error,
          ),
          title: const Text('Calendar access is off'),
          subtitle: const Text(
            'Tasks are not added or updated until you allow HomeTrackHub to '
            'use your calendar.',
          ),
          trailing: TextButton(
            onPressed: _service.openAppSettings,
            child: const Text('Settings'),
          ),
        ),
      ];
    }

    final colors = Theme.of(context).colorScheme;
    return [
      const SectionHeader('Calendar'),
      if (calendars.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'There is no calendar on this device that tasks can be added '
            'to. Add an account in your calendar app, then come back here.',
          ),
        )
      else ...[
        if (_findCalendar(calendars, selectedId) == null)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'The calendar you chose is hidden in your calendar app or no '
              'longer on this device. Choose another one.',
            ),
          ),
        RadioGroup<String>(
          groupValue: selectedId,
          onChanged: (id) {
            final calendar = _findCalendar(calendars, id);
            if (calendar != null) _choose(calendar);
          },
          child: Column(
            children: [
              for (final calendar in calendars)
                RadioListTile<String>(
                  value: calendar.id,
                  title: Text(calendar.name),
                  subtitle:
                      calendar.accountName == null ||
                          calendar.accountName == calendar.name
                      ? null
                      : Text(calendar.accountName!),
                  secondary: CircleAvatar(
                    radius: 8,
                    backgroundColor: calendar.color ?? colors.outline,
                  ),
                ),
            ],
          ),
        ),
      ],
      // A quiet tip rather than a main action, for people who don't want
      // tasks mixed in with their other events.
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Center(
          child: TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: colors.onSurfaceVariant,
              textStyle: Theme.of(context).textTheme.bodyMedium,
            ),
            icon: const Icon(Icons.lightbulb_outline, size: 18),
            label: const Text('Tip: Create a home maintenance calendar'),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const _SeparateCalendarDialog(),
            ),
          ),
        ),
      ),
    ];
  }
}

/// Why turning on calendar sync didn't work.
enum _TurnOnProblem {
  /// The user turned down calendar access.
  noAccess,

  /// The device has no calendar tasks can be added to.
  noCalendars,

  /// Something went wrong loading the calendars.
  failed,
}

/// Step-by-step instructions for making a calendar just for maintenance
/// tasks, so they don't fill up the user's other calendars.
class _SeparateCalendarDialog extends StatelessWidget {
  const _SeparateCalendarDialog();

  @override
  Widget build(BuildContext context) {
    final isIos = Theme.of(context).platform == TargetPlatform.iOS;
    final steps = [
      'On a PC, open calendar.google.com.',
      'Next to "Other calendars", click + and choose "Create new calendar".',
      'Name it whatever you\'d like - we recommend "Home Maintenance".',
      if (isIos)
        'Google only sends your main calendar to iPhones and iPads by '
            'default, so go to calendar.google.com/calendar/syncselect, '
            'select the calendar you just created and save.',
      'Refresh this list and choose your new calendar. Tasks are '
      'automatically transferred to it.',
    ];

    return AlertDialog(
      title: const Text('Tip: Creating a custom home maintenance calendar'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Give maintenance tasks a calendar of their own so they stay '
              'out of your personal or work calendar. Here\'s how to do it '
              'for Google Calendar:',
            ),
            for (final (index, step) in steps.indexed)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 24, child: Text('${index + 1}.')),
                    Expanded(child: Text(step)),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Got it'),
        ),
      ],
    );
  }
}

class _CalendarSyncHelpDialog extends StatelessWidget {
  const _CalendarSyncHelpDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Calendar Help'),
      content: const SingleChildScrollView(
        child: Text(
          'Each maintenance task is added to your calendar as an all-day '
          'event on its due date. Events move when you complete or change a '
          'task, and are removed when you delete it.\n\n'
          'Calendar events will not send you notifications by themselves '
          '(unless you set them), so we will still send you a notification '
          'based on your preferences for each task.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Got it'),
        ),
      ],
    );
  }
}
