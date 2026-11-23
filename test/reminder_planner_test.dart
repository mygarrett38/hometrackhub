import 'package:flutter_test/flutter_test.dart';
import 'package:hometrackhub/models/app_settings.dart';
import 'package:hometrackhub/models/home_item.dart';
import 'package:hometrackhub/models/home_item_category.dart';
import 'package:hometrackhub/models/maintenance_interval.dart';
import 'package:hometrackhub/models/maintenance_task.dart';
import 'package:hometrackhub/models/task_reminder.dart';
import 'package:hometrackhub/services/reminder_planner.dart';

/// Creates a home item with one monthly task that is next due on [dueDate].
HomeItem homeItemDueOn(
  DateTime dueDate, {
  String name = 'Furnace',
  String taskTitle = 'Replace filter',
  TaskReminder reminder = const TaskReminder(),
}) {
  return HomeItem(
    id: name,
    name: name,
    category: HomeItemCategory.hvac,
    tasks: [
      MaintenanceTask(
        id: taskTitle,
        title: taskTitle,
        interval: const MaintenanceInterval.months(1),
        // One month before the due date, so nextDueDate == dueDate.
        startDate: DateTime(dueDate.year, dueDate.month - 1, dueDate.day),
        reminder: reminder,
      ),
    ],
  );
}

/// The one task of [homeItemDueOn].
MaintenanceTask taskDueOn(
  DateTime dueDate, {
  TaskReminder reminder = const TaskReminder(),
}) => homeItemDueOn(dueDate, reminder: reminder).tasks.single;

