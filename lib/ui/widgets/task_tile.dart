import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/equipment_task.dart';
import '../../state/equipment_controller.dart';
import '../../utils/date_utils.dart';

/// A list row for one maintenance task showing how often it repeats, when it
/// is due, and a button to mark it done.
class TaskTile extends StatelessWidget {
  const TaskTile({
    super.key,
    required this.item,
    this.showEquipmentName = true,
    this.onTap,
  });

  final EquipmentTask item;

  /// Whether to include the equipment's name. Hidden on the equipment's own
  /// page, where it would be repeated on every row.
  final bool showEquipmentName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final task = item.task;
    final today = dateOnly(DateTime.now());
    final daysUntilDue = calendarDaysBetween(today, item.dueDate);
    final colors = Theme.of(context).colorScheme;
    final dueColor = daysUntilDue < 0
        ? colors.error
        : daysUntilDue <= 7
        ? colors.tertiary
        : colors.onSurfaceVariant;

    final details = [
      if (showEquipmentName) item.equipment.name,
      task.interval.label,
      if (!task.remindersEnabled) 'Reminders off',
    ].join(' · ');

    return ListTile(
      onTap: onTap,
      title: Text(task.title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(details),
          Text(
            '${describeDueDate(item.dueDate, today)} '
            '(${MaterialLocalizations.of(context).formatMediumDate(item.dueDate)})',
            style: TextStyle(color: dueColor),
          ),
        ],
      ),
      isThreeLine: true,
      trailing: IconButton(
        icon: const Icon(Icons.check_circle_outline),
        tooltip: 'Mark done today',
        onPressed: () => markTaskDoneWithUndo(context, item),
      ),
    );
  }
}

/// Marks [item] as done today and shows a message with an Undo button.
Future<void> markTaskDoneWithUndo(
  BuildContext context,
  EquipmentTask item,
) async {
  final controller = context.read<EquipmentController>();
  final messenger = ScaffoldMessenger.of(context);
  final previousTask = item.task;

  await controller.markTaskDone(
    item.equipment.id,
    item.task,
    completedOn: dateOnly(DateTime.now()),
  );

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('Marked "${previousTask.title}" as done'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => controller.saveTask(item.equipment.id, previousTask),
        ),
      ),
    );
}
