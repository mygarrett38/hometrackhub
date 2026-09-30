import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometrackhub/data/home_item_catalog.dart';
import 'package:hometrackhub/data/home_item_repository.dart';
import 'package:hometrackhub/models/home_item.dart';
import 'package:hometrackhub/models/home_item_category.dart';
import 'package:hometrackhub/state/home_item_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });

  HomeItemController createController() =>
      HomeItemController(HomeItemRepository(preferences));

  HomeItem dishwasher() => HomeItem(
    id: 'dishwasher',
    name: 'Dishwasher',
    category: HomeItemCategory.appliance,
    catalogTypeId: 'dishwasher',
    tasks: findHomeItemType('dishwasher')!
        .createTasks(startDate: DateTime(2026, 1, 1)),
  );

  test('saved home items are loaded again on the next launch', () async {
    await createController().addHomeItem(dishwasher());

    final reloaded = createController();

    expect(reloaded.homeItems.single.name, 'Dishwasher');
    expect(reloaded.homeItems.single.tasks, isNotEmpty);
  });

  test('marking a task done moves its due date forward', () async {
    final controller = createController();
    await controller.addHomeItem(dishwasher());
    final task = controller.homeItems.single.tasks.first;

    await controller.markTaskDone(
      'dishwasher',
      task,
      completedOn: DateTime(2026, 3, 5),
    );

    final updated = controller.homeItems.single.tasks.first;
    expect(updated.lastCompleted, DateTime(2026, 3, 5));
    expect(updated.nextDueDate, task.interval.addTo(DateTime(2026, 3, 5)));
  });

  test('allTasks lists the soonest due task first', () async {
    final controller = createController();
    await controller.addHomeItem(dishwasher());

    final dueDates = controller.allTasks.map((item) => item.dueDate).toList();

    expect(dueDates, orderedEquals([...dueDates]..sort()));
  });

  test('deleteAll removes stored home items', () async {
    final controller = createController();
    await controller.addHomeItem(dishwasher());

    await controller.deleteAll();

    expect(controller.homeItems, isEmpty);
    expect(createController().homeItems, isEmpty);
  });

  test('items saved before the rename to home items still load', () async {
    final oldItem = dishwasher().toJson();
    SharedPreferences.setMockInitialValues({
      'equipment_v1': jsonEncode([oldItem]),
    });
    preferences = await SharedPreferences.getInstance();

    expect(createController().homeItems.single.name, 'Dishwasher');
  });
}
