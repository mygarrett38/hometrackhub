import 'package:flutter/foundation.dart';

import '../data/home_item_repository.dart';
import '../models/home_item.dart';
import '../models/home_item_task.dart';
import '../models/maintenance_task.dart';

/// Holds the user's home items and maintenance tasks, saves every change, and
/// notifies listening widgets so they can rebuild.
class HomeItemController extends ChangeNotifier {
  HomeItemController(this._repository) : _homeItems = _repository.load();

  final HomeItemRepository _repository;
  List<HomeItem> _homeItems;

  /// All home items, sorted by name.
  List<HomeItem> get homeItems {
    final sorted = [..._homeItems]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return List.unmodifiable(sorted);
  }

  /// Every maintenance task across all home items, soonest due first.
  List<HomeItemTask> get allTasks {
    final tasks = [
      for (final item in _homeItems)
        for (final task in item.tasks) HomeItemTask(item, task),
    ]..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return List.unmodifiable(tasks);
  }

  // Whether there are no tasks running
  bool get hasNoTasks {
    return _homeItems.every((item) => item.tasks.isEmpty);
  }

  /// Network ids of home items that were added from the network scan.
  Set<String> get networkIds => {
    for (final item in _homeItems)
      if (item.networkId != null) item.networkId!,
  };

  HomeItem? findById(String id) {
    for (final item in _homeItems) {
      if (item.id == id) return item;
    }
    return null;
  }

  Future<void> addHomeItem(HomeItem homeItem) async {
    _homeItems = [..._homeItems, homeItem];
    await _saveAndNotify();
  }

  Future<void> updateHomeItem(HomeItem homeItem) async {
    _homeItems = [
      for (final item in _homeItems) item.id == homeItem.id ? homeItem : item,
    ];
    await _saveAndNotify();
  }

  Future<void> deleteHomeItem(String homeItemId) async {
    _homeItems = [
      for (final item in _homeItems)
        if (item.id != homeItemId) item,
    ];
    await _saveAndNotify();
  }

  /// Adds [task] to the home item, or replaces the task with the same id.
  Future<void> saveTask(String homeItemId, MaintenanceTask task) async {
    final homeItem = findById(homeItemId);
    if (homeItem == null) return;

    final exists = homeItem.tasks.any((existing) => existing.id == task.id);
    final tasks = exists
        ? [
            for (final existing in homeItem.tasks)
              existing.id == task.id ? task : existing,
          ]
        : [...homeItem.tasks, task];
    await updateHomeItem(homeItem.copyWith(tasks: tasks));
  }

  Future<void> deleteTask(String homeItemId, String taskId) async {
    final homeItem = findById(homeItemId);
    if (homeItem == null) return;
    await updateHomeItem(
      homeItem.copyWith(
        tasks: [
          for (final task in homeItem.tasks)
            if (task.id != taskId) task,
        ],
      ),
    );
  }

  /// Records that a task was done on [completedOn], which moves its next due
  /// date forward by one interval.
  Future<void> markTaskDone(
    String homeItemId,
    MaintenanceTask task, {
    required DateTime completedOn,
  }) {
    return saveTask(homeItemId, task.copyWith(lastCompleted: completedOn));
  }

  /// Deletes all home items from the device.
  Future<void> deleteAll() async {
    _homeItems = [];
    await _repository.deleteAll();
    notifyListeners();
  }

  Future<void> _saveAndNotify() async {
    notifyListeners();
    await _repository.save(_homeItems);
  }
}
