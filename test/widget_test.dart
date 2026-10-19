import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometrackhub/app.dart';
import 'package:hometrackhub/data/home_item_repository.dart';
import 'package:hometrackhub/data/settings_repository.dart';
import 'package:hometrackhub/models/home_item.dart';
import 'package:hometrackhub/models/home_item_category.dart';
import 'package:hometrackhub/models/maintenance_interval.dart';
import 'package:hometrackhub/models/maintenance_task.dart';
import 'package:hometrackhub/services/calendar_service.dart';
import 'package:hometrackhub/services/device_discovery_service.dart';
import 'package:hometrackhub/services/notification_service.dart';
import 'package:hometrackhub/services/reminder_planner.dart';
import 'package:hometrackhub/state/home_item_controller.dart';
import 'package:hometrackhub/state/settings_controller.dart';
import 'package:hometrackhub/ui/home_shell.dart';
import 'package:hometrackhub/ui/screens/launch/launch_screen.dart';
import 'package:hometrackhub/ui/widgets/form_rows.dart';
import 'package:hometrackhub/utils/date_utils.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'calendar_sync_test.dart' show FakeCalendarService;

class FakeNotificationService implements NotificationService {
  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> replaceScheduledReminders(
    List<PlannedReminder> reminders,
  ) async {}

  @override
  Future<void> showTestNotification() async {}

  int openSettingsCalls = 0;

  @override
  Future<bool> openDeviceNotificationSettings() async {
    openSettingsCalls++;
    return true;
  }
}

class FakeDiscoveryService implements DeviceDiscoveryService {
  @override
  Future<bool> isConnectedToLocalNetwork() async => true;

  @override
  Stream<DiscoveredDevice> scan({
    Duration duration = Duration.zero,
    bool includeNetwork = true,
  }) {
    return Stream.value(
      const DiscoveredDevice(
        id: 'mdns:living room tv',
        name: 'Living Room TV',
        kind: 'Google Cast device',
        suggestedTypeId: 'smart_tv',
      ),
    );
  }

  @override
  Future<DiscoveredDevice?> loadDetails(DiscoveredDevice device) async =>
      device;
}

/// Starts the app with fake services and waits until the launch animation
/// has finished. Pass [notifications] to inspect what the app asked the
/// notification service to do.
Future<void> pumpApp(
  WidgetTester tester, {
  FakeNotificationService? notifications,
  FakeCalendarService? calendar,
}) async {
  await startApp(tester, notifications: notifications, calendar: calendar);
  await tester.pumpAndSettle();
}

/// Starts the app with fake services, leaving the launch animation at its
/// first frame.
Future<void> startApp(
  WidgetTester tester, {
  FakeNotificationService? notifications,
  FakeCalendarService? calendar,
}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => HomeItemController(HomeItemRepository(preferences)),
        ),
        ChangeNotifierProvider(
          create: (_) => SettingsController(SettingsRepository(preferences)),
        ),
        Provider<NotificationService>.value(
          value: notifications ?? FakeNotificationService(),
        ),
        Provider<CalendarService>.value(
          value: calendar ?? FakeCalendarService(),
        ),
        Provider<DeviceDiscoveryService>.value(value: FakeDiscoveryService()),
      ],
      child: const HomeTrackHubApp(),
    ),
  );

  // The launch screen waits for its logo to load. Loading an image takes
  // real time, which widget tests only allow inside runAsync.
  await tester.runAsync(
    () => precacheImage(
      LaunchScreen.logo,
      tester.element(find.byType(LaunchScreen)),
    ),
  );
  await tester.pump();
}

