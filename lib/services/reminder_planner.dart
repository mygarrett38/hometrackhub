import 'package:flutter/foundation.dart';

import '../models/app_settings.dart';
import '../models/home_item.dart';
import '../models/home_item_task.dart';
import '../models/maintenance_task.dart';
import '../utils/date_utils.dart';

/// iOS keeps at most 64 pending notifications per app, so the planner never
/// asks for more than this. Reminders are rebuilt every time the app's data
/// changes or the app starts, so later reminders get scheduled over time.
const int maxScheduledReminders = 60;

/// How many upcoming overview notifications are scheduled ahead of time.
/// Scheduling a few means overviews keep arriving even if the app isn't
/// opened for a while.
const int overviewsScheduledAhead = 3;

/// The two kinds of notification the app sends.
enum ReminderKind {
  /// A reminder about one or more specific tasks.
  task,

  /// A weekly or monthly summary of upcoming maintenance.
  overview,
}

/// A notification that should be shown at a specific time.
@immutable
class PlannedReminder {
  const PlannedReminder({
    required this.id,
    required this.time,
    required this.title,
    required this.body,
    this.kind = ReminderKind.task,
  });

  final int id;
  final DateTime time;
  final String title;
  final String body;
  final ReminderKind kind;
}

/// Works out which notifications to schedule.
///
/// Every task with its reminder turned on gets one reminder, using the
/// task's own schedule (see [MaintenanceTask.reminder]). Reminders at the same
/// moment are combined into one notification.
///
/// If the user opted in, overview notifications summarizing the coming week
/// or month are added as well (see [AppSettings.overviewFrequency]).
List<PlannedReminder> planReminders({
  required List<HomeItem> homeItems,
  required AppSettings settings,
  required DateTime now,
}) {
  final hideDetails = settings.hideDetailsInNotifications;

  // Group task reminders by the moment they should appear.
  final tasksByTime = <DateTime, List<HomeItemTask>>{};
  for (final item in homeItems) {
    for (final task in item.tasks) {
      if (!task.reminder.enabled) continue;
      final time = nextReminderTime(task, now);
      tasksByTime.putIfAbsent(time, () => []).add(HomeItemTask(item, task));
    }
  }

  final unnumbered = <PlannedReminder>[
    for (final MapEntry(key: time, value: tasks) in tasksByTime.entries)
      _taskReminder(time: time, tasks: tasks, hideDetails: hideDetails),
    ..._overviews(homeItems: homeItems, settings: settings, now: now),
  ]..sort((a, b) => a.time.compareTo(b.time));

  // Keep the soonest notifications and number them in order.
  return [
    for (final (index, reminder)
        in unnumbered.take(maxScheduledReminders).indexed)
      PlannedReminder(
        id: index,
        time: reminder.time,
        title: reminder.title,
        body: reminder.body,
        kind: reminder.kind,
      ),
  ];
}

/// When the reminder for [task] will next appear.
///
/// This is normally the time set on the task's reminder. If that time has
/// already passed, for example because the task is overdue, the reminder is
/// sent at the reminder's time of day today, or tomorrow if that has passed
/// too.
DateTime nextReminderTime(MaintenanceTask task, DateTime now) {
  final reminder = task.reminder;
  final idealTime = reminder.timeFor(task.nextDueDate);
  if (idealTime.isAfter(now)) return idealTime;

  final today = DateTime(
    now.year,
    now.month,
    now.day,
    reminder.hour,
    reminder.minute,
  );
  if (today.isAfter(now)) return today;
  return DateTime(
    now.year,
    now.month,
    now.day + 1,
    reminder.hour,
    reminder.minute,
  );
}

/// One line per task, such as "Replace filter (Furnace) - due in 3 days".
String _taskLines(List<HomeItemTask> tasks, DateTime time) {
  return [
    for (final item in tasks)
      '${item.task.title} (${item.homeItem.name}) - '
          '${describeDueDate(item.dueDate, time).toLowerCase()}',
  ].join('\n');
}

