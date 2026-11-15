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
  // apart: upcoming at 9:30, overdue at 6:00 PM and overviews at 8:00.
  const settings = AppSettings(
    upcomingHour: 9,
    upcomingMinute: 30,
    overdueHour: 18,
    overdueMinute: 0,
    overviewHour: 8,
    overviewMinute: 0,
  );
  final upcomingOnly = settings.copyWith(overdueEnabled: false);

  group('upcoming task notifications', () {
    test('are sent on the due date at the upcoming time', () {
      final reminders = planReminders(
        homeItems: [homeItemDueOn(DateTime(2026, 6, 20))],
        settings: upcomingOnly,
        now: now,
      );

      expect(reminders.single.time, DateTime(2026, 6, 20, 9, 30));
      expect(reminders.single.kind, ReminderKind.task);
      expect(reminders.single.title, 'Furnace: Replace filter');
      expect(reminders.single.body, contains('due today'));
    });

    test('start on the task\'s day and repeat until the due date', () {
      final times = taskReminderTimes(
        taskDueOn(
          DateTime(2026, 6, 20),
          reminder: const TaskReminder(daysBefore: 7),
        ),
        upcomingOnly.copyWith(upcomingReminderDays: 3),
        now,
      );

      // 7, 4 and 1 days before, then on the due date.
      expect(times, [
        DateTime(2026, 6, 13, 9, 30),
        DateTime(2026, 6, 16, 9, 30),
        DateTime(2026, 6, 19, 9, 30),
        DateTime(2026, 6, 20, 9, 30),
      ]);
    });

    test('skip days that have already passed', () {
      // Starting a week early would have been June 5; 9:30 today has
      // passed too.
      final times = taskReminderTimes(
        taskDueOn(
          DateTime(2026, 6, 12),
          reminder: const TaskReminder(daysBefore: 7),
        ),
        upcomingOnly,
        now,
      );

      expect(times, [
        DateTime(2026, 6, 11, 9, 30),
        DateTime(2026, 6, 12, 9, 30),
      ]);
    });

    test('for tasks due the same day are sent separately, together', () {
      final reminders = planReminders(
        homeItems: [
          homeItemDueOn(DateTime(2026, 6, 20), name: 'Furnace'),
          homeItemDueOn(DateTime(2026, 6, 20), name: 'Dryer'),
        ],
        settings: upcomingOnly,
        now: now,
      );

      expect(reminders.map((reminder) => reminder.title), [
        'Dryer: Replace filter',
        'Furnace: Replace filter',
      ]);
      expect(
        reminders.map((reminder) => reminder.time),
        everyElement(DateTime(2026, 6, 20, 9, 30)),
      );
    });
  });

  group('overdue task notifications', () {
    test('start the day after the due date, at the overdue time', () {
      final times = taskReminderTimes(
        taskDueOn(DateTime(2026, 6, 20)),
        settings,
        now,
      );

      expect(times.take(3), [
        DateTime(2026, 6, 20, 9, 30),
        DateTime(2026, 6, 21, 18),
        DateTime(2026, 6, 22, 18),
      ]);
    });

    test('repeat as often as the settings say', () {
      // Due June 1. Every 3 days from June 2: June 5, 8, 11, 14.
      final times = taskReminderTimes(
        taskDueOn(DateTime(2026, 6, 1)),
        settings.copyWith(overdueReminderDays: 3),
        now,
      );

      expect(times.take(2), [
        DateTime(2026, 6, 11, 18),
        DateTime(2026, 6, 14, 18),
      ]);
    });

    test('keep a repeat later today', () {
      final times = taskReminderTimes(
        taskDueOn(DateTime(2026, 6, 1)),
        settings,
        now,
      );

      expect(times.first, DateTime(2026, 6, 10, 18));
    });

    test('are not sent when turned off', () {
      final times = taskReminderTimes(
        taskDueOn(DateTime(2026, 6, 1)),
        settings.copyWith(overdueEnabled: false),
        now,
      );

      expect(times, isEmpty);
    });

    test('only the next few are scheduled for each task', () {
      final reminders = planReminders(
        homeItems: [homeItemDueOn(DateTime(2026, 6, 1))],
        settings: settings,
        now: now,
      );

      expect(reminders, hasLength(taskRemindersScheduledAhead));
      expect(reminders.first.body, contains('overdue'));
    });
  });

  test('tasks with their reminder off are skipped', () {
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

  test('home item names are hidden when the privacy setting is on', () {
    final reminders = planReminders(
      homeItems: [homeItemDueOn(DateTime(2026, 6, 20))],
      settings: upcomingOnly.copyWith(hideDetailsInNotifications: true),
      now: now,
    );

    expect(reminders.single.title, isNot(contains('Furnace')));
    expect(reminders.single.body, isNot(contains('Furnace')));
  });

  group('overview notifications', () {
    final overviews = settings.copyWith(overviewEnabled: true);

    test('are not sent unless the user opts in', () {
      final reminders = planReminders(
        homeItems: [
          homeItemDueOn(
            DateTime(2026, 6, 12),
            reminder: const TaskReminder.off(),
          ),
        ],
        settings: settings,
        now: now,
      );

      expect(reminders, isEmpty);
    });

    test('weekly overviews list the tasks due that week', () {
      final reminders = planReminders(
        homeItems: [
          homeItemDueOn(
            DateTime(2026, 6, 17),
            name: 'Furnace',
            reminder: const TaskReminder.off(),
          ),
          homeItemDueOn(
            DateTime(2026, 6, 30),
            name: 'Dryer',
            reminder: const TaskReminder.off(),
          ),
        ],
        settings: overviews.copyWith(
          overviewFrequency: OverviewFrequency.weekly,
          overviewWeekday: DateTime.monday,
        ),
        now: now,
      );

      // Mondays June 15, 22 and 29 at the overview time. Nothing is due the
      // week of June 22, but the Furnace is still overdue then, so that
      // overview is sent too.
      expect(reminders.map((reminder) => reminder.time), [
        DateTime(2026, 6, 15, 8),
        DateTime(2026, 6, 22, 8),
        DateTime(2026, 6, 29, 8),
      ]);
      expect(reminders.every((r) => r.kind == ReminderKind.overview), isTrue);

      final firstWeek = reminders.first;
      expect(firstWeek.title, 'Home maintenance this week');
      expect(firstWeek.body, contains('Furnace'));
      expect(firstWeek.body, isNot(contains('Dryer')));

      final lastWeek = reminders.last;
      expect(lastWeek.body, contains('Dryer'));
    });

    test('monthly overviews are sent on the 1st of each month', () {
      final reminders = planReminders(
        homeItems: [
          homeItemDueOn(
            DateTime(2026, 7, 20),
            reminder: const TaskReminder.off(),
          ),
        ],
        settings: overviews.copyWith(
          overviewFrequency: OverviewFrequency.monthly,
        ),
        now: now,
      );

      // The task is due in July and stays overdue afterwards, so the July,
      // August and September overviews all mention it.
      expect(reminders.map((reminder) => reminder.time), [
        DateTime(2026, 7, 1, 8),
        DateTime(2026, 8, 1, 8),
        DateTime(2026, 9, 1, 8),
      ]);
      expect(reminders.first.title, 'Home maintenance this month');
      expect(reminders.first.body, contains('Replace filter (Furnace)'));
    });

    test('overviews with nothing due are skipped', () {
      final reminders = planReminders(
        homeItems: [
          homeItemDueOn(
            DateTime(2026, 12, 1),
            reminder: const TaskReminder.off(),
          ),
        ],
        settings: overviews,
        now: now,
      );

      expect(reminders, isEmpty);
    });

    test('arrive at their own time, apart from task notifications', () {
      // Due Monday, June 15, the same day as the first weekly overview.
      final reminders = planReminders(
        homeItems: [homeItemDueOn(DateTime(2026, 6, 15))],
        settings: overviews.copyWith(overdueEnabled: false),
        now: now,
      );

      expect(reminders.map((reminder) => (reminder.kind, reminder.time)), [
        (ReminderKind.overview, DateTime(2026, 6, 15, 8)),
        (ReminderKind.task, DateTime(2026, 6, 15, 9, 30)),
        (ReminderKind.overview, DateTime(2026, 6, 22, 8)),
        (ReminderKind.overview, DateTime(2026, 6, 29, 8)),
      ]);
    });

    test('come first when sent at the same time as a task notification', () {
      final reminders = planReminders(
        homeItems: [homeItemDueOn(DateTime(2026, 6, 15))],
        settings: overviews.copyWith(
          overdueEnabled: false,
          overviewHour: 9,
          overviewMinute: 30,
        ),
        now: now,
      );

      final (overview, task) = (reminders[0], reminders[1]);
      expect(overview.kind, ReminderKind.overview);
      expect(task.kind, ReminderKind.task);
      expect(task.time, overview.time);
    });
  });

  test('never plans more than the platform limit', () {
    final homeItems = [
      for (var day = 0; day < maxScheduledReminders + 10; day++)
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
}
