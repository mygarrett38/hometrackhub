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

/// How many of each task's notifications are scheduled ahead of time.
/// Scheduling a few means they keep arriving even if the app isn't opened
/// for a while.
const int taskRemindersScheduledAhead = 3;

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
/// Each task with its reminder turned on gets its own notifications: before
/// it's due and once it's overdue, if those are turned on (see
/// [taskReminderTimes]). Each kind of notification arrives at its own time
/// of day, so notifications of the same kind come together, one per task.
///
/// If the user opted in, overview notifications summarizing the coming week
/// or month are added as well (see [AppSettings.overviewEnabled]).
List<PlannedReminder> planReminders({
  required List<HomeItem> homeItems,
  required AppSettings settings,
  required DateTime now,
}) {
  final tasks = [
    for (final item in homeItems)
      for (final task in item.tasks)
        if (task.reminder.enabled) HomeItemTask(item, task),
  ]..sort(_byDueDate);

  // Overviews come before task reminders sent at the same time, and those
  // keep the order of their due dates. Dart's sort isn't stable, so each
  // notification's place in this list breaks ties.
  final unnumbered =
      [
        ..._overviews(homeItems: homeItems, settings: settings, now: now),
        for (final item in tasks)
          for (final time in taskReminderTimes(
            item.task,
            settings,
            now,
          ).take(taskRemindersScheduledAhead))
            _taskReminder(
              time: time,
              item: item,
              hideDetails: settings.hideDetailsInNotifications,
            ),
      ].indexed.toList()..sort((a, b) {
        final byTime = a.$2.time.compareTo(b.$2.time);
        return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
      });

  // Keep the soonest notifications and number them in order.
  return [
    for (final (index, (_, reminder))
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

/// Soonest due first, then by home item name and task title.
int _byDueDate(HomeItemTask a, HomeItemTask b) {
  final byDate = a.dueDate.compareTo(b.dueDate);
  if (byDate != 0) return byDate;
  final byName = a.homeItem.name.compareTo(b.homeItem.name);
  return byName != 0 ? byName : a.task.title.compareTo(b.task.title);
}

/// When [task]'s notifications will appear after [now], soonest first.
///
/// Upcoming notifications start on the day the task's reminder picks (see
/// [TaskReminder.daysBefore]) and repeat every
/// [AppSettings.upcomingReminderDays] days before the due date, with one on
/// the due date itself. Overdue notifications start the day after the due
/// date and repeat every [AppSettings.overdueReminderDays] days for as long
/// as the task stays overdue, so this never ends when they're turned on.
///
/// Counting from the due date keeps the repeats on the same days however
/// often the app is opened.
Iterable<DateTime> taskReminderTimes(
  MaintenanceTask task,
  AppSettings settings,
  DateTime now,
) sync* {
  if (!task.reminder.enabled) return;
  final due = task.nextDueDate;
  DateTime daysFromDue(int days, int hour, int minute) =>
      DateTime(due.year, due.month, due.day + days, hour, minute);

  final everyUpcoming = settings.upcomingReminderDays;
  for (final days in {
    for (var days = -task.reminder.daysBefore; days < 0; days += everyUpcoming)
      days,
    0,
  }) {
    final time = daysFromDue(
      days,
      settings.upcomingHour,
      settings.upcomingMinute,
    );
    if (time.isAfter(now)) yield time;
  }

  if (settings.overdueEnabled) {
    final every = settings.overdueReminderDays;
    // Skip ahead to the latest repeat on or before today.
    final daysOverdue = calendarDaysBetween(due, now);
    var days = daysOverdue <= 1 ? 1 : daysOverdue - (daysOverdue - 1) % every;
    while (true) {
      final time = daysFromDue(
        days,
        settings.overdueHour,
        settings.overdueMinute,
      );
      if (time.isAfter(now)) yield time;
      days += every;
    }
  }
}

/// One line per task, such as "Replace filter (Furnace) - due in 3 days".
String _taskLines(List<HomeItemTask> tasks, DateTime time) {
  return [
    for (final item in tasks)
      '${item.task.title} (${item.homeItem.name}) - '
          '${describeDueDate(item.dueDate, time).toLowerCase()}',
  ].join('\n');
}

/// The notification for one task.
PlannedReminder _taskReminder({
  required DateTime time,
  required HomeItemTask item,
  required bool hideDetails,
}) {
  if (hideDetails) {
    return PlannedReminder(
      id: 0,
      time: time,
      title: 'Home maintenance reminder',
      body: 'You have a maintenance task due.',
    );
  }

  final due = describeDueDate(item.dueDate, time).toLowerCase();
  return PlannedReminder(
    id: 0,
    time: time,
    title: '${item.homeItem.name}: ${item.task.title}',
    body: 'This maintenance task is $due.',
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
  if (!settings.overviewEnabled) return [];
  final frequency = settings.overviewFrequency;

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
