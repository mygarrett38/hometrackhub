import 'package:flutter/foundation.dart';

import '../models/app_settings.dart';
import '../models/home_item.dart';
import '../models/home_item_task.dart';
import '../utils/date_utils.dart';

/// iOS keeps at most 64 pending notifications per app, so the planner never
/// asks for more than this. Reminders are rebuilt every time the app's data
/// changes or the app starts, so later reminders get scheduled over time.
const int maxScheduledReminders = 60;

/// A notification that should be shown at a specific time.
@immutable
class PlannedReminder {
  const PlannedReminder({
    required this.id,
    required this.time,
    required this.title,
    required this.body,
  });

  final int id;
  final DateTime time;
  final String title;
  final String body;
}

/// Works out which maintenance reminders to schedule.
///
/// Each task gets one reminder at the user's chosen time of day, a number of
/// days before the task is due (see [AppSettings.reminderDaysBefore]). Tasks
/// whose reminder time has already passed, including overdue tasks, are
/// reminded at the next available reminder time. Tasks reminded at the same
/// moment are combined into one notification.
List<PlannedReminder> planReminders({
  required List<HomeItem> homeItems,
  required AppSettings settings,
  required DateTime now,
}) {
  if (!settings.notificationsEnabled) return [];

  // Group tasks by the moment their reminder should appear.
  final tasksByTime = <DateTime, List<HomeItemTask>>{};
  for (final item in homeItems) {
    for (final task in item.tasks) {
      if (!task.remindersEnabled) continue;
      final time = _reminderTimeFor(task.nextDueDate, settings, now);
      tasksByTime.putIfAbsent(time, () => []).add(HomeItemTask(item, task));
    }
  }

  final times = tasksByTime.keys.toList()..sort();
  final reminders = <PlannedReminder>[];
  for (final time in times.take(maxScheduledReminders)) {
    final tasks = tasksByTime[time]!
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    reminders.add(
      _buildReminder(
        id: reminders.length,
        time: time,
        tasks: tasks,
        hideDetails: settings.hideDetailsInNotifications,
      ),
    );
  }
  return reminders;
}

DateTime _reminderTimeFor(
  DateTime dueDate,
  AppSettings settings,
  DateTime now,
) {
  final reminderDay = dueDate.subtract(
    Duration(days: settings.reminderDaysBefore),
  );
  final idealTime = _atReminderTime(reminderDay, settings);
  if (idealTime.isAfter(now)) return idealTime;

  // The ideal time has passed, so use the next reminder time from now.
  final todayAtReminderTime = _atReminderTime(now, settings);
  if (todayAtReminderTime.isAfter(now)) return todayAtReminderTime;
  return _atReminderTime(now.add(const Duration(days: 1)), settings);
}

DateTime _atReminderTime(DateTime day, AppSettings settings) {
  return DateTime(
    day.year,
    day.month,
    day.day,
    settings.reminderHour,
    settings.reminderMinute,
  );
}

PlannedReminder _buildReminder({
  required int id,
  required DateTime time,
  required List<HomeItemTask> tasks,
  required bool hideDetails,
}) {
  if (hideDetails) {
    return PlannedReminder(
      id: id,
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
      id: id,
      time: time,
      title: '${item.homeItem.name}: ${item.task.title}',
      body: 'This maintenance task is $due.',
    );
  }

  final lines = [
    for (final item in tasks)
      '${item.task.title} (${item.homeItem.name}) - '
          '${describeDueDate(item.dueDate, time).toLowerCase()}',
  ];
  return PlannedReminder(
    id: id,
    time: time,
    title: '${tasks.length} maintenance tasks need attention',
    body: lines.join('\n'),
  );
}
