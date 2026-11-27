import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometrackhub/app.dart';
import 'package:hometrackhub/data/assist_chat_repository.dart';
import 'package:hometrackhub/data/home_item_repository.dart';
import 'package:hometrackhub/data/settings_repository.dart';
import 'package:hometrackhub/models/app_settings.dart';
import 'package:hometrackhub/models/assist_chat.dart';
import 'package:hometrackhub/models/calendar_period.dart';
import 'package:hometrackhub/models/home_expense.dart';
import 'package:hometrackhub/models/home_item.dart';
import 'package:hometrackhub/models/home_item_category.dart';
import 'package:hometrackhub/models/maintenance_interval.dart';
import 'package:hometrackhub/models/maintenance_task.dart';
import 'package:hometrackhub/models/service_type.dart';
import 'package:hometrackhub/models/suggested_task.dart';
import 'package:hometrackhub/models/task_reminder.dart';
import 'package:hometrackhub/models/technical_level.dart';
import 'package:hometrackhub/services/calendar_service.dart';
import 'package:hometrackhub/services/data_export_service.dart';
import 'package:hometrackhub/services/device_discovery_service.dart';
import 'package:hometrackhub/services/home_assistant_client.dart';
import 'package:hometrackhub/services/location_service.dart';
import 'package:hometrackhub/services/nearby_services_client.dart';
import 'package:hometrackhub/services/notification_service.dart';
import 'package:hometrackhub/services/reminder_planner.dart';
import 'package:hometrackhub/state/assist_chat_controller.dart';
import 'package:hometrackhub/state/home_item_controller.dart';
import 'package:hometrackhub/state/settings_controller.dart';
import 'package:hometrackhub/ui/home_shell.dart';
import 'package:hometrackhub/ui/screens/dashboard/dashboard_screen.dart';
import 'package:hometrackhub/ui/screens/assist/assist_new_chat_screen.dart';
import 'package:hometrackhub/ui/screens/assist/assist_widgets.dart';
import 'package:hometrackhub/ui/screens/assist/nearby_services_screen.dart';
import 'package:hometrackhub/ui/screens/launch/launch_screen.dart';
import 'package:hometrackhub/ui/screens/settings/assistant_settings_screen.dart';
import 'package:hometrackhub/ui/screens/upcoming/maintenance_calendar_screen.dart';
import 'package:hometrackhub/ui/widgets/form_rows.dart';
import 'package:hometrackhub/utils/date_utils.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'calendar_sync_test.dart' show FakeCalendarService;
import 'nearby_services_test.dart' show FakeLocationService;

class FakeNotificationService implements NotificationService {
  @override
  Future<void> initialize() async {}

  /// What the user answers when asked to allow notifications.
  bool permissionGranted = true;

  @override
  Future<bool> requestPermission() async => permissionGranted;

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

  /// Add a kind of reminder to act as if the user tapped one.
  final taps = StreamController<ReminderKind>.broadcast();

  @override
  Stream<ReminderKind> get tappedReminders => taps.stream;
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

class FakeAssistantClient implements HomeAssistantClient {
  FakeAssistantClient({this.isConfigured = true});

  @override
  final bool isConfigured;

  /// What the next question gets: an [AssistantReply] to return, or an
  /// exception to throw.
  Object reply = const AssistantReply(answer: 'Every 90 days.');

  /// The conversation sent with each question, oldest first.
  final conversations = <List<AssistantMessage>>[];

  /// The technical level each question was asked at, oldest first.
  final technicalLevels = <TechnicalLevel>[];

  /// When set, questions aren't answered until this completes, so a test
  /// can see what happens while the assistant is working on an answer.
  Future<void>? answerWhen;

  @override
  Future<AssistantReply> ask(
    List<AssistantMessage> conversation, {
    TechnicalLevel technicalLevel = TechnicalLevel.someExperience,
  }) async {
    conversations.add(List.of(conversation));
    technicalLevels.add(technicalLevel);
    if (answerWhen case final wait?) await wait;
    final reply = this.reply;
    if (reply is AssistantReply) return reply;
    throw reply;
  }
}

/// Records what the app asked to save or share instead of opening the
/// device's save dialog or share sheet.
class FakeDataExportService implements DataExportService {
  /// What the user does in the save dialog: true to save, false to cancel.
  /// Set to an error to make saving fail.
  Object saveAnswer = true;

  final saved = <(String, String)>[];
  final shared = <(String, String)>[];

  @override
  Future<bool> save(String fileName, String contents) async {
    final answer = saveAnswer;
    if (answer is! bool) throw answer;
    if (answer) saved.add((fileName, contents));
    return answer;
  }

  @override
  Future<void> share(String fileName, String contents, {Rect? origin}) async {
    shared.add((fileName, contents));
  }

  /// The file the user picks to load, or `null` to cancel.
  OpenedFile? openAnswer;