/// Taps [name] on the My Home tab to open it for editing, then scrolls down
/// to its maintenance tasks.
Future<void> openHomeItem(WidgetTester tester, String name) async {
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
  // The form's list is the outermost scrollable; text fields have their own.
  await tester.scrollUntilVisible(
    find.byTooltip('Add task'),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(find.byTooltip('Add task'));
  await tester.pumpAndSettle();
}

/// Saves a home item with [tasks], as if the user had added it.
Future<void> addTasks(WidgetTester tester, List<MaintenanceTask> tasks) async {
  final controller = tester
      .element(find.byType(HomeShell))
      .read<HomeItemController>();
  await controller.addHomeItem(
    HomeItem(
      id: 'house',
      name: 'House',
      category: HomeItemCategory.custom,
      tasks: tasks,
    ),
  );
  await tester.pumpAndSettle();
}

/// Scrolls the visible tab's list until [finder] is on screen.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

/// Swipes the calendar to the next week, month or year, or to the previous
/// one when [back] is true.
Future<void> swipeCalendar(WidgetTester tester, {bool back = false}) async {
  await tester.fling(find.byType(PageView), Offset(back ? 300 : -300, 0), 1000);
  await tester.pumpAndSettle();
}

/// Picks [label] ("Week", "Month" or "Year") from the menu under the
/// calendar's title.
Future<void> showPeriod(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Show week, month or year'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('adding a home item from the catalog schedules its maintenance', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No maintenance scheduled yet'), findsOneWidget);

    await tester.tap(find.text('My Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add home item'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appliances'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refrigerator'));
    await tester.pumpAndSettle();
    // Only saved home items can be deleted.
    expect(find.byTooltip('Delete home item'), findsNothing);
    // Recommended tasks are only added when asked for.
    expect(find.text('Replace water filter'), findsNothing);
    await tester.tap(find.text('Add recommended tasks'));
    await tester.pumpAndSettle();
    expect(find.text('Add recommended tasks'), findsNothing);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Saving skips the pickers and returns to the list of home items.
    expect(find.text('Refrigerator'), findsOneWidget);
    expect(find.byTooltip('Add home item'), findsOneWidget);

    // Tapping the home item opens it for editing, with its recommended tasks.
    await openHomeItem(tester, 'Refrigerator');
    expect(find.text('Edit appliance'), findsOneWidget);
    expect(find.text('Replace water filter'), findsOneWidget);
    expect(find.text('Clean condenser coils'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // The tasks also appear on the Calendar tab in the month they are due,
    // which for door gaskets is three months from now.
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    expect(find.text('Clean door gaskets'), findsNothing);
    for (var i = 0; i < 3; i++) {
      await swipeCalendar(tester);
    }
    expect(find.text('Clean door gaskets'), findsOneWidget);
  });

  testWidgets('completed tasks are checked, even from earlier days', (
    tester,
  ) async {
    await pumpApp(tester);
    final today = dateOnly(DateTime.now());
    final yesterday = today.subtract(const Duration(days: 1));
    await addTasks(tester, [
      MaintenanceTask(
        id: 'smoke-alarms',
        title: 'Test smoke alarms',
        interval: const MaintenanceInterval.months(1),
        startDate: yesterday.subtract(const Duration(days: 30)),
        lastCompleted: yesterday,
        completionDates: [yesterday],
      ),
    ]);
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    if (yesterday.month != today.month) {
      await swipeCalendar(tester, back: true);
    }

    final row = find.widgetWithText(ListTile, 'Test smoke alarms');
    await scrollTo(tester, row);
    expect(find.text('Completed (1)'), findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.byIcon(Icons.check_circle)),
      findsOneWidget,
    );

    // Unchecking it undoes yesterday's completion.
    await tester.tap(find.byTooltip('Unmark done'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Completed'), findsNothing);

    // Lets the message with Undo close.
    await tester.pump(HomeItemController.doneTaskMoveDelay);
    await tester.pumpAndSettle();
  });

  testWidgets('the calendar is swiped between months, fading other months', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();

    const months = [
      'January', 'February', 'March', 'April', 'May', 'June', 'July', //
      'August', 'September', 'October', 'November', 'December',
    ];
    String monthTitle(int monthsFromNow) {
      final now = DateTime.now();
      final month = DateTime(now.year, now.month + monthsFromNow);
      return '${months[month.month - 1]} ${month.year}';
    }

    expect(find.text(monthTitle(0)), findsOneWidget);
    await swipeCalendar(tester);
    expect(find.text(monthTitle(1)), findsOneWidget);
    await swipeCalendar(tester, back: true);
    await swipeCalendar(tester, back: true);
    expect(find.text(monthTitle(-1)), findsOneWidget);

    // Six weeks are always shown, so some days belong to the months either
    // side and are half faded.
    final faded = find.byWidgetPredicate(
      (widget) => widget is Opacity && widget.opacity == 0.5,
    );
    expect(faded, findsAtLeastNWidgets(42 - 31));

    // The weekday letters stay still above the pages that swipe.
    expect(
      find.descendant(of: find.byType(PageView), matching: find.text('M')),
      findsNothing,
    );

    // Tapping a faded day moves to its month and selects it. The last day
    // shown is always in the next month.
    final shown = DateTime(DateTime.now().year, DateTime.now().month - 1);
    final lastShown = DateTime(
      shown.year,
      shown.month,
      1 - shown.weekday % 7 + 41,
    );
    await tester.tap(faded.last);
    await tester.pumpAndSettle();
    expect(find.text(monthTitle(0)), findsOneWidget);
    expect(
      find.text(
        '${months[lastShown.month - 1]} ${lastShown.day}, ${lastShown.year}',
      ),
      findsOneWidget,
    );
    expect(find.text('Show whole month'), findsOneWidget);

    // Today goes back to this month.
    await tester.tap(find.byTooltip('Today'));
    await tester.pumpAndSettle();
    expect(find.text(monthTitle(0)), findsOneWidget);
  });

  testWidgets('the calendar lists every task in the period shown', (
    tester,
  ) async {
    await pumpApp(tester);
    final today = dateOnly(DateTime.now());
    await addTasks(tester, [
      MaintenanceTask(
        id: 'gutters',
        title: 'Clean gutters',
        interval: const MaintenanceInterval.weeks(1),
        startDate: today.subtract(const Duration(days: 14)),
      ),
      MaintenanceTask(
        id: 'water-heater',
        title: 'Flush water heater',
        interval: const MaintenanceInterval.years(1),
        startDate: today,
        lastCompleted: today,
        completionDates: [today],
      ),
      MaintenanceTask(
        id: 'mower',
        title: 'Service lawn mower',
        interval: const MaintenanceInterval.years(1),
        startDate: today,
      ),
    ]);
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();

    // This month: the overdue task, then the one completed today at the
    // bottom. The mower isn't due until next year.
    expect(find.text('Overdue (1)'), findsOneWidget);
    expect(find.text('Clean gutters'), findsOneWidget);
    await scrollTo(tester, find.text('Flush water heater'));
    expect(find.text('Completed (1)'), findsOneWidget);
    expect(find.text('Flush water heater'), findsOneWidget);
    expect(find.text('Service lawn mower'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Flush water heater')).dy,
      greaterThan(tester.getTopLeft(find.text('Clean gutters')).dy),
    );

    // Next year has both yearly tasks due, and nothing completed yet.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 2000));
    await tester.pumpAndSettle();
    await showPeriod(tester, 'Year');
    await swipeCalendar(tester);
    await scrollTo(tester, find.text('Service lawn mower'));
    await scrollTo(tester, find.text('Flush water heater'));
    expect(find.textContaining('Completed'), findsNothing);
  });

  testWidgets('network scan results can be added as home items', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('My Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add home item'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Find nearby devices'));
    await tester.pumpAndSettle();

    expect(find.text('Living Room TV'), findsOneWidget);
    await tester.tap(find.text('Living Room TV'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add recommended tasks'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Saving returns to the scan results so more devices can be added.
    expect(find.text('Living Room TV'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await openHomeItem(tester, 'Living Room TV');
    expect(find.text('Install software updates'), findsOneWidget);
  });

  testWidgets('the add task button can be scrolled above the navigation bar', (
    tester,
  ) async {
    // On-screen navigation buttons are drawn over the bottom of the app.
    const navigationBarHeight = 48.0;
    final physicalHeight = navigationBarHeight * tester.view.devicePixelRatio;
    tester.view.padding = FakeViewPadding(bottom: physicalHeight);
    tester.view.viewPadding = FakeViewPadding(bottom: physicalHeight);
    addTearDown(tester.view.reset);

    await pumpApp(tester);

    await tester.tap(find.text('My Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add home item'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appliances'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refrigerator'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await openHomeItem(tester, 'Refrigerator');

    // Scroll as far down as the form goes.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
    await tester.pumpAndSettle();

    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(
      tester.getRect(find.byTooltip('Add task')).bottom,
      lessThanOrEqualTo(screenHeight - navigationBarHeight),
    );
  });

  testWidgets('tasks marked done move to the bottom after a few seconds', (
    tester,
  ) async {
    await pumpApp(tester);
    // Two weekly tasks due today. Once done, a weekly task is next due
    // outside this week, so it is only listed once as completed.
    final lastWeek = dateOnly(DateTime.now()).subtract(const Duration(days: 7));
    await addTasks(tester, [
      for (final (id, title) in [
        ('salt', 'Check water softener salt'),
        ('filter', 'Replace water filter'),
      ])
        MaintenanceTask(
          id: id,
          title: title,
          interval: const MaintenanceInterval.weeks(1),
          startDate: lastWeek,
        ),
    ]);
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    await showPeriod(tester, 'Week');

    final task = find.text('Replace water filter');
    await scrollTo(tester, task);
    final topBefore = tester.getTopLeft(task).dy;
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Replace water filter'),
        matching: find.byTooltip('Mark done today'),
      ),
    );
    await tester.pump();

    // At first the task stays where it was, showing that it's done.
    expect(tester.getTopLeft(task).dy, topBefore);
    expect(find.textContaining('Completed'), findsNothing);

    expect(find.text('Undo'), findsOneWidget);

    await tester.pump(HomeItemController.doneTaskMoveDelay);
    expect(find.text('Due (1)'), findsOneWidget);
    expect(find.text('Completed (1)'), findsOneWidget);
    expect(
      tester.getTopLeft(task).dy,
      greaterThan(tester.getTopLeft(find.text('Completed (1)')).dy),
    );

    // The message with Undo goes away once the task has moved.
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('a home item can be deleted from its edit screen', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('My Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add home item'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appliances'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refrigerator'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    await openHomeItem(tester, 'Refrigerator');
    await tester.tap(find.byTooltip('Delete home item'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Refrigerator'), findsNothing);
    expect(find.textContaining('not tracking any home items'), findsOneWidget);
  });

  testWidgets('tasks are deleted, not marked done, from the edit screen', (
    tester,
  ) async {
    await pumpApp(tester);
    await addTasks(tester, [
      MaintenanceTask(
        id: 'filter',
        title: 'Replace water filter',
        interval: const MaintenanceInterval.weeks(1),
        startDate: dateOnly(DateTime.now()),
      ),
    ]);
    await tester.tap(find.text('My Home'));
    await tester.pumpAndSettle();
    await openHomeItem(tester, 'House');
    expect(find.byTooltip('Mark done today'), findsNothing);

    // The task's own screen doesn't delete it.
    await tester.tap(find.text('Replace water filter'));
    await tester.pumpAndSettle();
    expect(find.text('Edit task'), findsOneWidget);
    expect(find.byTooltip('Delete task'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Deleting asks first, so cancelling keeps the task.
    await tester.tap(find.byTooltip('Delete task'));
    await tester.pumpAndSettle();
    expect(find.text('Delete "Replace water filter"?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Replace water filter'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete task'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Replace water filter'), findsNothing);
  });

  testWidgets('each category lists only its own types', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('My Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add home item'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vehicles'));
    await tester.pumpAndSettle();

    expect(find.text('Motorcycle'), findsOneWidget);
    expect(find.text('Refrigerator'), findsNothing);

    // Custom has no catalog types, so it opens the home item form directly.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Custom'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    expect(find.text('Add custom item'), findsOneWidget);
  });

  testWidgets('recommended tasks can be removed or changed before saving', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('My Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add home item'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appliances'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refrigerator'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add recommended tasks'));
    await tester.pumpAndSettle();

    // The form's list is the outermost scrollable; text fields have their own.
    final formList = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Clean condenser coils'),
      200,
      scrollable: formList,
    );
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Replace water filter'),
        matching: find.byTooltip('Delete task'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Replace water filter'), findsNothing);
    // The button comes back so a removed task can be added again.
    expect(find.text('Add recommended tasks'), findsOneWidget);

    await tester.tap(find.text('Clean condenser coils'));
    await tester.pumpAndSettle();
    // The task screen shows which home item the task is for.
    expect(
      find.descendant(
        of: find.widgetWithText(InlineValueRow, 'For'),
        matching: find.text('Refrigerator'),
      ),
      findsOneWidget,
    );
    // The fields are the task, its instructions, then how often it repeats.
    await tester.enterText(find.byType(TextFormField).at(2), '3');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      find.text('Every 3 months (recommended: every 6 months)'),
      findsOneWidget,
    );

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await openHomeItem(tester, 'Refrigerator');

    // Only the remaining tasks are created, with the user's changes.
    expect(find.text('Replace water filter'), findsNothing);
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Clean condenser coils'),
        matching: find.textContaining('Every 3 months'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('each task has its own reminder that can be turned off', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('My Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add home item'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appliances'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refrigerator'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add recommended tasks'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await openHomeItem(tester, 'Refrigerator');

    await tester.ensureVisible(find.text('Replace water filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace water filter'));
    await tester.pumpAndSettle();
    // The form's list is the outermost scrollable; text fields have their own.
    await tester.scrollUntilVisible(
      find.textContaining('Next reminder'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('On the due date'), findsOneWidget);

    await tester.tap(find.text('On the due date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Never'));
    await tester.pumpAndSettle();
    expect(find.text('Never'), findsOneWidget);
    expect(find.textContaining('Next reminder'), findsNothing);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Only the task that was changed has its reminder off.
    expect(find.textContaining('Reminder off'), findsOneWidget);
  });

  testWidgets('a weekly or monthly overview can be turned on', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Overview off'), findsOneWidget);
    await tester.tap(find.text('Notifications'));
    await tester.pumpAndSettle();
    expect(find.text('Overview time'), findsNothing);

    await tester.tap(find.text('Weekly'));
    await tester.pumpAndSettle();
    expect(find.text('Monday'), findsOneWidget);
    expect(find.text('Overview time'), findsOneWidget);

    await tester.tap(find.text('Monthly'));
    await tester.pumpAndSettle();
    expect(find.text('1st of each month'), findsOneWidget);

    // The settings list summarizes the choice.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.textContaining('Monthly overview on the 1st'), findsOneWidget);
  });

  testWidgets('notification settings can open the device settings', (
    tester,
  ) async {
    final notifications = FakeNotificationService();
    await pumpApp(tester, notifications: notifications);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notifications'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notification settings'));
    await tester.pumpAndSettle();

    expect(notifications.openSettingsCalls, 1);
  });

  testWidgets('tasks can be added to a calendar the user picks', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Calendar sync'));
    await tester.pumpAndSettle();
    expect(find.text('Personal'), findsNothing);

    // Turning sync on picks the main calendar.
    await tester.tap(find.text('Sync tasks with my calendar'));
    await tester.pumpAndSettle();
    expect(find.text('Personal'), findsOneWidget);
    expect(
      tester
          .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
          .groupValue,
      'personal',
    );

    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();

    // The settings list summarizes the choice.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Adding tasks to Work'), findsOneWidget);
  });

  testWidgets('the calendar list explains how to add a separate calendar', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Calendar sync'));
    await tester.pumpAndSettle();
    const tip = 'Tip: Create a home maintenance calendar';
    expect(find.text(tip), findsNothing);

    await tester.tap(find.text('Sync tasks with my calendar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(tip));
    await tester.pumpAndSettle();
    expect(find.textContaining('Create new calendar'), findsOneWidget);
    // Tests run as Android, so the iPhone and iPad sync step is left out.
    expect(find.textContaining('syncselect'), findsNothing);

    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Create new calendar'), findsNothing);
  });

  testWidgets('calendar sync explains itself in a help dialog', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Calendar sync'));
    await tester.pumpAndSettle();
    expect(find.textContaining('all-day event'), findsNothing);

    await tester.tap(find.byTooltip('Help'));
    await tester.pumpAndSettle();
    expect(find.textContaining('all-day event'), findsOneWidget);

    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.textContaining('all-day event'), findsNothing);
  });

  testWidgets('calendar sync stays off if calendar access is turned down', (
    tester,
  ) async {
    final calendar = FakeCalendarService()..accessAllowed = false;
    await pumpApp(tester, calendar: calendar);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Calendar sync'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sync tasks with my calendar'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    expect(find.textContaining('Allow calendar access'), findsOneWidget);
    await tester.tap(find.widgetWithText(SnackBarAction, 'Settings'));
    expect(calendar.openSettingsCalls, 1);
  });

  testWidgets('dark mode can be selected in settings', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
  });

  group('launch screen', () {
    final logo = find.image(LaunchScreen.logo);
    final mainScreen = find.text('HomeTrack Hub');

    testWidgets('shows the logo, then reveals the main screen', (tester) async {
      await startApp(tester);
      expect(logo, findsOneWidget);
      expect(mainScreen, findsNothing);

      // Partway through, the main screen is being revealed under the logo.
      await tester.pump(const Duration(milliseconds: 1000));
      expect(logo, findsOneWidget);
      expect(mainScreen, findsOneWidget);

      // Once finished, only the main screen is left.
      await tester.pumpAndSettle();
      expect(logo, findsNothing);
      expect(mainScreen, findsOneWidget);
    });

    testWidgets('is short when the device asks for reduced motion', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );

      await startApp(tester);
      expect(logo, findsOneWidget);

      await tester.pump(const Duration(milliseconds: 450));
      expect(logo, findsNothing);
      expect(mainScreen, findsOneWidget);
    });
  });
}