PlannedReminder _taskReminder({
  required DateTime time,
  required List<HomeItemTask> tasks,
  required bool hideDetails,
}) {
  tasks.sort((a, b) => a.dueDate.compareTo(b.dueDate));

  if (hideDetails) {
    return PlannedReminder(
      id: 0,
      time: time,
      title: 'Home maintenance reminder',
      body: tasks.length == 1
          ? 'You have a maintenance task due.'
          : 'You have ${tasks.length} maintenance tasks due.',
    );
  }

  if (tasks.length == 1) {
    final item = tasks.single;
    final due = describeDueDate(item.dueDate, time).toLowerCase();
    return PlannedReminder(
      id: 0,
      time: time,
      title: '${item.homeItem.name}: ${item.task.title}',
      body: 'This maintenance task is $due.',
    );
  }

  return PlannedReminder(
    id: 0,
    time: time,
    title: '${tasks.length} maintenance tasks need attention',
    body: _taskLines(tasks, time),
  );
}

/// The next few overview notifications, or none if the user hasn't opted in.
///
/// Each overview lists every task due before the next overview, plus any
/// overdue tasks, whether or not those tasks have their own reminders turned
/// on. Overviews with nothing to report are skipped.
List<PlannedReminder> _overviews({
  required List<HomeItem> homeItems,
  required AppSettings settings,
  required DateTime now,
}) {
  final frequency = settings.overviewFrequency;
  if (frequency == OverviewFrequency.off) return [];

  final allTasks = [
    for (final item in homeItems)
      for (final task in item.tasks) HomeItemTask(item, task),
  ]..sort((a, b) => a.dueDate.compareTo(b.dueDate));

  final overviews = <PlannedReminder>[];
  var time = _firstOverviewTime(settings, now);
  for (var i = 0; i < overviewsScheduledAhead; i++) {
    final periodEnd = _nextOverviewTime(time, frequency);
    final tasks = [
      for (final item in allTasks)
        if (calendarDaysBetween(item.dueDate, periodEnd) > 0) item,
    ];
    if (tasks.isNotEmpty) {
      overviews.add(
        _overview(
          time: time,
          frequency: frequency,
          tasks: tasks,
          hideDetails: settings.hideDetailsInNotifications,
        ),
      );
    }
    time = periodEnd;
  }
  return overviews;
}

/// The first overview time after [now]: the chosen weekday for weekly
/// overviews, or the 1st of the month for monthly ones.
DateTime _firstOverviewTime(AppSettings settings, DateTime now) {
  DateTime atOverviewTime(int year, int month, int day) => DateTime(
    year,
    month,
    day,
    settings.overviewHour,
    settings.overviewMinute,
  );

  switch (settings.overviewFrequency) {
    case OverviewFrequency.weekly:
      final daysAhead = (settings.overviewWeekday - now.weekday) % 7;
      final candidate = atOverviewTime(
        now.year,
        now.month,
        now.day + daysAhead,
      );
      return candidate.isAfter(now)
          ? candidate
          : _nextOverviewTime(candidate, OverviewFrequency.weekly);
    case OverviewFrequency.monthly:
    case OverviewFrequency.off:
      final candidate = atOverviewTime(now.year, now.month, 1);
      return candidate.isAfter(now)
          ? candidate
          : _nextOverviewTime(candidate, OverviewFrequency.monthly);
  }
}

/// The overview that follows the one sent at [time].
DateTime _nextOverviewTime(DateTime time, OverviewFrequency frequency) {
  return switch (frequency) {
    OverviewFrequency.weekly => DateTime(
      time.year,
      time.month,
      time.day + 7,
      time.hour,
      time.minute,
    ),
    _ => DateTime(time.year, time.month + 1, 1, time.hour, time.minute),
  };
}

PlannedReminder _overview({
  required DateTime time,
  required OverviewFrequency frequency,
  required List<HomeItemTask> tasks,
  required bool hideDetails,
}) {
  final period = frequency == OverviewFrequency.weekly
      ? 'this week'
      : 'this month';
  final count = tasks.length == 1
      ? '1 maintenance task'
      : '${tasks.length} maintenance tasks';

  return PlannedReminder(
    id: 0,
    time: time,
    kind: ReminderKind.overview,
    title: 'Home maintenance $period',
    body: hideDetails
        ? 'You have $count to do $period.'
        : '$count to do $period:\n${_taskLines(tasks, time)}',
  );
}
