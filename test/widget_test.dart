import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometrackhub/app.dart';
import 'package:hometrackhub/data/home_item_repository.dart';
import 'package:hometrackhub/data/settings_repository.dart';
import 'package:hometrackhub/services/device_discovery_service.dart';
import 'package:hometrackhub/services/notification_service.dart';
import 'package:hometrackhub/services/reminder_planner.dart';
import 'package:hometrackhub/state/home_item_controller.dart';
import 'package:hometrackhub/state/settings_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}

class FakeDiscoveryService implements DeviceDiscoveryService {
  @override
  Future<bool> isConnectedToLocalNetwork() async => true;

  @override
  Stream<DiscoveredDevice> scan({Duration duration = Duration.zero}) {
    return Stream.value(
      const DiscoveredDevice(
        id: 'mdns:living room tv',
        name: 'Living Room TV',
        kind: 'Google Cast device',
        suggestedTypeId: 'smart_tv',
      ),
    );
  }
}

Future<void> pumpApp(WidgetTester tester) async {
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
        Provider<NotificationService>.value(value: FakeNotificationService()),
        Provider<DeviceDiscoveryService>.value(value: FakeDiscoveryService()),
      ],
      child: const HomeTrackHubApp(),
    ),
  );
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
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // The detail screen lists the manufacturer-recommended tasks.
    expect(find.text('Replace water filter'), findsOneWidget);
    expect(find.text('Clean condenser coils'), findsOneWidget);

    // Going back skips the pickers and returns to the list of home items.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Refrigerator'), findsOneWidget);
    expect(find.byTooltip('Add home item'), findsOneWidget);

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
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Install software updates'), findsOneWidget);
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

    // A custom home item started here is already in the Vehicles category.
    await tester.tap(find.text('Not listed? Create custom home item'));
    await tester.pumpAndSettle();
    expect(find.text('Vehicles'), findsOneWidget);
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

    await tester.tap(find.text('Replace water filter'));
    await tester.pumpAndSettle();
    // The form's list is the outermost scrollable; text fields have their own.
    await tester.scrollUntilVisible(
      find.textContaining('Next reminder'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('On the due date'), findsOneWidget);

    await tester.tap(find.text('Remind me about this task'));
    await tester.pumpAndSettle();
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
    expect(find.text('Overview time'), findsNothing);

    await tester.tap(find.text('Weekly'));
    await tester.pumpAndSettle();
    expect(find.text('Monday'), findsOneWidget);
    expect(find.text('Overview time'), findsOneWidget);

    await tester.tap(find.text('Monthly'));
    await tester.pumpAndSettle();
    expect(find.text('1st of each month'), findsOneWidget);
  });

  testWidgets('dark mode can be selected in settings', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
  });
}
