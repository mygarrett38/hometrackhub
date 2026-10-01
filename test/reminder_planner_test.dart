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
  TaskReminder reminder = const TaskReminder(hour: 9, minute: 30),
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

void main() {
  // Wednesday, June 10, 2026 at noon.
  final now = DateTime(2026, 6, 10, 12, 0);
  const settings = AppSettings();

  group('task reminders', () {
    test('remind on the due date at the task\'s time', () {
      final reminders = planReminders(
        homeItems: [homeItemDueOn(DateTime(2026, 6, 20))],
        settings: settings,
        now: now,
      );

      expect(reminders.single.time, DateTime(2026, 6, 20, 9, 30));
      expect(reminders.single.kind, ReminderKind.task);
      expect(reminders.single.title, 'Furnace: Replace filter');
      expect(reminders.single.body, contains('due today'));
    });

    test('each task uses its own schedule', () {
      final reminders = planReminders(
        homeItems: [
          homeItemDueOn(
            DateTime(2026, 6, 20),
            name: 'Furnace',
            reminder: const TaskReminder(daysBefore: 3, hour: 7, minute: 15),
          ),
          homeItemDueOn(
            DateTime(2026, 6, 20),
            name: 'Dryer',
            reminder: const TaskReminder(daysBefore: 0, hour: 18, minute: 0),
          ),
        ],
        settings: settings,
        now: now,
      );

      expect(reminders.map((reminder) => reminder.time), [
        DateTime(2026, 6, 17, 7, 15),
        DateTime(2026, 6, 20, 18, 0),
      ]);
      expect(reminders.first.body, contains('due in 3 days'));
    });

    test('overdue tasks are reminded at the task\'s next reminder time', () {
      // It is already past 9:30 today, so the reminder moves to tomorrow.
      final reminders = planReminders(
        homeItems: [homeItemDueOn(DateTime(2026, 6, 1))],
        settings: settings,
        now: now,
      );

      expect(reminders.single.time, DateTime(2026, 6, 11, 9, 30));
      expect(reminders.single.body, contains('overdue'));
    });

    test('tasks reminded at the same moment are combined', () {
      final reminders = planReminders(
        homeItems: [
          homeItemDueOn(DateTime(2026, 6, 20), name: 'Furnace'),
          homeItemDueOn(DateTime(2026, 6, 20), name: 'Dryer'),
        ],
        settings: settings,
        now: now,
      );

      expect(reminders, hasLength(1));
      expect(reminders.single.title, '2 maintenance tasks need attention');
      expect(reminders.single.body, contains('Furnace'));
      expect(reminders.single.body, contains('Dryer'));
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
        settings: settings.copyWith(hideDetailsInNotifications: true),
        now: now,
      );

      expect(reminders.single.title, isNot(contains('Furnace')));
      expect(reminders.single.body, isNot(contains('Furnace')));
    });
  });

  group('overview notifications', () {
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
        settings: settings.copyWith(
          overviewFrequency: OverviewFrequency.weekly,
          overviewWeekday: DateTime.monday,
          overviewHour: 8,
        ),
        now: now,
      );

      // Mondays June 15, 22 and 29. Nothing is due the week of June 22, but
      // the Furnace is still overdue then, so that overview is sent too.
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
        settings: settings.copyWith(
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
        settings: settings.copyWith(
          overviewFrequency: OverviewFrequency.weekly,
        ),
        now: now,
      );

      expect(reminders, isEmpty);
    });

    test('include tasks whose own reminder is on, alongside that reminder', () {
      final reminders = planReminders(
        homeItems: [homeItemDueOn(DateTime(2026, 6, 16))],
        settings: settings.copyWith(
          overviewFrequency: OverviewFrequency.weekly,
          overviewWeekday: DateTime.monday,
        ),
        now: now,
      );

      expect(reminders.map((reminder) => reminder.kind), [
        ReminderKind.overview,
        ReminderKind.task,
        ReminderKind.overview,
        ReminderKind.overview,
      ]);
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
