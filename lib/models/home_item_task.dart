import 'package:flutter/foundation.dart';

import 'home_item.dart';
import 'maintenance_task.dart';

/// A maintenance task paired with the home item it belongs to. Used by lists
/// that show tasks from many home items together.
@immutable
class HomeItemTask {
  const HomeItemTask(this.homeItem, this.task);

  final HomeItem homeItem;
  final MaintenanceTask task;

  DateTime get dueDate => task.nextDueDate;
}
