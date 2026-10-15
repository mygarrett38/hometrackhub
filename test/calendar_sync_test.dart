import 'package:flutter_test/flutter_test.dart';
import 'package:hometrackhub/data/calendar_event_repository.dart';
import 'package:hometrackhub/data/home_item_repository.dart';
import 'package:hometrackhub/data/settings_repository.dart';
import 'package:hometrackhub/models/home_item.dart';
import 'package:hometrackhub/models/home_item_category.dart';
import 'package:hometrackhub/models/maintenance_interval.dart';
import 'package:hometrackhub/models/maintenance_task.dart';
import 'package:hometrackhub/services/calendar_service.dart';
import 'package:hometrackhub/state/calendar_sync.dart';
import 'package:hometrackhub/state/home_item_controller.dart';
import 'package:hometrackhub/state/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A calendar event held by [FakeCalendarService].
typedef FakeEvent = ({String calendarId, CalendarEventDetails details});

/// Keeps events in memory instead of on the device's calendars.
class FakeCalendarService implements CalendarService {
  FakeCalendarService({
    this.calendars = const [
      UserCalendar(id: 'personal', name: 'Personal', isPrimary: true),
      UserCalendar(id: 'work', name: 'Work'),
    ],
  });

  bool accessAllowed = true;
  List<UserCalendar> calendars;
  final events = <String, FakeEvent>{};
  int writes = 0;
  int openSettingsCalls = 0;
  var _nextId = 0;

  @override
  Future<bool> hasAccess() async => accessAllowed;

  @override
  Future<bool> requestAccess() async => accessAllowed;

  @override
  Future<void> openAppSettings() async => openSettingsCalls++;

  @override
  Future<List<UserCalendar>> listWritableCalendars() async => calendars;

  @override
  Future<String> createEvent(
    String calendarId,
    CalendarEventDetails details,
  ) async {
    writes++;
    final id = 'event${_nextId++}';
    events[id] = (calendarId: calendarId, details: details);
    return id;
  }

  @override
  Future<bool> updateEvent(String eventId, CalendarEventDetails details) async {
    writes++;
    final event = events[eventId];
    if (event == null) return false;
    events[eventId] = (calendarId: event.calendarId, details: details);
    return true;
  }

  @override
  Future<void> deleteEvent(String eventId) async {
    writes++;
    events.remove(eventId);
  }
}

void main() {
  late HomeItemController homeItems;
  late SettingsController settings;
  late FakeCalendarService calendar;
  late CalendarSync calendarSync;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    homeItems = HomeItemController(HomeItemRepository(preferences));
    settings = SettingsController(SettingsRepository(preferences));
    calendar = FakeCalendarService();
    // Not started, so each test decides when to sync.
    calendarSync = CalendarSync(
      homeItems: homeItems,
      settings: settings,
      calendar: calendar,
      repository: CalendarEventRepository(preferences),
    );
  });

  MaintenanceTask task(String id, {required DateTime startDate}) =>
      MaintenanceTask(
        id: id,
        title: id,
        interval: const MaintenanceInterval.months(1),
        startDate: startDate,
      );

  final furnace = HomeItem(
    id: 'furnace',
    name: 'Furnace',
    category: HomeItemCategory.hvac,
    tasks: [
      task('Replace filter', startDate: DateTime(2026, 5, 20)),
      task('Clean vents', startDate: DateTime(2026, 5, 25)),
    ],
  );

  Future<void> turnOn({String calendarId = 'personal'}) => settings.update(
    settings.settings.copyWith(
      calendarSyncEnabled: true,
      syncCalendarId: calendarId,
      syncCalendarName: calendarId,
    ),
  );

  FakeEvent eventTitled(String title) =>
      calendar.events.values.singleWhere((e) => e.details.title == title);

  test('each task is added on its due date once sync is on', () async {
    await homeItems.addHomeItem(furnace);
    await calendarSync.sync();
    expect(calendar.events, isEmpty);

    await turnOn();
    await calendarSync.sync();

    expect(calendar.events, hasLength(2));
    final filter = eventTitled('Furnace: Replace filter');
    expect(filter.calendarId, 'personal');
    expect(filter.details.date, DateTime(2026, 6, 20));
    expect(
      eventTitled('Furnace: Clean vents').details.date,
      DateTime(2026, 6, 25),
    );
  });

  test('completing a task moves its event to the next due date', () async {
    await homeItems.addHomeItem(furnace);
    await turnOn();
    await calendarSync.sync();
    final eventIds = calendar.events.keys.toSet();
    calendar.writes = 0;

    await homeItems.markTaskDone(
      'furnace',
      furnace.tasks.first,
      completedOn: DateTime(2026, 6, 18),
    );
    await calendarSync.sync();

    // The same event is moved, and the unchanged task isn't written again.
    expect(calendar.events.keys.toSet(), eventIds);
    expect(
      eventTitled('Furnace: Replace filter').details.date,
      DateTime(2026, 7, 18),
    );
    expect(calendar.writes, 1);
  });

  test('deleting a task or home item removes its events', () async {
    await homeItems.addHomeItem(furnace);
    await turnOn();
    await calendarSync.sync();

    await homeItems.deleteTask('furnace', 'Clean vents');
    await calendarSync.sync();
    expect(calendar.events.values.map((e) => e.details.title), [
      'Furnace: Replace filter',
    ]);

    await homeItems.deleteHomeItem('furnace');
    await calendarSync.sync();
    expect(calendar.events, isEmpty);
  });

  test('turning sync off removes the events', () async {
    await homeItems.addHomeItem(furnace);
    await turnOn();
    await calendarSync.sync();

    await settings.update(
      settings.settings.copyWith(calendarSyncEnabled: false),
    );
    await calendarSync.sync();

    expect(calendar.events, isEmpty);
  });

  test('choosing another calendar moves the events there', () async {
    await homeItems.addHomeItem(furnace);
    await turnOn();
    await calendarSync.sync();

    await turnOn(calendarId: 'work');
    await calendarSync.sync();

    expect(calendar.events, hasLength(2));
    expect(
      calendar.events.values.map((e) => e.calendarId),
      everyElement('work'),
    );
  });

  test('an event deleted in the calendar app is added again when its task '
      'changes', () async {
    await homeItems.addHomeItem(furnace);
    await turnOn();
    await calendarSync.sync();
    calendar.events.removeWhere(
      (_, e) => e.details.title == 'Furnace: Replace filter',
    );

    await homeItems.markTaskDone(
      'furnace',
      furnace.tasks.first,
      completedOn: DateTime(2026, 6, 18),
    );
    await calendarSync.sync();

    expect(
      eventTitled('Furnace: Replace filter').details.date,
      DateTime(2026, 7, 18),
    );
  });

  test('nothing is written without calendar access', () async {
    calendar.accessAllowed = false;
    await homeItems.addHomeItem(furnace);
    await turnOn();

    await calendarSync.sync();

    expect(calendar.writes, 0);
  });

  test('events are remembered after the app restarts', () async {
    await homeItems.addHomeItem(furnace);
    await turnOn();
    await calendarSync.sync();

    final preferences = await SharedPreferences.getInstance();
    final restarted = CalendarSync(
      homeItems: HomeItemController(HomeItemRepository(preferences)),
      settings: SettingsController(SettingsRepository(preferences)),
      calendar: calendar,
      repository: CalendarEventRepository(preferences),
    );
    calendar.writes = 0;
    await restarted.sync();

    expect(calendar.writes, 0);
    expect(calendar.events, hasLength(2));
  });
}
