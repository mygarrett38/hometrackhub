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

/// How many days ahead notifications are planned. Planning a while ahead
/// means they keep arriving even if the app isn't opened for some time.
const int daysPlannedAhead = 60;

/// The two kinds of notification the app sends, each listing the tasks it's
/// about.
enum ReminderKind {
  /// Tasks coming up: from the day each task's reminder picks (see
  /// [TaskReminder.daysBefore]) through its due date.
  upcoming,

  /// Tasks past their due date.
  overdue,
}

/// A notification that should be shown at a specific time.
@immutable
class PlannedReminder {
  const PlannedReminder({
    required this.id,
    required this.time,
    required this.title,
    required this.body,
    required this.kind,
  });

  final int id;
  final DateTime time;
  final String title;
  final String body;

  /// Which tasks the notification is about, so tapping it can show them.
  final ReminderKind kind;
}

/// One time a task should be notified about, and whether it'll be upcoming
/// or overdue then.
typedef TaskReminderTime = ({DateTime time, ReminderKind kind});

/// Works out which notifications to schedule.
///
/// Each task with its reminder turned on is notified about before it's due
/// and, if those are turned on, once it's overdue (see [taskReminderTimes]).
/// Tasks aren't notified about one at a time: all the upcoming tasks due a
/// reminder at the same moment share one notification listing them, and so
/// do the overdue ones.
List<PlannedReminder> planReminders({
  required List<HomeItem> homeItems,
  required AppSettings settings,
  required DateTime now,
}) {
  final until = DateTime(now.year, now.month, now.day + daysPlannedAhead);
  final tasks = [
    for (final item in homeItems)
      for (final task in item.tasks)
        if (task.reminder.enabled) HomeItemTask(item, task),
  ]..sort(_byDueDate);

  // The tasks to list at each moment, in order of their due dates.
  final tasksByMoment = <TaskReminderTime, List<HomeItemTask>>{};
  for (final item in tasks) {
    for (final moment in taskReminderTimes(item.task, settings, now)) {
      // The times come soonest first.
      if (moment.time.isAfter(until)) break;
      tasksByMoment.putIfAbsent(moment, () => []).add(item);
    }
  }

  // Soonest first. Overdue tasks come before upcoming ones sent at the same
  // time, since they're more pressing.
  final moments = tasksByMoment.keys.toList()
    ..sort((a, b) {
      final byTime = a.time.compareTo(b.time);
      return byTime != 0 ? byTime : b.kind.index.compareTo(a.kind.index);
    });

  // Keep the soonest notifications and number them in order.
  return [
    for (final (index, moment) in moments.take(maxScheduledReminders).indexed)
      _reminder(
        id: index,
        moment: moment,
        tasks: tasksByMoment[moment]!,
        hideDetails: settings.hideDetailsInNotifications,
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

/// When [task] should be notified about after [now], soonest first.
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
Iterable<TaskReminderTime> taskReminderTimes(
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
    if (time.isAfter(now)) yield (time: time, kind: ReminderKind.upcoming);
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
      if (time.isAfter(now)) yield (time: time, kind: ReminderKind.overdue);
      days += every;
    }
  }
}

/// The notification listing [tasks], which are all upcoming or all overdue
/// at [moment].
///
/// With [hideDetails], it only says how many there are, since notifications
/// can appear on a locked screen.
PlannedReminder _reminder({
  required int id,
  required TaskReminderTime moment,
  required List<HomeItemTask> tasks,
  required bool hideDetails,
}) {
  final (title, kindOfTask) = switch (moment.kind) {
    ReminderKind.upcoming => ('Upcoming maintenance', 'upcoming'),
    ReminderKind.overdue => ('Overdue maintenance', 'overdue'),
  };
  final count = tasks.length;
  return PlannedReminder(
    id: id,
    time: moment.time,
    kind: moment.kind,
    title: title,
    body: hideDetails
        ? 'You have $count $kindOfTask maintenance '
              '${count == 1 ? 'task' : 'tasks'}. Tap to view.'
        : _taskLines(tasks, moment.time),
  );
}

/// One line per task, such as "Replace filter (Furnace) – due in 3 days",
/// as of [time].
String _taskLines(List<HomeItemTask> tasks, DateTime time) {
  return [
    for (final item in tasks)
      '${item.task.title} (${item.homeItem.name}) – '
          '${describeDueDate(item.dueDate, time).toLowerCase()}',
  ].join('\n');
}
