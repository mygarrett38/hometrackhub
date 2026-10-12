import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/home_item_repository.dart';
import '../models/home_item.dart';
import '../models/home_item_task.dart';
import '../models/maintenance_task.dart';

/// Holds the user's home items and maintenance tasks, saves every change, and
/// notifies listening widgets so they can rebuild.
class HomeItemController extends ChangeNotifier {
  HomeItemController(this._repository) : _homeItems = _repository.load();

  /// How long a task that was just marked done stays in place in task lists
  /// before it moves down with the other tasks done today.
  static const doneTaskMoveDelay = Duration(seconds: 3);

  final HomeItemRepository _repository;
  List<HomeItem> _homeItems;

  /// Timers for tasks marked done less than [doneTaskMoveDelay] ago, by
  /// task id.
  final Map<String, Timer> _justDoneTimers = {};

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

  /// Orders [tasks] for a task list: tasks still to do, soonest due first,
  /// followed by the tasks done today.
  ///
  /// A task marked done in the last [doneTaskMoveDelay] stays where it was
  /// until then, so it doesn't jump away as soon as the user taps it.
  List<HomeItemTask> orderForList(Iterable<HomeItemTask> tasks) {
    return [...tasks]..sort((a, b) {
      final aDone = isListedAsDone(a);
      if (aDone != isListedAsDone(b)) return aDone ? 1 : -1;
      return listDueDate(a).compareTo(listDueDate(b));
    });
  }

  /// Whether [item] belongs with the tasks done today at the bottom of a
  /// task list.
  bool isListedAsDone(HomeItemTask item) {
    return item.task.wasCompletedOn(DateTime.now()) &&
        !_justDoneTimers.containsKey(item.task.id);
  }

  /// The due date that places [item] in a task list. A task that was just
  /// marked done keeps the date it was due before, until it moves down.
  DateTime listDueDate(HomeItemTask item) {
    final justDone =
        _justDoneTimers.containsKey(item.task.id) &&
        item.task.wasCompletedOn(DateTime.now());
    return justDone ? item.task.previousDueDate : item.dueDate;
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
    _justDoneTimers.remove(task.id)?.cancel();
    _justDoneTimers[task.id] = Timer(doneTaskMoveDelay, () {
      _justDoneTimers.remove(task.id);
      notifyListeners();
    });
    return saveTask(
      homeItemId,
      task.copyWith(
        lastCompleted: completedOn,
        previousLastCompleted: task.lastCompleted,
        clearPreviousLastCompleted: task.lastCompleted == null,
      ),
    );
  }

  /// Undoes the latest completion and restores the previous maintenance date.
  Future<void> undoTaskDone(String homeItemId, MaintenanceTask task) {
    _justDoneTimers.remove(task.id)?.cancel();
    return saveTask(
      homeItemId,
      task.copyWith(
        lastCompleted: task.previousLastCompleted,
        clearLastCompleted: task.previousLastCompleted == null,
        clearPreviousLastCompleted: true,
      ),
    );
  }

  /// Deletes all home items from the device.
  Future<void> deleteAll() async {
    _homeItems = [];
    await _repository.deleteAll();
    notifyListeners();
  }

  @override
  void dispose() {
    for (final timer in _justDoneTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }

  Future<void> _saveAndNotify() async {
    notifyListeners();
    await _repository.save(_homeItems);
  }
}
