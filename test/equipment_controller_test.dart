import 'package:flutter_test/flutter_test.dart';
import 'package:hometrackhub/data/equipment_catalog.dart';
import 'package:hometrackhub/data/equipment_repository.dart';
import 'package:hometrackhub/models/equipment.dart';
import 'package:hometrackhub/models/equipment_category.dart';
import 'package:hometrackhub/state/equipment_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });

  EquipmentController createController() =>
      EquipmentController(EquipmentRepository(preferences));

  Equipment dishwasher() => Equipment(
    id: 'dishwasher',
    name: 'Dishwasher',
    category: EquipmentCategory.appliance,
    catalogTypeId: 'dishwasher',
    tasks: findEquipmentType('dishwasher')!
        .createTasks(startDate: DateTime(2026, 1, 1)),
  );

  test('saved equipment is loaded again on the next launch', () async {
    await createController().addEquipment(dishwasher());

    final reloaded = createController();

    expect(reloaded.equipment.single.name, 'Dishwasher');
    expect(reloaded.equipment.single.tasks, isNotEmpty);
  });

  test('marking a task done moves its due date forward', () async {
    final controller = createController();
    await controller.addEquipment(dishwasher());
    final task = controller.equipment.single.tasks.first;

    await controller.markTaskDone(
      'dishwasher',
      task,
      completedOn: DateTime(2026, 3, 5),
    );

    final updated = controller.equipment.single.tasks.first;
    expect(updated.lastCompleted, DateTime(2026, 3, 5));
    expect(updated.nextDueDate, task.interval.addTo(DateTime(2026, 3, 5)));
  });

  test('allTasks lists the soonest due task first', () async {
    final controller = createController();
    await controller.addEquipment(dishwasher());

    final dueDates = controller.allTasks.map((item) => item.dueDate).toList();

    expect(dueDates, orderedEquals([...dueDates]..sort()));
  });

  test('deleteAll removes stored equipment', () async {
    final controller = createController();
    await controller.addEquipment(dishwasher());

    await controller.deleteAll();

    expect(controller.equipment, isEmpty);
    expect(createController().equipment, isEmpty);
  });
}