  @override
  Future<OpenedFile?> open() async => openAnswer;
}

/// Starts the app with fake services and waits until the launch animation
/// has finished. Pass [notifications] to inspect what the app asked the
/// notification service to do, and [savedData] for what the app finds
/// already saved on the device.
Future<void> pumpApp(
  WidgetTester tester, {
  FakeNotificationService? notifications,
  FakeCalendarService? calendar,
  FakeAssistantClient? assistant,
  FakeDataExportService? export,
  Map<String, Object> savedData = const {},
  bool firstLaunch = false,
}) async {
  await startApp(
    tester,
    notifications: notifications,
    calendar: calendar,
    assistant: assistant,
    export: export,
    savedData: savedData,
    firstLaunch: firstLaunch,
  );
  await tester.pumpAndSettle();
}

/// Starts the app with fake services, leaving the launch animation at its
/// first frame.
///
/// Unless [firstLaunch] is true, the app starts as if the user had already
/// been asked about the AI assistant, so that question doesn't get in the
/// way of other tests.
Future<void> startApp(
  WidgetTester tester, {
  FakeNotificationService? notifications,
  FakeCalendarService? calendar,
  FakeAssistantClient? assistant,
  FakeDataExportService? export,
  Map<String, Object> savedData = const {},
  bool firstLaunch = false,
}) async {
  final data = {...savedData};
  if (!firstLaunch) {
    final settings = switch (data['settings_v1']) {
      final String json => jsonDecode(json) as Map<String, dynamic>,
      _ => const AppSettings().toJson(),
    };
    data['settings_v1'] = jsonEncode({
      ...settings,
      'askedAboutAssistant': true,
    });
  }
  SharedPreferences.setMockInitialValues(data);
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
        ChangeNotifierProvider(
          create: (context) => AssistChatController(
            AssistChatRepository(preferences),
            context.read<SettingsController>(),
          ),
        ),
        Provider<NotificationService>.value(
          value: notifications ?? FakeNotificationService(),
        ),
        Provider<CalendarService>.value(
          value: calendar ?? FakeCalendarService(),
        ),
        Provider<DeviceDiscoveryService>.value(value: FakeDiscoveryService()),
        Provider<HomeAssistantClient>.value(
          value: assistant ?? FakeAssistantClient(),
        ),
        Provider<DataExportService>.value(
          value: export ?? FakeDataExportService(),
        ),
        Provider<NearbyServicesClient>.value(
          value: SampleNearbyServicesClient(delay: Duration.zero),
        ),
        Provider<LocationService>.value(value: FakeLocationService()),
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

/// The default name of a chat started today: "October 28th Chat", or with
/// [number] when several chats were started today.
String todaysChat([int? number]) =>
    '${monthDayOrdinal(DateTime.now())} Chat${number == null ? '' : ' $number'}';

/// Opens the Assist tab and its New conversation screen.
Future<void> openNewConversation(WidgetTester tester) async {
  await tester.tap(find.text('Assist'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('New conversation'));
  await tester.pumpAndSettle();
}

/// Types [question] on an Assist screen and sends it.
Future<void> askAssistant(WidgetTester tester, String question) async {
  await tester.enterText(find.byType(TextField), question);
  // The send button is enabled on the next frame.
  await tester.pump();
  await tester.tap(find.byTooltip('Send'));
  await tester.pumpAndSettle();
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
    await tester.tap(find.text('Add'));
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
    // A completed task says when it was done instead of when it's due, and
    // the calendar leaves out how often it repeats.
    expect(
      find.descendant(
        of: row,
        matching: find.text('House · Completed yesterday', findRichText: true),
      ),
      findsOneWidget,
    );

    // Unchecking it undoes yesterday's completion.
    await tester.tap(find.byTooltip('Unmark done'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Completed ('), findsNothing);

    // Lets the message with Undo close.
    await tester.pump(HomeItemController.doneTaskMoveDelay);
    await tester.pumpAndSettle();
  });

  testWidgets(
    'due tasks on the calendar open the task; completed ones do not',
    (tester) async {
      await pumpApp(tester);
      final today = dateOnly(DateTime.now());
      await addTasks(tester, [
        MaintenanceTask(
          id: 'filter',
          title: 'Replace water filter',
          interval: const MaintenanceInterval.weeks(1),
          startDate: today.subtract(const Duration(days: 7)),
        ),
        MaintenanceTask(
          id: 'smoke-alarms',
          title: 'Test smoke alarms',
          interval: const MaintenanceInterval.months(1),
          startDate: today.subtract(const Duration(days: 30)),
          lastCompleted: today,
          completionDates: [today],
        ),
      ]);
      await tester.tap(find.text('Calendar'));
      await tester.pumpAndSettle();
      await showPeriod(tester, 'Week');

      final due = find.widgetWithText(ListTile, 'Replace water filter');
      final done = find.widgetWithText(ListTile, 'Test smoke alarms');
      await scrollTo(tester, done);
      expect(
        find.descendant(of: done, matching: find.byIcon(Icons.chevron_right)),
        findsNothing,
      );
      await tester.tap(find.text('Test smoke alarms'));
      await tester.pumpAndSettle();
      expect(find.text('Edit task'), findsNothing);

      await scrollTo(tester, due);
      expect(
        find.descendant(of: due, matching: find.byIcon(Icons.chevron_right)),
        findsOneWidget,
      );
      await tester.tap(find.text('Replace water filter'));
      await tester.pumpAndSettle();
      expect(find.text('Edit task'), findsOneWidget);
      expect(
        find.widgetWithText(TextFormField, 'Replace water filter'),
        findsOneWidget,
      );
    },
  );

  testWidgets('a later month lists tasks by when they are due in it', (
    tester,
  ) async {
    await pumpApp(tester);
    final today = dateOnly(DateTime.now());
    final shownMonth = DateTime(today.year, today.month + 2);
    await addTasks(tester, [
      MaintenanceTask(
        id: 'plants',
        title: 'Water plants',
        interval: const MaintenanceInterval.weeks(1),
        startDate: today,
      ),
      // Due on the first of the month shown.
      MaintenanceTask(
        id: 'filter',
        title: 'Change filter',
        interval: const MaintenanceInterval.months(1),
        startDate: DateTime(shownMonth.year, shownMonth.month - 1),
      ),
    ]);
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    await swipeCalendar(tester);
    await swipeCalendar(tester);

    // The weekly task is listed for the first time it repeats in that
    // month, and says so, rather than when it's next due.
    var plantsDue = today.add(const Duration(days: 7));
    while (plantsDue.isBefore(shownMonth)) {
      plantsDue = plantsDue.add(const Duration(days: 7));
    }
    Finder rowSays(String title, DateTime due) => find.descendant(
      of: find.widgetWithText(ListTile, title),
      matching: find.text(
        'House · ${describeDueDateRoughly(due, today)}',
        findRichText: true,
      ),
    );
    await scrollTo(tester, find.text('Water plants'));
    expect(rowSays('Water plants', plantsDue), findsOneWidget);
    expect(rowSays('Change filter', shownMonth), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Change filter')).dy,
      lessThan(tester.getTopLeft(find.text('Water plants')).dy),
    );
  });

  testWidgets('tasks completed more than a day ago can no longer be changed', (
    tester,
  ) async {
    await pumpApp(tester);
    final today = dateOnly(DateTime.now());
    final threeDaysAgo = today.subtract(const Duration(days: 3));
    await addTasks(tester, [
      MaintenanceTask(
        id: 'smoke-alarms',
        title: 'Test smoke alarms',
        interval: const MaintenanceInterval.months(1),
        startDate: threeDaysAgo.subtract(const Duration(days: 30)),
        lastCompleted: threeDaysAgo,
        completionDates: [threeDaysAgo],
      ),
    ]);
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    if (threeDaysAgo.month != today.month) {
      await swipeCalendar(tester, back: true);
    }

    final row = find.widgetWithText(ListTile, 'Test smoke alarms');
    await scrollTo(tester, row);
    expect(
      find.descendant(of: row, matching: find.byIcon(Icons.check_circle)),
      findsOneWidget,
    );
    expect(find.byTooltip('Unmark done'), findsNothing);
    expect(
      find.descendant(
        of: row,
        matching: find.text('House · Completed 3 days ago', findRichText: true),
      ),
      findsOneWidget,
    );

    // Tapping it doesn't open the home item.
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.text('Edit custom item'), findsNothing);
    expect(find.text('Completed (1)'), findsOneWidget);
  });

  testWidgets('tapping a reminder shows the tasks it lists on the Overview', (
    tester,
  ) async {
    final today = dateOnly(DateTime.now());
    final notifications = FakeNotificationService();
    await pumpApp(tester, notifications: notifications);
    await addTasks(tester, [
      MaintenanceTask(
        id: 'gutters',
        title: 'Clean gutters',
        interval: const MaintenanceInterval.months(1),
        // Due 10 days ago.
        startDate: DateTime(today.year, today.month - 1, today.day - 10),
      ),
      MaintenanceTask(
        id: 'filter',
        title: 'Replace water filter',
        interval: const MaintenanceInterval.months(1),
        // Due in 10 days.
        startDate: DateTime(today.year, today.month - 1, today.day + 10),
      ),
    ]);
    final overdue = find.text('Overdue (1)');
    final upcoming = find.text('Upcoming (1)');

    // Even from a screen on another tab, the reminder's tasks are shown.
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notifications'));
    await tester.pumpAndSettle();
    notifications.taps.add(ReminderKind.overdue);
    await tester.pumpAndSettle();
    expect(find.text('Upcoming tasks'), findsNothing);
    expect(overdue, findsOneWidget);
    expect(upcoming, findsNothing);
    final overdueCard = tester.getRect(
      find.ancestor(of: overdue, matching: find.byType(Card)).first,
    );
    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(overdueCard.bottom, lessThan(screenHeight));

    notifications.taps.add(ReminderKind.upcoming);
    await tester.pumpAndSettle();
    expect(upcoming, findsOneWidget);
    expect(overdue, findsNothing);
  });

  testWidgets('the Overview lists tasks below its cards, and a card lists '
      'only its own', (tester) async {
    final today = dateOnly(DateTime.now());
    await pumpApp(tester);
    await addTasks(tester, [
      MaintenanceTask(
        id: 'gutters',
        title: 'Clean gutters',
        interval: const MaintenanceInterval.months(1),
        // Due 10 days ago.
        startDate: DateTime(today.year, today.month - 1, today.day - 10),
      ),
      MaintenanceTask(
        id: 'filter',
        title: 'Replace water filter',
        interval: const MaintenanceInterval.months(1),
        // Due in 10 days.
        startDate: DateTime(today.year, today.month - 1, today.day + 10),
      ),
      MaintenanceTask(
        id: 'smoke-alarms',
        title: 'Test smoke alarms',
        interval: const MaintenanceInterval.months(6),
        startDate: today,
        lastCompleted: today,
        completionDates: [today],
      ),
      // Outside the month ahead and the month back, so not counted.
      MaintenanceTask(
        id: 'roof',
        title: 'Inspect roof',
        interval: const MaintenanceInterval.months(3),
        // Due in about 45 days.
        startDate: DateTime(today.year, today.month - 3, today.day + 45),
      ),
      MaintenanceTask(
        id: 'chimney',
        title: 'Sweep chimney',
        interval: const MaintenanceInterval.months(12),
        startDate: today.subtract(const Duration(days: 45)),
        lastCompleted: today.subtract(const Duration(days: 45)),
        completionDates: [today.subtract(const Duration(days: 45))],
      ),
    ]);

    final overdue = find.text('Overdue (1)');
    final upcoming = find.text('Upcoming (1)');
    // Named like the Overview card it's listed for.
    final completed = find.text('Recently completed (1)');
    double top(Finder finder) => tester.getTopLeft(finder).dy;

    // Overdue, upcoming, then completed, all below the summary cards and
    // the assistant button.
    expect(overdue, findsOneWidget);
    expect(upcoming, findsOneWidget);
    expect(completed, findsOneWidget);
    expect(
      top(overdue),
      greaterThan(top(find.textContaining('Ask AI Assist'))),
    );
    expect(top(upcoming), greaterThan(top(overdue)));
    expect(top(completed), greaterThan(top(upcoming)));
    // A line sets the tasks apart from the summary above.
    final divider = find.byType(Divider).first;
    expect(top(divider), greaterThan(top(find.textContaining('Ask AI'))));
    expect(top(divider), lessThan(top(overdue)));
    // Finished tasks are a record, so they don't open.
    expect(
      find.descendant(
        of: find.ancestor(of: completed, matching: find.byType(Card)),
        matching: find.byIcon(Icons.chevron_right),
      ),
      findsNothing,
    );

    /// Taps the summary card labelled [label], scrolling back up to it if
    /// the list scrolled down to the tasks.
    Future<void> tapCard(Finder label) async {
      await tester.ensureVisible(label);
      await tester.pumpAndSettle();
      await tester.tap(label);
      await tester.pumpAndSettle();
    }

    // Tapping a card lists only its tasks, scrolled into view; tapping it
    // again lists them all.
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(scroll.position.pixels, 0);

    /// The outline around the card titled [title].
    BorderSide outline(Finder title) {
      final card = tester.widget<Card>(
        find.ancestor(of: title, matching: find.byType(Card)).first,
      );
      return (card.shape! as RoundedRectangleBorder).side;
    }

    // Once scrolled to, the picked card's tasks flash an outline briefly.
    await tester.tap(find.text('Overdue'));
    var flashed = false;
    for (var i = 0; i < 30 && !flashed; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      flashed = outline(overdue).width == 2;
    }
    expect(flashed, isTrue);
    await tester.pumpAndSettle();
    expect(outline(overdue), BorderSide.none);
    expect(scroll.position.pixels, greaterThan(0));
    // As far as the page goes: the tasks are on screen.
    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(tester.getBottomLeft(overdue).dy, lessThan(screenHeight));
    expect(overdue, findsOneWidget);
    expect(upcoming, findsNothing);
    expect(completed, findsNothing);

    // Tapping it again lists all the tasks without moving the page.
    await tester.ensureVisible(find.text('Overdue'));
    await tester.pumpAndSettle();
    final scrolledTo = scroll.position.pixels;
    await tester.tap(find.text('Overdue'));
    await tester.pumpAndSettle();
    expect(upcoming, findsOneWidget);
    expect(scroll.position.pixels, scrolledTo);

    await tapCard(find.text('Recently Completed'));
    expect(completed, findsOneWidget);
    expect(overdue, findsNothing);
    expect(upcoming, findsNothing);

    // Another card switches straight to its tasks.
    await tapCard(find.text('Upcoming'));
    expect(upcoming, findsOneWidget);
    expect(overdue, findsNothing);
    expect(completed, findsNothing);

    // Like the calendar, a task checked off stays put for a moment with a
    // way to undo it.
    final markDone = find.byTooltip('Mark done today');
    await tester.ensureVisible(markDone);
    await tester.pumpAndSettle();
    await tester.tap(markDone);
    await tester.pump();
    expect(find.text('Marked as done'), findsOneWidget);
    expect(upcoming, findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Marked as done'), findsNothing);
    expect(upcoming, findsOneWidget);
    await tester.pump(HomeItemController.doneTaskMoveDelay);

    // Leaving the Overview lists all of them again when coming back.
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Overview'));
    await tester.pumpAndSettle();
    expect(overdue, findsOneWidget);
    expect(upcoming, findsOneWidget);
    expect(completed, findsOneWidget);
  });

  testWidgets('the calendar title lines up with other tab titles', (
    tester,
  ) async {
    tester.view.padding = const FakeViewPadding(top: 72);
    addTearDown(tester.view.reset);
    await pumpApp(tester);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    final settings = tester.getRect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Settings')),
    );

    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    final calendar = tester.getRect(
      find
          .descendant(
            of: find.byTooltip('Show week, month or year'),
            matching: find.byType(Text),
          )
          .first,
    );
    expect(calendar.left, settings.left);
    expect(calendar.top, settings.top);
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
    expect(find.textContaining('Completed ('), findsNothing);
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
    await tester.tap(find.text('Add'));
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
    await tester.tap(find.text('Add'));
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

  testWidgets('marking a task done offers Undo at the top of its card', (
    tester,
  ) async {
    await pumpApp(tester);
    final lastWeek = dateOnly(DateTime.now()).subtract(const Duration(days: 7));
    await addTasks(tester, [
      MaintenanceTask(
        id: 'filter',
        title: 'Replace water filter',
        interval: const MaintenanceInterval.weeks(1),
        startDate: lastWeek,
      ),
    ]);
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    final markDone = find.byTooltip('Mark done today');
    await scrollTo(tester, markDone);

    final message = find.text('Marked as done');
    // The fade nearest the message is its own.
    double opacity() => tester
        .widget<FadeTransition>(
          find
              .ancestor(of: message, matching: find.byType(FadeTransition))
              .first,
        )
        .opacity
        .value;

    // It shows straight away, without fading in.
    await tester.tap(markDone);
    await tester.pump();
    expect(opacity(), 1);
    expect(find.byType(SnackBar), findsNothing);
    await tester.pumpAndSettle();

    // It's on the right of the heading of the card the task is in, and
    // screen readers hear which task it was.
    final heading = find.text('Due (1)');
    expect(tester.getCenter(message).dy, tester.getCenter(heading).dy);
    expect(
      tester.getTopLeft(message).dx,
      greaterThanOrEqualTo(tester.getTopRight(heading).dx),
    );
    expect(
      tester.widget<Text>(message).semanticsLabel,
      'Marked "Replace water filter" as done',
    );

    // Undo puts the task back.
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(message, findsNothing);
    expect(find.byTooltip('Mark done today'), findsOneWidget);

    // Otherwise it fades out once the task has moved down.
    await tester.tap(find.byTooltip('Mark done today'));
    await tester.pumpAndSettle();
    expect(opacity(), 1);
    await tester.pump(HomeItemController.doneTaskMoveDelay);
    await tester.pump(const Duration(milliseconds: 100));
    expect(opacity(), inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(message, findsNothing);
    expect(find.text('Completed (1)'), findsOneWidget);
  });

  group('the keyboard', () {
    /// Whether a text field is being typed in, with the keyboard up.
    bool typing(WidgetTester tester) {
      final focused = FocusManager.instance.primaryFocus;
      final inTextField =
          focused?.context?.findAncestorStateOfType<EditableTextState>() !=
          null;
      return inTextField && tester.testTextInput.isVisible;
    }

    testWidgets("doesn't come back on returning to a screen", (tester) async {
      await pumpApp(tester);
      // A home item named House.
      await addTasks(tester, const []);
      await tester.tap(find.text('My Home'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('House'));
      await tester.pumpAndSettle();

      // Typing in its name, then opening another screen.
      final name = find.byWidgetPredicate(
        (widget) => widget is EditableText && widget.controller.text == 'House',
      );
      await tester.tap(name);
      await tester.pumpAndSettle();
      expect(typing(tester), isTrue);
      await scrollTo(tester, find.byTooltip('Add task'));
      await tester.tap(find.byTooltip('Add task'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Add task'), findsOneWidget);
      expect(typing(tester), isFalse);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(name, findsOneWidget);
      expect(typing(tester), isFalse);
    });

    testWidgets("doesn't come back on returning to a tab", (tester) async {
      await pumpApp(
        tester,
        savedData: {
          'settings_v1': jsonEncode({
            ...const AppSettings().toJson(),
            // So the Assist tab is the nearby services search.
            'assistantEnabled': false,
          }),
        },
      );
      await tester.tap(find.text('Assist'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SearchBar));
      await tester.pumpAndSettle();
      expect(typing(tester), isTrue);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(typing(tester), isFalse);

      await tester.tap(find.text('Assist'));
      await tester.pumpAndSettle();
      expect(typing(tester), isFalse);
    });
  });

  testWidgets('a card whose last task moves on fades out with its note', (
    tester,
  ) async {
    final today = dateOnly(DateTime.now());
    await pumpApp(tester);
    await addTasks(tester, [
      MaintenanceTask(
        id: 'gutters',
        title: 'Clean gutters',
        interval: const MaintenanceInterval.months(1),
        // Due 10 days ago, so once it's done it's no longer overdue.
        startDate: DateTime(today.year, today.month - 1, today.day - 10),
      ),
    ]);
    final markDone = find.byTooltip('Mark done today');
    await scrollTo(tester, markDone);
    await tester.tap(markDone);
    await tester.pumpAndSettle();

    final heading = find.text('Overdue (1)');
    final message = find.text('Marked as done');
    double opacityAbove(Finder finder) => tester
        .widget<FadeTransition>(
          find
              .ancestor(of: finder, matching: find.byType(FadeTransition))
              .first,
        )
        .opacity
        .value;
    expect(heading, findsOneWidget);
    expect(message, findsOneWidget);

    // When the task moves on, the card stays while it and its note fade.
    await tester.pump(HomeItemController.doneTaskMoveDelay);
    await tester.pump(const Duration(milliseconds: 100));
    expect(opacityAbove(heading), inExclusiveRange(0, 1));
    expect(opacityAbove(message), inExclusiveRange(0, 1));
    // Its task can't be checked off again while it goes.
    expect(
      tester
          .widget<IgnorePointer>(
            find
                .ancestor(of: heading, matching: find.byType(IgnorePointer))
                .first,
          )
          .ignoring,
      isTrue,
    );

    await tester.pumpAndSettle();
    expect(heading, findsNothing);
    expect(message, findsNothing);
    expect(find.text('Recently completed (1)'), findsOneWidget);
  });

  group('expenses on the calendar', () {
    /// Whether the calendar is showing expenses rather than tasks.
    bool showingExpenses(WidgetTester tester) =>
        tester
            .widget<SegmentedButton<CalendarView>>(
              find.byType(SegmentedButton<CalendarView>),
            )
            .selected
            .single ==
        CalendarView.expenses;

    /// Records [amount] spent on House on [date], described as [what].
    Future<void> spend(
      WidgetTester tester,
      String what,
      double amount,
      DateTime date,
    ) async {
      await tester
          .element(find.byType(HomeShell, skipOffstage: false))
          .read<HomeItemController>()
          .addExpense(
            'house',
            HomeExpense(
              id: what,
              description: what,
              amount: amount,
              date: date,
            ),
          );
      await tester.pumpAndSettle();
    }

    testWidgets("are opened from the Overview's spending, and added with +", (
      tester,
    ) async {
      await pumpApp(tester);
      await addTasks(tester, []);

      // The Overview's spending opens the calendar's expenses, this month.
      await scrollTo(tester, find.text('Spent This Month'));
      await tester.tap(find.text('Spent This Month'));
      await tester.pumpAndSettle();
      expect(showingExpenses(tester), isTrue);
      expect(find.text('No expenses this month'), findsOneWidget);

      // The total is at the top right, above the calendar, with what it's
      // of read aloud rather than shown.
      final total = find.text(r'$0.00');
      final calendar = tester.getRect(find.byType(PageView));
      expect(tester.getBottomLeft(total).dy, lessThan(calendar.top));
      expect(
        tester.getTopRight(total).dx,
        greaterThan(
          tester.view.physicalSize.width / tester.view.devicePixelRatio / 2,
        ),
      );
      expect(find.text('Spent this month'), findsNothing);
      expect(find.bySemanticsLabel(r'Spent this month, $0.00'), findsOneWidget);

      // Between the calendar and the list is the switch, with + beside it to
      // add an expense, which is a screen of its own.
      final toggle = tester.getRect(find.byType(SegmentedButton<CalendarView>));
      final add = find.byTooltip('Add expense');
      expect(toggle.top, greaterThan(calendar.bottom));
      expect(
        tester.getTopLeft(find.text('No expenses this month')).dy,
        greaterThan(toggle.bottom),
      );
      expect(tester.getCenter(add).dy, closeTo(toggle.center.dy, 1));
      expect(tester.getTopLeft(add).dx, greaterThan(toggle.right));
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Add expense'), findsOneWidget);
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a description'), findsOneWidget);
      expect(find.text(r'Enter an amount above $0'), findsOneWidget);

      // Each message goes away once its field is fixed.
      Finder field(String label) => find.descendant(
        of: find.widgetWithText(InlineTextRow, label),
        matching: find.byType(TextField),
      );
      await tester.enterText(field('Description'), 'New filter');
      await tester.pump();
      expect(find.text('Enter a description'), findsNothing);
      expect(find.text(r'Enter an amount above $0'), findsOneWidget);

      await tester.enterText(field('Amount'), '25');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      // Back on the calendar, it's counted and listed, and marked on its day.
      expect(showingExpenses(tester), isTrue);
      expect(find.text('New filter'), findsOneWidget);
      expect(find.text(r'$25.00'), findsNWidgets(2));
      final today = DateTime.now();
      expect(
        find.bySemanticsLabel(
          '${monthName(today.month)} ${today.day}, 1 expense',
        ),
        findsOneWidget,
      );
    });

    testWidgets('work like tasks: by week, month or year, or one day', (
      tester,
    ) async {
      final now = DateTime.now();
      await pumpApp(tester);
      await addTasks(tester, []);
      await spend(tester, 'New filter', 25, now);
      await spend(tester, 'Roof repair', 400, DateTime(now.year - 1, 6, 10));
      await tester.tap(find.text('Calendar'));
      await tester.pumpAndSettle();

      // The calendar starts on tasks, and switches to expenses.
      expect(showingExpenses(tester), isFalse);
      expect(find.byTooltip('Add expense'), findsNothing);
      await tester.tap(find.text('Expenses'));
      await tester.pumpAndSettle();
      expect(showingExpenses(tester), isTrue);

      // The total is at the top, large, and the expenses under the calendar.
      final total = find.text(r'$25.00').first;
      final calendar = tester.getRect(find.byType(PageView));
      expect(find.bySemanticsLabel(r'Spent this month, $25.00'), findsOne);
      expect(tester.getBottomLeft(total).dy, lessThan(calendar.top));
      expect(
        tester.getTopLeft(find.text('New filter')).dy,
        greaterThan(calendar.bottom),
      );
      expect(
        tester.widget<Text>(total).style!.fontSize,
        greaterThanOrEqualTo(22),
      );

      expect(find.text('Roof repair'), findsNothing);

      // A day narrows it to that day.
      await tester.tap(
        find.bySemanticsLabel('${monthName(now.month)} ${now.day}, 1 expense'),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(r'Spent this day, $25.00'), findsOne);
      expect(find.text('New filter'), findsOneWidget);
      await tester.tap(find.text('Show whole month'));
      await tester.pumpAndSettle();

      // A year lists each month so far, which opens to show its expenses.
      await showPeriod(tester, 'Year');
      expect(find.bySemanticsLabel(r'Spent this year, $25.00'), findsOne);
      await scrollTo(tester, find.text(monthName(now.month)));
      expect(find.text('1 expense'), findsOneWidget);
      expect(find.text('New filter'), findsNothing);
      await tester.tap(find.text(monthName(now.month)));
      await tester.pumpAndSettle();
      expect(find.text('New filter'), findsOneWidget);

      // Earlier years are a swipe away, with what each month cost on the
      // calendar too.
      await tester.dragUntilVisible(
        find.byTooltip('Show week, month or year'),
        find.byType(ListView).first,
        const Offset(0, 300),
      );
      await swipeCalendar(tester, back: true);
      // The title names the year, so the total is just the total.
      expect(find.text('${now.year - 1}'), findsOneWidget);
      expect(find.bySemanticsLabel(r'Total spent, $400.00'), findsOne);
      expect(find.bySemanticsLabel(r'June, $400.00 spent'), findsOneWidget);
      expect(find.text(r'$400.00'), findsNWidgets(3));

      // And back to tasks, which has no total or +.
      await tester.dragUntilVisible(
        find.text('Tasks'),
        find.byType(ListView).first,
        const Offset(0, -300),
      );
      await tester.tap(find.text('Tasks'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp('^Total spent')), findsNothing);
      expect(find.byTooltip('Add expense'), findsNothing);
    });

    testWidgets('need a home item to add an expense to', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.text('Calendar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Expenses'));
      await tester.pumpAndSettle();

      final add = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.add),
      );
      expect(add.onPressed, isNull);
      expect(find.textContaining('Add a home item'), findsOneWidget);
    });
  });

  testWidgets('turning on a reminder with notifications blocked says so', (
    tester,
  ) async {
    final notifications = FakeNotificationService()..permissionGranted = false;
    await pumpApp(tester, notifications: notifications);
    await addTasks(tester, [
      MaintenanceTask(
        id: 'filter',
        title: 'Replace water filter',
        interval: const MaintenanceInterval.weeks(1),
        startDate: dateOnly(DateTime.now()),
        reminder: const TaskReminder(enabled: false),
      ),
    ]);
    await tester.tap(find.text('My Home'));
    await tester.pumpAndSettle();
    await openHomeItem(tester, 'House');
    await tester.tap(find.text('Replace water filter'));
    await tester.pumpAndSettle();

    final form = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('Never'), 200, scrollable: form);
    await tester.tap(find.text('Never'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('On the due date').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('Notifications are blocked'),
      200,
      scrollable: form,
    );
    expect(find.byType(SnackBar), findsNothing);
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
    expect(find.textContaining('Completed ('), findsNothing);

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

  testWidgets('dates on the home item and task screens show the year', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester
        .element(find.byType(HomeShell))
        .read<HomeItemController>()
        .addHomeItem(
          HomeItem(
            id: 'furnace',
            name: 'Furnace',
            category: HomeItemCategory.hvac,
            purchaseDate: DateTime(2019, 8, 2),
            tasks: [
              MaintenanceTask(
                id: 'filter',
                title: 'Replace filter',
                interval: const MaintenanceInterval.months(1),
                startDate: DateTime(2025, 1, 1),
                lastCompleted: DateTime(2025, 3, 14),
                completionDates: [DateTime(2025, 3, 14)],
              ),
            ],
          ),
        );
    await tester.pumpAndSettle();

    await tester.tap(find.text('My Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Furnace'));
    await tester.pumpAndSettle();
    expect(find.text('Aug 2, 2019'), findsOneWidget);

    await scrollTo(tester, find.text('Replace filter'));
    await tester.tap(find.text('Replace filter'));
    await tester.pumpAndSettle();
    expect(find.text('Mar 14, 2025'), findsOneWidget); // Last done
    expect(find.text('Apr 14, 2025'), findsOneWidget); // Next due
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
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    await openHomeItem(tester, 'Refrigerator');
    await tester.tap(find.byTooltip('Delete home item'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Refrigerator'), findsNothing);
    expect(find.textContaining('not tracking any home items'), findsOneWidget);
  });

  group('saving as you edit', () {
    /// The text field of the form row labelled [label].
    Finder field(String label) => find.descendant(
      of: find.widgetWithText(InlineTextRow, label),
      matching: find.byType(TextFormField),
    );

    HomeItemController homeItemsOf(WidgetTester tester) =>
        tester.element(find.byType(MaterialApp)).read<HomeItemController>();

    /// Adds a refrigerator with its recommended tasks from the catalog.
    Future<void> addRefrigerator(WidgetTester tester) async {
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
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
    }

    testWidgets('a new home item is only created when Add is tapped', (
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

      expect(find.text('Save'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(homeItemsOf(tester).homeItems, isEmpty);
    });

    testWidgets('changes to a home item are saved without a Save button', (
      tester,
    ) async {
      await pumpApp(tester);
      await addRefrigerator(tester);
      await tester.tap(find.text('Refrigerator'));
      await tester.pumpAndSettle();
      expect(find.text('Save'), findsNothing);
      expect(find.text('Add'), findsNothing);

      // Saved once the user pauses typing.
      await tester.enterText(field('Name'), 'Kitchen fridge');
      await tester.pump(autosaveDelay);
      expect(homeItemsOf(tester).homeItems.single.name, 'Kitchen fridge');

      // An empty name isn't saved, and the form says why.
      await tester.enterText(field('Name'), '');
      await tester.pump(autosaveDelay);
      expect(find.text('Please enter a name'), findsOneWidget);
      expect(homeItemsOf(tester).homeItems.single.name, 'Kitchen fridge');

      // Leaving straight after typing still saves.
      await tester.enterText(field('Name'), 'Garage fridge');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(homeItemsOf(tester).homeItems.single.name, 'Garage fridge');
      expect(find.text('Garage fridge'), findsOneWidget);
    });

    testWidgets('changes to a task are saved without a Save button', (
      tester,
    ) async {
      await pumpApp(tester);
      await addRefrigerator(tester);
      await openHomeItem(tester, 'Refrigerator');
      await tester.ensureVisible(find.text('Replace water filter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replace water filter'));
      await tester.pumpAndSettle();
      expect(find.text('Save'), findsNothing);
      expect(find.text('Add'), findsNothing);

      await tester.enterText(field('Task'), 'Replace filter cartridge');
      await tester.pageBack();
      await tester.pumpAndSettle();

      final tasks = homeItemsOf(tester).homeItems.single.tasks;
      expect(
        tasks.map((task) => task.title),
        contains('Replace filter cartridge'),
      );
      expect(find.text('Replace filter cartridge'), findsOneWidget);
    });

    testWidgets('a new task is only created when Add is tapped', (
      tester,
    ) async {
      await pumpApp(tester);
      await addRefrigerator(tester);
      await openHomeItem(tester, 'Refrigerator');
      final taskCount = homeItemsOf(tester).homeItems.single.tasks.length;

      await tester.tap(find.byTooltip('Add task'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Task'), 'Check door seal');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(homeItemsOf(tester).homeItems.single.tasks, hasLength(taskCount));

      await tester.tap(find.byTooltip('Add task'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Task'), 'Check door seal');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(
        homeItemsOf(tester).homeItems.single.tasks,
        hasLength(taskCount + 1),
      );
    });
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
    // An arrow shows that tapping a task opens it.
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Replace water filter'),
        matching: find.byIcon(Icons.chevron_right),
      ),
      findsOneWidget,
    );
    // Nor does it say when each task is due.
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Replace water filter'),
        matching: find.textContaining('Due'),
      ),
      findsNothing,
    );

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

  testWidgets('My Home lists items by room, then by name', (tester) async {
    await pumpApp(tester);
    final controller = tester
        .element(find.byType(HomeShell))
        .read<HomeItemController>();
    final today = dateOnly(DateTime.now());
    for (final (id, name, location) in [
      ('1', 'Stove', 'Kitchen'),
      ('2', 'Car', ''),
      ('3', 'Dishwasher', 'kitchen'),
      ('4', 'Water heater', 'Basement'),
    ]) {
      await controller.addHomeItem(
        HomeItem(
          id: id,
          name: name,
          category: HomeItemCategory.custom,
          location: location,
          tasks: [
            MaintenanceTask(
              id: 't$id',
              title: 'Check',
              interval: const MaintenanceInterval.weeks(3),
              startDate: today,
            ),
          ],
        ),
      );
    }
    await tester.tap(find.text('My Home'));
    await tester.pumpAndSettle();

    final order = [
      'Basement',
      'Water heater',
      'Kitchen',
      'Dishwasher',
      'Stove',
      'Unknown',
      'Car',
    ];
    final tops = [
      for (final text in order) tester.getTopLeft(find.text(text)).dy,
    ];
    expect(tops, orderedEquals([...tops]..sort()));
    // "kitchen" and "Kitchen" are the same room.
    expect(find.text('kitchen'), findsNothing);
    expect(find.textContaining('task'), findsNWidgets(4));
    // Only when the next task is due, without counting the tasks.
    expect(find.text('Next task due in 3 weeks'), findsNWidgets(4));
    // Each room's heading shows how many items are in it.
    expect(find.text('2'), findsOneWidget);
    expect(find.text('1'), findsNWidgets(2));

    // Tapping a room's heading collapses it to just the heading.
    await tester.tap(find.text('Kitchen'));
    await tester.pumpAndSettle();
    expect(find.text('Stove'), findsNothing);
    expect(find.text('Water heater'), findsOneWidget);
    await tester.tap(find.text('Kitchen'));
    await tester.pumpAndSettle();
    expect(find.text('Stove'), findsOneWidget);
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
    // Changes are saved as they're made, so just go back.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      find.text('Every 3 months (recommended: every 6 months)'),
      findsOneWidget,
    );

    await tester.tap(find.text('Add'));
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
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await openHomeItem(tester, 'Refrigerator');

    await tester.ensureVisible(find.text('Replace water filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace water filter'));
    await tester.pumpAndSettle();
    // The form's list is the outermost scrollable; text fields have their own.
    await tester.scrollUntilVisible(
      find.text('Start notifying me'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('On the due date'), findsOneWidget);
    // The next due date leads the card with the notification choice.
    final notifyCard = find.ancestor(
      of: find.text('Start notifying me'),
      matching: find.byType(Card),
    );
    expect(
      find.descendant(of: notifyCard, matching: find.text('Next due')),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.text('Next due')).dy,
      lessThan(tester.getTopLeft(find.text('Start notifying me')).dy),
    );

    await tester.tap(find.text('On the due date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Never'));
    await tester.pumpAndSettle();
    expect(find.text('Never'), findsOneWidget);
    // Changes are saved as they're made, so just go back.
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Only the task that was changed has its reminder off.
    expect(find.textContaining('Reminder off'), findsOneWidget);
  });

  group('notification settings', () {
    /// [finder] within the "Receive at" row of the kind of notification
    /// named [kind]: upcoming or overdue.
    Finder receiveAt(String kind, Finder finder) => find.descendant(
      of: find.byKey(Key('${kind}ReceiveAt')),
      matching: finder,
    );

    AppSettings settingsOf(WidgetTester tester) => tester
        .element(find.byType(MaterialApp))
        .read<SettingsController>()
        .settings;

    Future<void> openNotifications(WidgetTester tester) async {
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Notifications'));
      await tester.pumpAndSettle();
    }

    /// Scrolls until [finder] is on screen.
    Future<void> scrollTo(WidgetTester tester, Finder finder) async {
      await tester.scrollUntilVisible(
        finder,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('only overdue notifications have a switch, which shows their '
        'settings', (tester) async {
      await pumpApp(tester);
      await openNotifications(tester);

      // The device's settings, then the kinds of notification.
      expect(find.byType(Card), findsNWidgets(2));
      expect(find.byType(SwitchListTile), findsOneWidget);
      // Overviews were folded into the upcoming and overdue notifications.
      expect(find.text('Overviews'), findsNothing);

      // Upcoming tasks are always notified about, so have no switch. Their
      // settings fold open with an arrow instead.
      expect(
        find.widgetWithText(SwitchListTile, 'Upcoming tasks'),
        findsNothing,
      );
      expect(find.byKey(const Key('upcomingReceiveAt')), findsNothing);
      await tester.tap(find.text('Upcoming tasks'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('upcomingReceiveAt')), findsOneWidget);
      await tester.tap(find.text('Upcoming tasks'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('upcomingReceiveAt')), findsNothing);

      // Overdue notifications start on, and fold away when turned off.
      await scrollTo(tester, find.byKey(const Key('overdueReceiveAt')));
      await tester.tap(find.text('Overdue tasks'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('overdueReceiveAt')), findsNothing);
      expect(settingsOf(tester).overdueEnabled, isFalse);
    });

    testWidgets('each kind of notification is received at its own time and '
        'repeat', (tester) async {
      await pumpApp(tester);
      await openNotifications(tester);
      await tester.tap(find.text('Upcoming tasks'));
      await tester.pumpAndSettle();

      // Read as one phrase: the time, then how often.
      final upcoming = find.byKey(const Key('upcomingReceiveAt'));
      expect(
        find.descendant(of: upcoming, matching: find.text('Receive at')),
        findsOneWidget,
      );
      expect(
        tester.getCenter(receiveAt('upcoming', find.text('9:00 AM'))).dx,
        lessThan(
          tester.getCenter(receiveAt('upcoming', find.text('every day'))).dx,
        ),
      );

      // The time picker opens on 9:00 AM; switching to PM makes it 9:00 PM.
      await tester.tap(receiveAt('upcoming', find.text('9:00 AM')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PM'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(receiveAt('upcoming', find.text('9:00 PM')), findsOneWidget);

      final overdueRepeat = receiveAt('overdue', find.text('every day'));
      await scrollTo(tester, overdueRepeat);
      await tester.tap(overdueRepeat);
      await tester.pumpAndSettle();
      await tester.tap(find.text('every week').last);
      await tester.pumpAndSettle();
      expect(receiveAt('overdue', find.text('every week')), findsOneWidget);
      expect(receiveAt('overdue', find.text('9:00 AM')), findsOneWidget);

      final settings = settingsOf(tester);
      expect((settings.upcomingHour, settings.upcomingMinute), (21, 0));
      expect(settings.upcomingReminderDays, 1);
      expect((settings.overdueHour, settings.overdueMinute), (9, 0));
      expect(settings.overdueReminderDays, 7);
    });
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
    await tester.tap(find.byTooltip('Sync tasks with my calendar'));
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

    // The choice is kept after leaving the screen.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Calendar sync'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
          .groupValue,
      'work',
    );
  });

  testWidgets('the calendar list explains how to add a separate calendar', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Calendar sync'));
    await tester.pumpAndSettle();
    // The tip is there even before sync is turned on.
    await tester.tap(find.text('Create a home maintenance calendar'));
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

    // Help is a card on the screen rather than a button in the title bar.
    expect(find.byTooltip('Help'), findsNothing);
    await tester.tap(find.text('Sync help'));
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
    await tester.tap(find.byTooltip('Sync tasks with my calendar'));
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    // The problem is explained on the screen, not in a pop-up.
    expect(find.byType(SnackBar), findsNothing);
    final problem = find.widgetWithText(
      ListTile,
      'Allow calendar access in Settings to add tasks to your calendar.',
    );
    expect(problem, findsOneWidget);
    await tester.tap(
      find.descendant(
        of: problem,
        matching: find.widgetWithText(TextButton, 'Settings'),
      ),
    );
    expect(calendar.openSettingsCalls, 1);
  });

  testWidgets('the tabs are ordered around the overview, which opens first', (
    tester,
  ) async {
    await pumpApp(tester);

    // The test screen is wide, so the tabs are on the side rail.
    final labels = ['My Home', 'Calendar', 'Overview', 'Assist', 'Settings'];
    final tops = [
      for (final label in labels)
        tester
            .getCenter(
              find.descendant(
                of: find.byType(NavigationRail),
                // The Overview tab is just the app's icon, without a label.
                matching: label == 'Overview'
                    ? find.byTooltip(label)
                    : find.text(label),
              ),
            )
            .dy,
    ];
    expect(tops, orderedEquals([...tops]..sort()));
    expect(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Overview'),
      ),
      findsNothing,
    );
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
      labels.indexOf('Overview'),
    );

    await tester.tap(find.text('Assist'));
    await tester.pumpAndSettle();
    expect(find.text('What would you like to do today?'), findsOneWidget);
  });

  testWidgets('a question opens its own chat screen, named after it', (
    tester,
  ) async {
    final assistant = FakeAssistantClient()
      ..reply = const AssistantReply(
        answer: 'Turn off the breaker before you check it.',
        recommendProfessional: true,
        professionalReason: 'Wiring work needs an electrician.',
      );
    await pumpApp(tester, assistant: assistant);
    await openNewConversation(tester);

    await askAssistant(tester, 'My outlet sparks');
    expect(find.widgetWithText(AppBar, todaysChat()), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.byTooltip('Chat history'), findsNothing);
    expect(
      find.text('Turn off the breaker before you check it.'),
      findsOneWidget,
    );
    expect(
      find.text('Consider a professional: Wiring work needs an electrician.'),
      findsOneWidget,
    );

    // Follow-up questions are sent with the conversation so far.
    assistant.reply = const AssistantReply(answer: 'Only after it is fixed.');
    await askAssistant(tester, 'Can I still use it?');
    expect(
      [
        for (final message in assistant.conversations.last)
          (message.role, message.content),
      ],
      [
        ('user', 'My outlet sparks'),
        ('assistant', 'Turn off the breaker before you check it.'),
        ('user', 'Can I still use it?'),
      ],
    );

    // Back goes straight to the Assist tab, not to an empty new
    // conversation, and an example question there starts another chat.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('What would you like to do today?'), findsOneWidget);
    await tester.tap(find.text('New conversation'));
    await tester.pumpAndSettle();
    assistant.reply = const AssistantReply(answer: 'Every 90 days.');
    final suggestion = tester
        .widget<Text>(
          find.descendant(
            of: find.byType(OutlinedButton).first,
            matching: find.byType(Text),
          ),
        )
        .data!;
    await tester.tap(find.text(suggestion));
    await tester.pumpAndSettle();
    expect(find.text('Every 90 days.'), findsOneWidget);
    expect(find.text('My outlet sparks'), findsNothing);
    expect(
      [for (final message in assistant.conversations.last) message.content],
      [suggestion],
    );
  });

  testWidgets('a new conversation suggests three different example questions, '
      'shown in full', (tester) async {
    tester.view.physicalSize = const Size(412, 900) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Assist'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New conversation'));
    await tester.pumpAndSettle();

    final texts = find.descendant(
      of: find.byType(OutlinedButton),
      matching: find.byType(Text),
    );
    final shown = [
      for (final element in texts.evaluate()) (element.widget as Text).data!,
    ];
    expect(shown, hasLength(AssistNewChatScreen.suggestionCount));
    expect(shown.toSet(), hasLength(shown.length));
    for (final question in shown) {
      expect(AssistNewChatScreen.questions, contains(question));
      // Nothing is cut off, even on a narrow phone.
      final paragraph = tester.renderObject<RenderParagraph>(
        find.text(question),
      );
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(
        tester.getSize(find.text(question)).width,
        lessThanOrEqualTo(tester.getSize(find.byType(Scaffold).last).width),
      );
    }
  });

  testWidgets('the note about the assistant is behind the info button', (
    tester,
  ) async {
    await pumpApp(tester);
    await openNewConversation(tester);
    expect(find.textContaining("sent to Anthropic's Claude"), findsNothing);

    await tester.tap(find.byTooltip('About the assistant'));
    await tester.pumpAndSettle();
    expect(find.textContaining("sent to Anthropic's Claude"), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.textContaining("sent to Anthropic's Claude"), findsNothing);
  });

  testWidgets('the question box has a line above it instead of an outline, '
      'and a send button as tall as it', (tester) async {
    await pumpApp(tester);
    await openNewConversation(tester);

    final field = find.byType(TextField);
    expect(
      tester.widget<TextField>(field).decoration!.border,
      InputBorder.none,
    );
    final line = find.descendant(
      of: find.byType(AssistComposer),
      matching: find.byType(Divider),
    );
    expect(
      tester.getBottomLeft(line).dy,
      lessThanOrEqualTo(tester.getTopLeft(field).dy),
    );
    expect(
      tester.getSize(find.byTooltip('Send')).height,
      tester.getSize(field).height,
    );
  });

  testWidgets('the assistant shows errors on screen and can try again', (
    tester,
  ) async {
    final assistant = FakeAssistantClient()
      ..reply = const AssistantConnectionException(
        'Could not reach the assistant service.',
      );
    await pumpApp(tester, assistant: assistant);
    await openNewConversation(tester);

    await askAssistant(tester, 'Why is my sink slow?');
    expect(find.text('Could not reach the assistant service.'), findsOneWidget);

    assistant.reply = const AssistantReply(answer: 'Clean the P-trap.');
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Could not reach the assistant service.'), findsNothing);
    expect(find.text('Clean the P-trap.'), findsOneWidget);
    // The question is asked again rather than added a second time.
    expect(assistant.conversations.last.length, 1);
  });

  testWidgets('a task the assistant suggests can be added to a home item', (
    tester,
  ) async {
    final assistant = FakeAssistantClient()
      ..reply = const AssistantReply(
        answer: 'A clogged filter makes the furnace work harder.',
        suggestedTasks: [
          SuggestedTask(
            title: 'Replace furnace filter',
            description: 'Slide out the old filter and put in a new one.',
            interval: MaintenanceInterval.months(3),
          ),
        ],
      );
    await pumpApp(tester, assistant: assistant);
    // A home item named House.
    await addTasks(tester, const []);
    await openNewConversation(tester);
    await askAssistant(tester, 'How often should I change my filter?');

    expect(find.text('Add to your schedule'), findsOneWidget);
    expect(find.text('Every 3 months'), findsOneWidget);
    await tester.tap(find.text('Replace furnace filter'));
    await tester.pumpAndSettle();

    // Its own screen asks which home item, grouped by room, with the task
    // at the top.
    expect(find.widgetWithText(AppBar, 'Choose home item'), findsOneWidget);
    expect(find.text('Replace furnace filter'), findsOneWidget);
    expect(find.text('Every 3 months'), findsOneWidget);
    expect(find.text('Unknown'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'House'));
    await tester.pumpAndSettle();

    // The task form opens filled in, for the user to check.
    expect(find.widgetWithText(AppBar, 'Add task'), findsOneWidget);
    expect(find.text('Replace furnace filter'), findsOneWidget);
    expect(
      find.text('Slide out the old filter and put in a new one.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    // Back in the chat, it says where the task went.
    expect(find.text('Add to your schedule'), findsOneWidget);
    expect(
      find.text('Added "Replace furnace filter" to House.'),
      findsOneWidget,
    );
    final task = tester
        // Under the chat's screen.
        .element(find.byType(HomeShell, skipOffstage: false))
        .read<HomeItemController>()
        .findById('house')!
        .tasks
        .single;
    expect(task.title, 'Replace furnace filter');
    expect(task.interval, const MaintenanceInterval.months(3));
    expect(task.description, 'Slide out the old filter and put in a new one.');
  });

  testWidgets('a suggested task without home items says to add one', (
    tester,
  ) async {
    final assistant = FakeAssistantClient()
      ..reply = const AssistantReply(
        answer: 'Test them every month.',
        suggestedTasks: [
          SuggestedTask(
            title: 'Test smoke alarms',
            interval: MaintenanceInterval.months(1),
          ),
        ],
      );
    await pumpApp(tester, assistant: assistant);
    await openNewConversation(tester);
    await askAssistant(tester, 'How often should I test my alarms?');

    await tester.tap(find.text('Test smoke alarms'));
    await tester.pumpAndSettle();
    expect(find.textContaining("don't have any home items"), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Add to your schedule'), findsOneWidget);
  });

  testWidgets('a professional the assistant suggests can be found nearby', (
    tester,
  ) async {
    final assistant = FakeAssistantClient()
      ..reply = const AssistantReply(
        answer: 'Turn off the breaker before you check it.',
        recommendProfessional: true,
        professionalReason: 'Wiring work needs an electrician.',
        professionalService: ServiceType.electrical,
      );
    await pumpApp(tester, assistant: assistant);
    await openNewConversation(tester);
    await askAssistant(tester, 'My outlet sparks');

    await tester.tap(find.text('Find one nearby'));
    await tester.pumpAndSettle();

    // Nearby services opens searching for electricians, with the service
    // shown as picked.
    expect(find.byType(NearbyServicesScreen), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(
            find.widgetWithText(ChoiceChip, ServiceType.electrical.label),
          )
          .selected,
      isTrue,
    );
    expect(find.text('BrightLine Electric'), findsOneWidget);
    expect(find.text('Riverbend Plumbing & Drain'), findsNothing);

    // Back returns to the chat.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Find one nearby'), findsOneWidget);
  });

  testWidgets('a chat left while the assistant answers is still waiting '
      'when reopened, and is answered once', (tester) async {
    final answered = Completer<void>();
    final assistant = FakeAssistantClient()
      ..answerWhen = answered.future
      ..reply = const AssistantReply(answer: 'Clean the P-trap.');
    await pumpApp(tester, assistant: assistant);
    await openNewConversation(tester);

    // The waiting spinner never settles, so frames are pumped by hand.
    Future<void> pumpFor() async {
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    await tester.enterText(find.byType(TextField), 'Why is my sink slow?');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await pumpFor();
    expect(find.text('Thinking…'), findsOneWidget);

    await tester.pageBack();
    await pumpFor();
    await tester.tap(find.text('Continue conversation'));
    await pumpFor();
    await tester.tap(find.widgetWithText(ListTile, todaysChat()));
    await pumpFor();
    expect(find.text('Thinking…'), findsOneWidget);
    expect(find.text("This question hasn't been answered yet."), findsNothing);
    expect(find.text('Try again'), findsNothing);

    answered.complete();
    await tester.pumpAndSettle();
    expect(find.text('Clean the P-trap.'), findsOneWidget);
    expect(find.text('Thinking…'), findsNothing);
    expect(assistant.conversations, hasLength(1));
  });

  testWidgets('chats are reopened from the history and carry on', (
    tester,
  ) async {
    final assistant = FakeAssistantClient()
      ..reply = const AssistantReply(answer: 'Turn off the breaker.');
    await pumpApp(tester, assistant: assistant);
    await openNewConversation(tester);

    await askAssistant(tester, 'My outlet sparks');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await openNewConversation(tester);
    assistant.reply = const AssistantReply(answer: 'Clean the P-trap.');
    await askAssistant(tester, 'Why is my sink slow?');
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Continue conversation lists the newest chat first. Both were started
    // today, so they're numbered. There's no help text above them.
    await tester.tap(find.text('Continue conversation'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.widgetWithText(ListTile, todaysChat(2))).dy,
      lessThan(
        tester.getTopLeft(find.widgetWithText(ListTile, todaysChat(1))).dy,
      ),
    );
    expect(find.textContaining('Press and hold'), findsNothing);
    expect(find.textContaining('deleted after'), findsNothing);

    // Opening an earlier chat shows it, and follow-ups continue it. Its top
    // bar is just its name, since chats are renamed and deleted from the
    // history.
    await tester.tap(find.widgetWithText(ListTile, todaysChat(1)));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, todaysChat(1)), findsOneWidget);
    expect(find.byTooltip('Rename chat'), findsNothing);
    expect(find.byTooltip('Delete chat'), findsNothing);
    expect(find.text('Turn off the breaker.'), findsOneWidget);
    expect(find.text('Clean the P-trap.'), findsNothing);
    await askAssistant(tester, 'Is it safe to use?');
    expect(
      [for (final message in assistant.conversations.last) message.content],
      ['My outlet sparks', 'Turn off the breaker.', 'Is it safe to use?'],
    );

    // Back goes to the history the chat was opened from.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Chat history'), findsOneWidget);
  });

  testWidgets('chats in the history can be selected to pin, rename or '
      'delete them', (tester) async {
    await pumpApp(tester);
    for (final question in ['Outlet?', 'Sink?', 'Gutters?']) {
      await openNewConversation(tester);
      await askAssistant(tester, question);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Continue conversation'));
    await tester.pumpAndSettle();

    Finder chat(String title) => find.widgetWithText(ListTile, title);
    Finder inGroup(String group, String title) => find.descendant(
      of: find.widgetWithText(Card, group),
      matching: find.text(title),
    );
    double top(String title) => tester.getTopLeft(chat(title)).dy;
    Finder button(String label) => find.descendant(
      of: find.byType(BottomAppBar),
      matching: find.text(label),
    );
    Future<void> tapAndSettle(Finder finder) async {
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    bool enabled(String label) => tester
        .widget<ButtonStyleButton>(
          find.ancestor(
            of: button(label),
            matching: find.bySubtype<ButtonStyleButton>(),
          ),
        )
        .enabled;

    final first = todaysChat(1), second = todaysChat(2), third = todaysChat(3);
    expect(find.byType(BottomAppBar), findsNothing);

    // Pressing and holding selects a chat rather than opening it, and shows
    // four buttons in a row at the bottom, each labelled under its icon.
    await tester.longPress(chat(first));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '1 selected'), findsOneWidget);
    const labels = ['Select all', 'Pin', 'Rename', 'Delete'];
    for (final label in labels) {
      expect(button(label), findsOneWidget);
      expect(enabled(label), isTrue);
    }
    final lefts = [
      for (final label in labels) tester.getCenter(button(label)).dx,
    ];
    expect(lefts, orderedEquals([...lefts]..sort()));
    expect({
      for (final label in labels) tester.getCenter(button(label)).dy,
    }, hasLength(1));
    final pinIcon = find.descendant(
      of: find.byType(BottomAppBar),
      matching: find.byIcon(Icons.push_pin_outlined),
    );
    expect(
      tester.getCenter(pinIcon).dy,
      lessThan(tester.getCenter(button('Pin')).dy),
    );
    expect(tester.getSize(pinIcon).width, 28);

    // All the chats start in the Recent card.
    for (final title in [first, second, third]) {
      expect(inGroup('Recent', title), findsOneWidget);
    }
    expect(find.text('Pinned'), findsNothing);

    // Pinning one chat moves it to a Pinned card at the top. It keeps the
    // chat icon, and says when it was last chatted in rather than when it
    // will be deleted.
    await tapAndSettle(button('Pin'));
    expect(find.byType(BottomAppBar), findsNothing);
    expect(inGroup('Pinned', first), findsOneWidget);
    expect(inGroup('Recent', first), findsNothing);
    expect(top(first), lessThan(top(third)));
    expect(
      find.descendant(
        of: chat(first),
        matching: find.text('Last chatted today'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: chat(first),
        matching: find.byIcon(Icons.chat_bubble_outline),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: chat(third),
        matching: find.textContaining('Deleting'),
      ),
      findsOneWidget,
    );

    // Tapping other chats adds them to the selection. With more than one,
    // renaming is greyed out but stays in place.
    await tester.longPress(chat(second));
    await tester.pumpAndSettle();
    await tapAndSettle(chat(first));
    expect(find.widgetWithText(AppBar, '2 selected'), findsOneWidget);
    expect(enabled('Rename'), isFalse);

    // With only some pinned, the button pins them all.
    expect(button('Unpin'), findsNothing);
    await tapAndSettle(button('Pin'));
    expect(inGroup('Pinned', first), findsOneWidget);
    expect(inGroup('Pinned', second), findsOneWidget);
    expect(inGroup('Recent', third), findsOneWidget);
    expect(top(second), lessThan(top(third)));

    // Each card can be collapsed to its heading, which shows the count.
    final pinnedCard = find.widgetWithText(Card, 'Pinned');
    expect(
      find.descendant(of: pinnedCard, matching: find.text('2')),
      findsOneWidget,
    );
    await tapAndSettle(find.text('Pinned'));
    expect(chat(first), findsNothing);
    expect(chat(third), findsOneWidget);
    await tapAndSettle(find.text('Pinned'));
    expect(chat(first), findsOneWidget);

    // With all of them pinned, it unpins them instead.
    await tester.longPress(chat(first));
    await tester.pumpAndSettle();
    await tapAndSettle(chat(second));
    await tapAndSettle(button('Unpin'));
    expect(find.text('Pinned'), findsNothing);

    // Select all selects every chat, and then deselects them all.
    await tester.longPress(chat(first));
    await tester.pumpAndSettle();
    await tapAndSettle(button('Select all'));
    expect(find.widgetWithText(AppBar, '3 selected'), findsOneWidget);
    await tapAndSettle(button('Deselect all'));
    expect(find.byType(BottomAppBar), findsNothing);
    expect(find.widgetWithText(AppBar, 'Chat history'), findsOneWidget);

    // Tapping a selected chat deselects it, and the close button stops selecting.
    await tester.longPress(chat(first));
    await tester.pumpAndSettle();
    await tapAndSettle(chat(second));
    await tapAndSettle(chat(second));
    expect(find.widgetWithText(AppBar, '1 selected'), findsOneWidget);
    await tapAndSettle(find.byTooltip('Cancel selection'));
    expect(find.widgetWithText(AppBar, 'Chat history'), findsOneWidget);

    // A single chat can be renamed, which edits the name in its card.
    await tester.longPress(chat(first));
    await tester.pumpAndSettle();
    await tapAndSettle(button('Rename'));
    final nameField = find.descendant(
      of: find.byType(Card),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(nameField).controller!.text, first);
    await tester.enterText(nameField, 'Outlet');
    await tapAndSettle(find.byTooltip('Save name'));
    expect(nameField, findsNothing);
    expect(chat('Outlet'), findsOneWidget);

    // Several chats are deleted together after asking once.
    await tester.longPress(chat('Outlet'));
    await tester.pumpAndSettle();
    await tapAndSettle(chat(third));
    await tapAndSettle(button('Delete'));
    expect(find.text('Delete 2 chats?'), findsOneWidget);
    await tapAndSettle(find.widgetWithText(FilledButton, 'Delete'));
    expect(chat('Outlet'), findsNothing);
    expect(chat(third), findsNothing);
    expect(chat(second), findsOneWidget);
    expect(find.byType(BottomAppBar), findsNothing);
  });

  testWidgets('answers are formatted with Markdown, but questions are not', (
    tester,
  ) async {
    final assistant = FakeAssistantClient()
      ..reply = const AssistantReply(
        answer:
            '**Turn off the power** first.\n\n'
            '- Check the breaker\n'
            '- Test the outlet',
      );
    await pumpApp(tester, assistant: assistant);
    await openNewConversation(tester);
    await askAssistant(tester, 'Is **this** safe?');

    // The question is shown just as it was typed.
    expect(find.text('Is **this** safe?'), findsOneWidget);

    // The answer's Markdown is formatted rather than shown as symbols.
    expect(find.textContaining('**'), findsOneWidget);
    expect(find.text('Turn off the power first.'), findsOneWidget);
    expect(find.text('Check the breaker'), findsOneWidget);
    expect(find.text('Test the outlet'), findsOneWidget);

    bool isBold(InlineSpan span, String text) {
      if (span is! TextSpan) return false;
      if (span.text == text && span.style?.fontWeight == FontWeight.bold) {
        return true;
      }
      return span.children?.any((child) => isBold(child, text)) ?? false;
    }

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText &&
            widget.textSpan != null &&
            isBold(widget.textSpan!, 'Turn off the power'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the first time the app opens, it asks about the assistant, '
      'and turning it off leaves only nearby services', (tester) async {
    await pumpApp(tester, firstLaunch: true);
    expect(find.text('Use the AI assistant?'), findsOneWidget);

    await tester.tap(find.text('Turn it off'));
    await tester.pumpAndSettle();
    expect(find.text('Use the AI assistant?'), findsNothing);
    final settings = tester
        .element(find.byType(HomeShell))
        .read<SettingsController>()
        .settings;
    expect(settings.assistantEnabled, isFalse);
    expect(settings.askedAboutAssistant, isTrue);

    // The Overview no longer points to the assistant, and the Assist tab is
    // just the nearby services search.
    expect(find.textContaining('Ask AI Assist'), findsNothing);
    await tester.tap(find.text('Assist'));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(AppBar, 'Search nearby services'),
      findsOneWidget,
    );
    expect(find.text('What would you like to do today?'), findsNothing);
  });

  testWidgets('keeping the assistant on at first launch keeps the Assist tab', (
    tester,
  ) async {
    await pumpApp(tester, firstLaunch: true);
    await tester.tap(find.text('Keep it on'));
    await tester.pumpAndSettle();

    final settings = tester
        .element(find.byType(HomeShell))
        .read<SettingsController>()
        .settings;
    expect(settings.assistantEnabled, isTrue);
    expect(settings.askedAboutAssistant, isTrue);
    expect(find.textContaining('Ask AI Assist'), findsOneWidget);
    await tester.tap(find.text('Assist'));
    await tester.pumpAndSettle();
    expect(find.text('What would you like to do today?'), findsOneWidget);
  });

  testWidgets('the app only asks about the assistant once', (tester) async {
    await pumpApp(tester);
    expect(find.text('Use the AI assistant?'), findsNothing);
  });

  testWidgets('the app does not ask about an assistant it does not have', (
    tester,
  ) async {
    await pumpApp(
      tester,
      firstLaunch: true,
      assistant: FakeAssistantClient(isConfigured: false),
    );
    expect(find.text('Use the AI assistant?'), findsNothing);
  });

  testWidgets('the switch in the Assistant settings turns the assistant on '
      'and off', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assistant'));
    await tester.pumpAndSettle();

    final toggle = find.descendant(
      of: find.byType(AppBar),
      matching: find.byType(Switch),
    );
    expect(tester.widget<Switch>(toggle).value, isTrue);
    expect(find.byTooltip('Use the AI assistant'), findsOneWidget);
    // There's only a message about the assistant while it's off.
    expect(find.text('The assistant is on'), findsNothing);
    expect(find.text('The assistant is off'), findsNothing);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(toggle).value, isFalse);
    expect(find.text('The assistant is off'), findsOneWidget);
    // Its other settings are hidden while it's off.
    expect(find.text('Technical level'), findsNothing);
    expect(find.text('Keep chats for'), findsNothing);
    expect(find.text('Delete chats'), findsNothing);

    // The Assist tab follows the switch.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assist'));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(AppBar, 'Search nearby services'),
      findsOneWidget,
    );

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assistant'));
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assist'));
    await tester.pumpAndSettle();
    expect(find.text('What would you like to do today?'), findsOneWidget);
  });

  testWidgets('with the assistant off, nearby services wait until the '
      'Assist tab is opened', (tester) async {
    await pumpApp(
      tester,
      savedData: {
        'settings_v1': jsonEncode({
          ...const AppSettings().toJson(),
          'assistantEnabled': false,
        }),
      },
    );
    // Nothing is searched for, or located, while another tab is shown.
    expect(
      find.text('Riverbend Plumbing & Drain', skipOffstage: false),
      findsNothing,
    );

    await tester.tap(find.text('Assist'));
    await tester.pumpAndSettle();
    expect(find.text('Riverbend Plumbing & Drain'), findsOneWidget);
  });

  /// Opens Settings, then the Assistant settings page.
  Future<void> openAssistantSettings(WidgetTester tester) async {
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assistant'));
    await tester.pumpAndSettle();
  }

  testWidgets('questions are asked at the technical level from settings', (
    tester,
  ) async {
    final assistant = FakeAssistantClient();
    await pumpApp(tester, assistant: assistant);
    await openAssistantSettings(tester);

    await tester.tap(find.byType(DropdownButton<TechnicalLevel>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Handy').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .element(find.byType(AssistantSettingsScreen))
          .read<SettingsController>()
          .settings
          .technicalLevel,
      TechnicalLevel.handy,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    await openNewConversation(tester);
    await askAssistant(tester, 'How do I replace a faucet cartridge?');
    expect(assistant.technicalLevels, [TechnicalLevel.handy]);
  });

  testWidgets('shortening how long chats are kept asks before deleting any', (
    tester,
  ) async {
    final tenDaysAgo = DateTime.now().subtract(const Duration(days: 10));
    await pumpApp(
      tester,
      savedData: {
        'assist_chats_v1': jsonEncode([
          AssistChat(
            id: 'old',
            messages: const [AssistChatMessage.user('Old question')],
            createdAt: tenDaysAgo,
            lastActiveAt: tenDaysAgo,
            dayNumber: 1,
          ).toJson(),
        ]),
      },
    );
    final chats = tester
        .element(find.byType(HomeShell))
        .read<AssistChatController>();
    await chats.startChat('Recent question');
    await openAssistantSettings(tester);
    int keepChatsDays() => tester
        .element(find.byType(AssistantSettingsScreen))
        .read<SettingsController>()
        .settings
        .keepChatsDays;

    Future<void> choose(String days) async {
      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(days).last);
      await tester.pumpAndSettle();
    }

    // Keeping chats for longer deletes nothing, so nothing is asked.
    await choose('30 days');
    expect(find.byType(AlertDialog), findsNothing);
    expect(keepChatsDays(), 30);

    // Keeping them for less than the old chat's age asks first.
    await choose('7 days');
    expect(find.text('Keep chats for 7 days?'), findsOneWidget);
    expect(
      find.textContaining('1 chat hasn\'t had a new message'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(keepChatsDays(), 30);
    expect(chats.chats, hasLength(2));

    await choose('7 days');
    await tester.tap(find.text('Delete and change'));
    await tester.pumpAndSettle();
    expect(keepChatsDays(), 7);
    expect(chats.chatById('old'), isNull);
    expect(chats.chats, hasLength(1));
  });

  testWidgets('all chats can be deleted from the Assistant settings', (
    tester,
  ) async {
    await pumpApp(tester);
    final chats = tester
        .element(find.byType(HomeShell))
        .read<AssistChatController>();
    final pinned = await chats.startChat('Pinned question');
    await chats.setPinned([pinned], true);
    await chats.startChat('Other question');
    await openAssistantSettings(tester);

    expect(find.text('Technical level'), findsOneWidget);
    await tester.tap(find.text('Delete chats'));
    await tester.pumpAndSettle();
    expect(find.textContaining('including pinned ones'), findsOneWidget);

    // Cancelling keeps them.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(chats.chats, hasLength(2));

    await tester.tap(find.text('Delete chats'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete chats'));
    await tester.pumpAndSettle();
    expect(chats.chats, isEmpty);
    expect(
      tester
          .widget<ListTile>(find.widgetWithText(ListTile, 'Delete chats'))
          .enabled,
      isFalse,
    );
  });

  testWidgets('the Assist tab explains when the assistant is not set up', (
    tester,
  ) async {
    await pumpApp(tester, assistant: FakeAssistantClient(isConfigured: false));
    await tester.tap(find.text('Assist'));
    await tester.pumpAndSettle();

    final newConversation = find.ancestor(
      of: find.text('New conversation'),
      matching: find.bySubtype<ButtonStyleButton>(),
    );
    expect(tester.widget<ButtonStyleButton>(newConversation).enabled, isFalse);
    expect(
      find.text('The assistant is currently unavailable.'),
      findsOneWidget,
    );

    // A chat saved earlier can still be read, with a note in place of the
    // text field explaining why there is nowhere to type.
    await tester
        .element(find.byType(HomeShell))
        .read<AssistChatController>()
        .startChat('Why is my sink slow?');
    await tester.tap(find.text('Continue conversation'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, todaysChat()));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, todaysChat()), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(
      find.text('The assistant is currently unavailable.'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('the Assist tab asks what the user would like to do', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('Assist'));
    await tester.pumpAndSettle();
    expect(find.text('What would you like to do today?'), findsOneWidget);

    await tester.tap(find.text('New conversation'));
    await tester.pumpAndSettle();
    expect(find.text('Ask about home maintenance'), findsOneWidget);
    expect(find.byTooltip('Chat history'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue conversation'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Chat history'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Search nearby services'));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(AppBar, 'Search nearby services'),
      findsOneWidget,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('What would you like to do today?'), findsOneWidget);
  });

  testWidgets('on phones, the overview is a round button above the bar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 900) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpApp(tester);

    final button = find.byTooltip('Overview');
    final bar = find.byType(NavigationBar);
    // Centered across the bar, sticking out a little above it.
    expect(tester.getCenter(button).dx, tester.getCenter(bar).dx);
    expect(tester.getTopLeft(button).dy, lessThan(tester.getTopLeft(bar).dy));
    expect(
      tester.getBottomLeft(button).dy,
      greaterThan(tester.getTopLeft(bar).dy),
    );

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    // The part above the bar can be tapped too.
    await tester.tapAt(tester.getTopLeft(button) + const Offset(32, 4));
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationBar>(bar).selectedIndex, 2);
  });

  testWidgets('settings are listed in one card, with Assistant above Privacy', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    final titles = [
      'Notifications',
      'Calendar sync',
      'Appearance',
      'Assistant',
      'Privacy',
    ];
    final tops = [
      for (final title in titles)
        tester
            .getTopLeft(
              find.descendant(
                of: find.byType(Card),
                matching: find.text(title),
              ),
            )
            .dy,
    ];
    expect(tops, orderedEquals([...tops]..sort()));
    expect(find.byType(Card), findsOneWidget);
    // Just the category names, without a summary under each.
    for (final title in titles) {
      expect(
        tester.widget<ListTile>(find.widgetWithText(ListTile, title)).subtitle,
        isNull,
      );
    }

    await tester.tap(find.text('Assistant'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Assistant'), findsOneWidget);
  });

  testWidgets('changing the calendar view leaves the open calendar alone', (
    tester,
  ) async {
    final calendarTitle = find.descendant(
      of: find.byTooltip('Show week, month or year'),
      matching: find.byType(Text),
    );
    // A week's title names its first and last days, such as "Nov 1 – 7".
    bool showsWeek() =>
        tester.widget<Text>(calendarTitle.first).data!.contains(' – ');

    await pumpApp(tester);
    expect(find.text('Recently Completed'), findsOneWidget);
    expect(find.text('Spent This Month'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<CalendarPeriod>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Week').last);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Spending is still counted by the month, like a budget.
    await tester.tap(find.byTooltip('Overview'));
    await tester.pumpAndSettle();
    expect(find.text('Spent This Month'), findsOneWidget);

    // The calendar that's already open keeps showing a month.
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    expect(showsWeek(), isFalse);
  });

  testWidgets('the calendar starts on the view saved in settings', (
    tester,
  ) async {
    await pumpApp(
      tester,
      savedData: {
        'settings_v1': jsonEncode(
          const AppSettings(calendarPeriod: CalendarPeriod.week).toJson(),
        ),
      },
    );
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();

    // A week's title names its first and last days, such as "Nov 1 – 7".
    final calendarTitle = find.descendant(
      of: find.byTooltip('Show week, month or year'),
      matching: find.byType(Text),
    );
    expect(tester.widget<Text>(calendarTitle.first).data, contains(' – '));
  });

  testWidgets('your data can be saved to a file or shared', (tester) async {
    final export = FakeDataExportService();
    await pumpApp(tester, export: export);
    await addTasks(tester, []);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Privacy'));
    await tester.pumpAndSettle();

    // The data buttons are in one line, each with a one-word label.
    final labels = [
      for (final label in ['Save', 'Load', 'Share', 'Delete'])
        tester.getCenter(find.text(label)),
    ];
    for (var i = 1; i < labels.length; i++) {
      expect(labels[i].dy, labels[0].dy);
      expect(labels[i].dx, greaterThan(labels[i - 1].dx));
    }

    final today = DateTime.now();
    final fileName =
        'hometrackhub-data-${today.year}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}.json';

    // Cancelling the save dialog changes nothing.
    export.saveAnswer = false;
    await tester.tap(find.byTooltip('Save my data'));
    await tester.pumpAndSettle();
    expect(export.saved, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);

    export.saveAnswer = true;
    await tester.tap(find.byTooltip('Save my data'));
    await tester.pumpAndSettle();
    expect(find.text('Data saved'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final (savedName, savedJson) = export.saved.single;
    expect(savedName, fileName);
    final data = jsonDecode(savedJson) as Map<String, dynamic>;
    expect(data.keys, containsAll(['settings', 'homeItems', 'assistChats']));
    expect((data['homeItems'] as List).single['name'], 'House');

    // Saving can fail, and says so.
    export.saveAnswer = Exception('Disk full');
    await tester.tap(find.byTooltip('Save my data'));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't save your data"), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // Sharing explains what it sends, and sends the same file.
    await tester.tap(find.byTooltip('Share my data'));
    await tester.pumpAndSettle();
    final (sharedName, sharedJson) = export.shared.single;
    expect(sharedName, fileName);
    // The same data, apart from when it was exported.
    final sharedData = jsonDecode(sharedJson) as Map<String, dynamic>;
    expect(sharedData['homeItems'], data['homeItems']);
    expect(sharedData['settings'], data['settings']);
  });

  testWidgets('serial numbers stay hidden and locked unless Privacy settings '
      'say not to', (tester) async {
    final serialField = find.descendant(
      of: find.widgetWithText(InlineTextRow, 'Serial #'),
      matching: find.byType(TextField),
    );
    TextField field() => tester.widget<TextField>(serialField);

    Future<void> openNewRefrigerator() async {
      await tester.tap(find.text('My Home'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add home item'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Appliances'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Refrigerator'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
    }

    Future<void> leaveForm() async {
      while (find.byTooltip('Back').evaluate().isNotEmpty) {
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
    }

    await pumpApp(tester);

    // While adding an item, its serial number is shown so it can be checked
    // as it's typed, even with the setting on. There's no eye or help.
    await openNewRefrigerator();
    expect(field().obscureText, isFalse);
    expect(field().readOnly, isFalse);
    expect(find.byTooltip('Show Serial #'), findsNothing);
    expect(find.byTooltip('Hide Serial #'), findsNothing);
    expect(find.byTooltip('About Serial #'), findsNothing);
    await tester.enterText(serialField, 'SN123');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    // Once saved, it can't be changed. A help button says why.
    await openHomeItem(tester, 'Refrigerator');
    expect(field().obscureText, isTrue);
    expect(field().readOnly, isTrue);
    expect(find.byTooltip('Show Serial #'), findsNothing);
    await tester.tap(find.byTooltip('About Serial #'));
    await tester.pumpAndSettle();
    expect(find.text('Hidden serial number'), findsOneWidget);
    expect(find.textContaining('Settings > Privacy'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Hidden serial number'), findsNothing);
    await leaveForm();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Privacy'));
    await tester.pumpAndSettle();
    final setting = find.widgetWithText(SwitchListTile, 'Hide serial numbers');
    expect(tester.widget<SwitchListTile>(setting).value, isTrue);
    await tester.tap(setting);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Now it's shown and can be changed, with an eye beside its label
    // instead of the help button.
    await tester.tap(find.text('My Home'));
    await tester.pumpAndSettle();
    await openHomeItem(tester, 'Refrigerator');
    expect(field().obscureText, isFalse);
    expect(field().readOnly, isFalse);
    expect(find.byTooltip('About Serial #'), findsNothing);
    expect(
      tester.getCenter(find.byTooltip('Hide Serial #')).dx,
      lessThan(tester.getCenter(serialField).dx),
    );

    // Hiding it with the eye locks it again.
    await tester.tap(find.byTooltip('Hide Serial #'));
    await tester.pumpAndSettle();
    expect(field().obscureText, isTrue);
    expect(field().readOnly, isTrue);
  });

  testWidgets('saved data can be loaded back from a file', (tester) async {
    final export = FakeDataExportService();
    await pumpApp(tester, export: export);
    await addTasks(tester, []);
    final shell = tester.element(find.byType(HomeShell));
    final homeItems = shell.read<HomeItemController>();
    final settings = shell.read<SettingsController>();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Privacy'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Save my data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final (savedName, savedJson) = export.saved.single;

    /// Picks [contents] as the file to load and taps Load my data.
    Future<void> load(String contents, {String name = 'data.json'}) async {
      export.openAnswer = (name: name, contents: contents);
      await tester.tap(find.byTooltip('Load my data'));
      await tester.pumpAndSettle();
    }

    // Files this version can't read are turned away with a popup saying
    // why, changing nothing.
    await load('Shopping list', name: 'list.txt');
    expect(find.text("Can't load this file"), findsOneWidget);
    expect(
      find.textContaining('incompatible with HomeTrackHub'),
      findsOneWidget,
    );
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    final fromNewerVersion = jsonDecode(savedJson) as Map<String, dynamic>
      ..['version'] = 2;
    await load(jsonEncode(fromNewerVersion));
    expect(find.textContaining('incompatible version'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // Change things after saving, to see them replaced.
    await homeItems.addHomeItem(
      HomeItem(
        id: 'garage',
        name: 'Garage door',
        category: HomeItemCategory.custom,
      ),
    );
    await settings.update(settings.settings.copyWith(hideSerialNumbers: false));
    await tester.pumpAndSettle();

    // A calendar picked on another device isn't brought along.
    final fromOtherDevice = jsonDecode(savedJson) as Map<String, dynamic>;
    (fromOtherDevice['settings'] as Map<String, dynamic>)
      ..['calendarSyncEnabled'] = true
      ..['syncCalendarId'] = 'other-device-calendar';

    // Loading warns that it replaces everything, and can be cancelled.
    await load(jsonEncode(fromOtherDevice), name: savedName);
    expect(find.text('Confirm import'), findsOneWidget);
    expect(find.textContaining('will be lost'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(homeItems.homeItems, hasLength(2));

    await tester.tap(find.byTooltip('Load my data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Data loaded'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(homeItems.homeItems.map((item) => item.name), ['House']);
    expect(settings.settings.hideSerialNumbers, isTrue);
    expect(settings.settings.calendarSyncEnabled, isFalse);
    expect(settings.settings.syncCalendarId, isNull);

    // Deleting everything says so in a popup too.
    await tester.tap(find.byTooltip('Delete all my data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete everything'));
    await tester.pumpAndSettle();
    expect(find.text('Data deleted'), findsOneWidget);
    expect(homeItems.homeItems, isEmpty);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('dark mode can be selected in settings', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<ThemeMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark').last);
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
  });

  group('launch screen', () {
    final logo = find.image(LaunchScreen.logo);
    final mainScreen = find.byType(DashboardScreen);

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
