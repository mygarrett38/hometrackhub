import 'package:flutter_test/flutter_test.dart';
import 'package:hometrackhub/data/equipment_catalog.dart';

void main() {
  test('every catalog id is unique', () {
    final ids = equipmentCatalog.map((type) => type.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
  });

  test('every catalog entry has at least one recommended task', () {
    for (final type in equipmentCatalog) {
      expect(type.tasks, isNotEmpty, reason: type.id);
    }
  });

  test('catalog types suggested by the network scan exist', () {
    // Keep in sync with device_discovery_service.dart.
    const suggestedIds = [
      'smart_device',
      'smart_tv',
      'smart_speaker',
      'smart_lighting',
      'smart_hub',
      'printer',
      'security_camera',
      'router',
    ];
    for (final id in suggestedIds) {
      expect(findEquipmentType(id), isNotNull, reason: id);
    }
  });

  test('created tasks start on the manufacturer recommendation', () {
    final type = findEquipmentType('refrigerator')!;
    final tasks = type.createTasks(startDate: DateTime(2026, 1, 1));

    expect(tasks, hasLength(type.tasks.length));
    for (final task in tasks) {
      expect(task.followsRecommendation, isTrue);
      expect(task.isCustom, isFalse);
    }
  });
}
