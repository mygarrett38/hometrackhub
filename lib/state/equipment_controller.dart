import 'package:flutter/foundation.dart';

import '../data/equipment_repository.dart';
import '../models/equipment.dart';
import '../models/equipment_task.dart';
import '../models/maintenance_task.dart';

/// Holds the user's equipment and maintenance tasks, saves every change, and
/// notifies listening widgets so they can rebuild.
class EquipmentController extends ChangeNotifier {
  EquipmentController(this._repository) : _equipment = _repository.load();

  final EquipmentRepository _repository;
  List<Equipment> _equipment;

  /// All equipment, sorted by name.
  List<Equipment> get equipment {
    final sorted = [..._equipment]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return List.unmodifiable(sorted);
  }

  /// Every maintenance task across all equipment, soonest due first.
  List<EquipmentTask> get allTasks {
    final tasks = [
      for (final item in _equipment)
        for (final task in item.tasks) EquipmentTask(item, task),
    ]..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return List.unmodifiable(tasks);
  }

  /// Network ids of equipment that was added from the network scan.
  Set<String> get networkIds => {
    for (final item in _equipment)
      if (item.networkId != null) item.networkId!,
  };

  Equipment? findById(String id) {
    for (final item in _equipment) {
      if (item.id == id) return item;
    }
    return null;
  }

  Future<void> addEquipment(Equipment equipment) async {
    _equipment = [..._equipment, equipment];
    await _saveAndNotify();
  }

  Future<void> updateEquipment(Equipment equipment) async {
    _equipment = [
      for (final item in _equipment) item.id == equipment.id ? equipment : item,
    ];
    await _saveAndNotify();
  }

  Future<void> deleteEquipment(String equipmentId) async {
    _equipment = [
      for (final item in _equipment)
        if (item.id != equipmentId) item,
    ];
    await _saveAndNotify();
  }

  /// Adds [task] to the equipment, or replaces the task with the same id.
  Future<void> saveTask(String equipmentId, MaintenanceTask task) async {
    final equipment = findById(equipmentId);
    if (equipment == null) return;

    final exists = equipment.tasks.any((existing) => existing.id == task.id);
    final tasks = exists
        ? [
            for (final existing in equipment.tasks)
              existing.id == task.id ? task : existing,
          ]
        : [...equipment.tasks, task];
    await updateEquipment(equipment.copyWith(tasks: tasks));
  }

  Future<void> deleteTask(String equipmentId, String taskId) async {
    final equipment = findById(equipmentId);
    if (equipment == null) return;
    await updateEquipment(
      equipment.copyWith(
        tasks: [
          for (final task in equipment.tasks)
            if (task.id != taskId) task,
        ],
      ),
    );
  }

  /// Records that a task was done on [completedOn], which moves its next due
  /// date forward by one interval.
  Future<void> markTaskDone(
    String equipmentId,
    MaintenanceTask task, {
    required DateTime completedOn,
  }) {
    return saveTask(equipmentId, task.copyWith(lastCompleted: completedOn));
  }

  /// Deletes all equipment from the device.
  Future<void> deleteAll() async {
    _equipment = [];
    await _repository.deleteAll();
    notifyListeners();
  }

  Future<void> _saveAndNotify() async {
    notifyListeners();
    await _repository.save(_equipment);
  }
}
