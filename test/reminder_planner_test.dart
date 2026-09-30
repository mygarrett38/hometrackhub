import 'package:flutter_test/flutter_test.dart';
import 'package:hometrackhub/models/app_settings.dart';
import 'package:hometrackhub/models/home_item.dart';
import 'package:hometrackhub/models/home_item_category.dart';
import 'package:hometrackhub/models/maintenance_interval.dart';
import 'package:hometrackhub/models/maintenance_task.dart';
import 'package:hometrackhub/services/reminder_planner.dart';

/// Creates a home item with one monthly task that is next due on [dueDate].
HomeItem homeItemDueOn(
  DateTime dueDate, {
  String name = 'Furnace',
  String taskTitle = 'Replace filter',
  bool remindersEnabled = true,
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
        remindersEnabled: remindersEnabled,
      ),
    ],
  );
}

void main() {
  final now = DateTime(2026, 6, 10, 12, 0);
  const settings = AppSettings(reminderHour: 9, reminderMinute: 30);

  test('plans nothing when notifications are turned off', () {
    final reminders = planReminders(
      homeItems: [homeItemDueOn(DateTime(2026, 6, 20))],
      settings: settings.copyWith(notificationsEnabled: false),
      now: now,
    );

    expect(reminders, isEmpty);
  });

  test('reminds on the due date at the chosen time', () {
    final reminders = planReminders(
      homeItems: [homeItemDueOn(DateTime(2026, 6, 20))],
      settings: settings,
      now: now,
    );

    expect(reminders.single.time, DateTime(2026, 6, 20, 9, 30));
    expect(reminders.single.title, 'Furnace: Replace filter');
    expect(reminders.single.body, contains('due today'));
  });

  test('reminds the chosen number of days early', () {
    final reminders = planReminders(
      homeItems: [homeItemDueOn(DateTime(2026, 6, 20))],
      settings: settings.copyWith(reminderDaysBefore: 3),
      now: now,
    );

    expect(reminders.single.time, DateTime(2026, 6, 17, 9, 30));
    expect(reminders.single.body, contains('due in 3 days'));
  });

  test('reminds about overdue tasks at the next reminder time', () {
    // It is already past 9:30 today, so the reminder moves to tomorrow.
    final reminders = planReminders(
      homeItems: [homeItemDueOn(DateTime(2026, 6, 1))],
      settings: settings,
      now: now,
    );

    expect(reminders.single.time, DateTime(2026, 6, 11, 9, 30));
    expect(reminders.single.body, contains('overdue'));
  });

  test('combines tasks reminded at the same time', () {
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

  test('skips tasks with reminders turned off', () {
    final reminders = planReminders(
      homeItems: [
        homeItemDueOn(DateTime(2026, 6, 20), remindersEnabled: false),
      ],
      settings: settings,
      now: now,
    );

    expect(reminders, isEmpty);
  });

  test('hides home item names when privacy setting is on', () {
    final reminders = planReminders(
      homeItems: [homeItemDueOn(DateTime(2026, 6, 20))],
      settings: settings.copyWith(hideDetailsInNotifications: true),
      now: now,
    );

    expect(reminders.single.title, isNot(contains('Furnace')));
    expect(reminders.single.body, isNot(contains('Furnace')));
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
    // The soonest reminders are the ones kept.
    expect(reminders.first.time, DateTime(2026, 7, 1, 9, 30));
  });
}
