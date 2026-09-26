import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometrackhub/app.dart';
import 'package:hometrackhub/data/equipment_repository.dart';
import 'package:hometrackhub/data/settings_repository.dart';
import 'package:hometrackhub/services/device_discovery_service.dart';
import 'package:hometrackhub/services/notification_service.dart';
import 'package:hometrackhub/services/reminder_planner.dart';
import 'package:hometrackhub/state/equipment_controller.dart';
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
          create: (_) => EquipmentController(EquipmentRepository(preferences)),
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
  testWidgets('adding equipment from the catalog schedules its maintenance', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.textContaining('No maintenance scheduled yet'), findsOneWidget);

    await tester.tap(find.text('Equipment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add equipment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose a common type'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'refrig');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refrigerator'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // The detail screen lists the manufacturer-recommended tasks.
    expect(find.text('Replace water filter'), findsOneWidget);
    expect(find.text('Clean condenser coils'), findsOneWidget);

    // The tasks also appear on the Upcoming tab.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upcoming'));
    await tester.pumpAndSettle();
    expect(find.text('Clean door gaskets'), findsOneWidget);
  });

  testWidgets('network scan results can be added as equipment', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Equipment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add equipment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Find smart devices on my network'));
    await tester.pumpAndSettle();

    expect(find.text('Living Room TV'), findsOneWidget);
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Install software updates'), findsOneWidget);
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