void main() {
  // Wednesday, June 10, 2026 at noon.
  final now = DateTime(2026, 6, 10, 12, 0);
  // Each kind of notification at its own time, so they're easy to tell
  // apart: upcoming at 9:30 and overdue at 6:00 PM.
  const settings = AppSettings(
    upcomingHour: 9,
    upcomingMinute: 30,
    overdueHour: 18,
    overdueMinute: 0,
  );
  final upcomingOnly = settings.copyWith(overdueEnabled: false);

  /// When [task] should be notified about, without the kinds.
  Iterable<DateTime> timesFor(MaintenanceTask task, AppSettings settings) =>
      taskReminderTimes(task, settings, now).map((moment) => moment.time);

  group('when tasks are notified about', () {
    test('upcoming tasks start on the task\'s day and repeat until due', () {
      final times = taskReminderTimes(
        taskDueOn(
          DateTime(2026, 6, 20),
          reminder: const TaskReminder(daysBefore: 7),
        ),
        upcomingOnly.copyWith(upcomingReminderDays: 3),
        now,
      );

      // 7, 4 and 1 days before, then on the due date.
      expect(times.map((moment) => moment.time), [
        DateTime(2026, 6, 13, 9, 30),
        DateTime(2026, 6, 16, 9, 30),
        DateTime(2026, 6, 19, 9, 30),
        DateTime(2026, 6, 20, 9, 30),
      ]);
      expect(
        times.map((moment) => moment.kind),
        everyElement(ReminderKind.upcoming),
      );
    });

    test('times that have already passed are skipped', () {
      // Starting a week early would have been June 5; 9:30 today has
      // passed too.
      final times = timesFor(
        taskDueOn(
          DateTime(2026, 6, 12),
          reminder: const TaskReminder(daysBefore: 7),
        ),
        upcomingOnly,
      );

      expect(times, [
        DateTime(2026, 6, 11, 9, 30),
        DateTime(2026, 6, 12, 9, 30),
      ]);
    });

    test('overdue tasks start the day after the due date', () {
      final times = taskReminderTimes(
        taskDueOn(DateTime(2026, 6, 20)),
        settings,
        now,
      ).take(3);

      expect(times, [
        (time: DateTime(2026, 6, 20, 9, 30), kind: ReminderKind.upcoming),
        (time: DateTime(2026, 6, 21, 18), kind: ReminderKind.overdue),
        (time: DateTime(2026, 6, 22, 18), kind: ReminderKind.overdue),
      ]);
    });

    test('overdue tasks repeat as often as the settings say', () {
      // Due June 1. Every 3 days from June 2: June 5, 8, 11, 14.
      final times = timesFor(
        taskDueOn(DateTime(2026, 6, 1)),
        settings.copyWith(overdueReminderDays: 3),
      );

      expect(times.take(2), [
        DateTime(2026, 6, 11, 18),
        DateTime(2026, 6, 14, 18),
      ]);
    });

    test('an overdue repeat later today is kept', () {
      final times = timesFor(taskDueOn(DateTime(2026, 6, 1)), settings);

      expect(times.first, DateTime(2026, 6, 10, 18));
    });

    test('overdue tasks aren\'t notified about when that\'s turned off', () {
      final times = timesFor(
        taskDueOn(DateTime(2026, 6, 1)),
        settings.copyWith(overdueEnabled: false),
      );

      expect(times, isEmpty);
    });

    test('tasks with their reminder off aren\'t notified about', () {
      final reminders = planReminders(
        homeItems: [
          homeItemDueOn(
            DateTime(2026, 6, 20),
            reminder: const TaskReminder.off(),
          ),
        ],
        settings: settings,
        now: now,
      );

      expect(reminders, isEmpty);
    });
  });

  group('notifications', () {
    test('list every upcoming task due a reminder at the same time', () {
      final reminders = planReminders(
        homeItems: [
          homeItemDueOn(DateTime(2026, 6, 20), name: 'Furnace'),
          homeItemDueOn(DateTime(2026, 6, 20), name: 'Dryer'),
        ],
        settings: upcomingOnly,
        now: now,
      );

      final reminder = reminders.single;
      expect(reminder.time, DateTime(2026, 6, 20, 9, 30));
      expect(reminder.kind, ReminderKind.upcoming);
      expect(reminder.title, 'You have 2 upcoming tasks');
      // Each home item, then its tasks with when they're due first.
      expect(
        reminder.body,
        'Dryer\n'
        'Due today – Replace filter\n'
        '\n'
        'Furnace\n'
        'Due today – Replace filter',
      );
    });

    test('list each home item\'s tasks together, under its name', () {
      final reminders = planReminders(
        homeItems: [
          HomeItem(
            id: 'furnace',
            name: 'Furnace',
            category: HomeItemCategory.hvac,
            tasks: [
              taskDueOn(DateTime(2026, 6, 20)),
              MaintenanceTask(
                id: 'coils',
                title: 'Clean coils',
                interval: const MaintenanceInterval.months(1),
                startDate: DateTime(2026, 5, 20),
              ),
            ],
          ),
          homeItemDueOn(DateTime(2026, 6, 20), name: 'Dryer'),
        ],
        settings: upcomingOnly,
        now: now,
      );

      expect(reminders.single.title, 'You have 3 upcoming tasks');
      expect(
        reminders.single.body,
        'Dryer\n'
        'Due today – Replace filter\n'
        '\n'
        'Furnace\n'
        'Due today – Clean coils\n'
        'Due today – Replace filter',
      );
    });

    test('include tasks notified about early, soonest due first', () {
      final reminders = planReminders(
        homeItems: [
          // Reminded every day from June 13.
          homeItemDueOn(
            DateTime(2026, 6, 20),
            name: 'Furnace',
            reminder: const TaskReminder(daysBefore: 7),
          ),
          homeItemDueOn(DateTime(2026, 6, 15), name: 'Dryer'),
        ],
        settings: upcomingOnly,
        now: now,
      );

      final june15 = reminders.singleWhere(
        (reminder) => reminder.time == DateTime(2026, 6, 15, 9, 30),
      );
      expect(
        june15.body,
        'Dryer\n'
        'Due today – Replace filter\n'
        '\n'
        'Furnace\n'
        'Due in 5 days – Replace filter',
      );
    });

    test('list overdue tasks in their own notification, at their own time', () {
      final reminders = planReminders(
        homeItems: [
          homeItemDueOn(DateTime(2026, 6, 1), name: 'Furnace'),
          homeItemDueOn(DateTime(2026, 6, 5), name: 'Dryer'),
        ],
        settings: settings,
        now: now,
      );

      final first = reminders.first;
      expect(first.time, DateTime(2026, 6, 10, 18));
      expect(first.kind, ReminderKind.overdue);
      expect(first.title, 'You have 2 overdue tasks');
      expect(
        first.body,
        'Furnace\n'
        'Overdue by 9 days – Replace filter\n'
        '\n'
        'Dryer\n'
        'Overdue by 5 days – Replace filter',
      );
    });

    test('for overdue tasks come before ones for upcoming tasks sent at the '
        'same time', () {
      final reminders = planReminders(
        homeItems: [
          homeItemDueOn(DateTime(2026, 6, 1), name: 'Furnace'),
          homeItemDueOn(DateTime(2026, 6, 11), name: 'Dryer'),
        ],
        settings: settings.copyWith(overdueHour: 9, overdueMinute: 30),
        now: now,
      );

      final june11 = [
        for (final reminder in reminders)
          if (reminder.time == DateTime(2026, 6, 11, 9, 30)) reminder,
      ];
      expect(june11.map((reminder) => reminder.kind), [
        ReminderKind.overdue,
        ReminderKind.upcoming,
      ]);
      expect(june11.first.body, isNot(contains('Dryer')));
      expect(june11.last.body, isNot(contains('Furnace')));
    });

    test('only say how many tasks there are when details are hidden', () {
      final reminders = planReminders(
        homeItems: [
          homeItemDueOn(DateTime(2026, 6, 1), name: 'Furnace'),
          homeItemDueOn(DateTime(2026, 6, 20), name: 'Furnace'),
          homeItemDueOn(DateTime(2026, 6, 20), name: 'Dryer'),
        ],
        settings: settings.copyWith(hideDetailsInNotifications: true),
        now: now,
      );

      final overdue = reminders.first;
      expect(overdue.title, 'You have 1 overdue task');
      expect(overdue.body, 'Tap to view.');
      final upcoming = reminders.firstWhere(
        (reminder) => reminder.kind == ReminderKind.upcoming,
      );
      expect(upcoming.title, 'You have 2 upcoming tasks');
      expect(upcoming.body, 'Tap to view.');
      for (final reminder in reminders) {
        expect(reminder.title, isNot(contains('Furnace')));
        expect(reminder.body, isNot(contains('Furnace')));
      }
    });

    test('are planned $daysPlannedAhead days ahead', () {
      // Due June 1 and overdue every week from June 2: June 16 to August 4.
      final reminders = planReminders(
        homeItems: [homeItemDueOn(DateTime(2026, 6, 1))],
        settings: settings.copyWith(overdueReminderDays: 7),
        now: now,
      );

      expect(reminders, hasLength(8));
      expect(reminders.first.time, DateTime(2026, 6, 16, 18));
      expect(reminders.last.time, DateTime(2026, 8, 4, 18));
    });

    test('never number more than the platform limit', () {
      final homeItems = [
        for (var day = 0; day < maxScheduledReminders; day++)
          homeItemDueOn(
            DateTime(2026, 7, 1).add(Duration(days: day)),
            name: 'Item $day',
          ),
      ];

      final reminders = planReminders(
        homeItems: homeItems,
        settings: settings,
        now: now,
      );

      expect(reminders, hasLength(maxScheduledReminders));
      // The soonest reminders are the ones kept, numbered in order.
      expect(reminders.first.time, DateTime(2026, 7, 1, 9, 30));
      expect(reminders.map((reminder) => reminder.id), [
        for (var id = 0; id < maxScheduledReminders; id++) id,
      ]);
    });
  });
}
