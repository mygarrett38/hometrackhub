import 'package:flutter/foundation.dart';

import 'equipment.dart';
import 'maintenance_task.dart';

/// A maintenance task paired with the equipment it belongs to. Used by lists
/// that show tasks from many pieces of equipment together.
@immutable
class EquipmentTask {
  const EquipmentTask(this.equipment, this.task);

  final Equipment equipment;
  final MaintenanceTask task;

  DateTime get dueDate => task.nextDueDate;
}
