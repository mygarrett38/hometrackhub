import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometrackhub/app.dart';
import 'package:hometrackhub/data/home_item_repository.dart';
import 'package:hometrackhub/data/settings_repository.dart';
import 'package:hometrackhub/services/calendar_service.dart';
import 'package:hometrackhub/services/device_discovery_service.dart';
import 'package:hometrackhub/services/notification_service.dart';
import 'package:hometrackhub/services/reminder_planner.dart';
import 'package:hometrackhub/state/home_item_controller.dart';
import 'package:hometrackhub/state/settings_controller.dart';
import 'package:hometrackhub/ui/screens/launch/launch_screen.dart';
import 'package:hometrackhub/ui/widgets/form_rows.dart';
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

void main() {
  testWidgets('adding a home item from the catalog schedules its maintenance', (
    tester,
  ) async {
    await pumpApp(tester);
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

    // The tasks also appear on the Upcoming tab.
    await tester.tap(find.text('Upcoming'));
    await tester.pumpAndSettle();
    expect(find.text('Clean door gaskets'), findsOneWidget);
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
    await tester.tap(find.text('Upcoming'));
    await tester.pumpAndSettle();

    final task = find.text('Replace water filter');
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
    expect(find.textContaining('Done today'), findsNothing);

    expect(find.text('Undo'), findsOneWidget);

    await tester.pump(HomeItemController.doneTaskMoveDelay);
    expect(find.text('Done today (1)'), findsOneWidget);
    expect(
      tester.getTopLeft(task).dy,
      greaterThan(tester.getTopLeft(find.text('Done today (1)')).dy),
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

  testWidgets('recommended tasks can be unticked or changed before saving', (
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
        matching: find.byType(Checkbox),
      ),
    );
    await tester.pumpAndSettle();

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

    // Only the ticked tasks are created, with the user's changes.
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
    final mainScreen = find.text('Upcoming Maintenance');

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
