import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/home_item_task.dart';
import '../../state/home_item_controller.dart';
import '../../utils/date_utils.dart';

/// A list row for one maintenance task showing how often it repeats, when it
/// is due, and a button to mark it done.
class TaskTile extends StatelessWidget {
  const TaskTile({
    super.key,
    required this.item,
    this.showHomeItemName = true,
    this.onTap,
  });

  final HomeItemTask item;

  /// Whether to include the home item's name. Hidden on the home item's own
  /// page, where it would be repeated on every row.
  final bool showHomeItemName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final task = item.task;
    final today = dateOnly(DateTime.now());
    final completedToday =
        task.lastCompleted != null && dateOnly(task.lastCompleted!) == today;
    final daysUntilDue = calendarDaysBetween(today, item.dueDate);
    final colors = Theme.of(context).colorScheme;
    final dueColor = daysUntilDue < 0
        ? colors.error
        : daysUntilDue <= 7
        ? colors.tertiary
        : colors.onSurfaceVariant;

    final details = [
      if (showHomeItemName) item.homeItem.name,
      task.interval.label,
      if (!task.reminder.enabled) 'Reminder off',
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
      trailing: Semantics(
        checked: completedToday,
        child: IconButton(
          icon: Icon(
            completedToday ? Icons.check_circle : Icons.radio_button_unchecked,
          ),
          tooltip: completedToday ? 'Unmark done today' : 'Mark done today',
          onPressed: () => markTaskDoneWithUndo(context, item),
        ),
      ),
    );
  }
}

/// Toggles today's completion and shows a message with an Undo button.
Future<void> markTaskDoneWithUndo(
  BuildContext context,
  HomeItemTask item,
) async {
  final controller = context.read<HomeItemController>();
  final messenger = ScaffoldMessenger.of(context);
  final previousTask = item.task;
  final today = dateOnly(DateTime.now());
  final completedToday =
      previousTask.lastCompleted != null &&
      dateOnly(previousTask.lastCompleted!) == today;

  if (completedToday) {
    await controller.undoTaskDone(item.homeItem.id, previousTask);
  } else {
    await controller.markTaskDone(
      item.homeItem.id,
      previousTask,
      completedOn: today,
    );
  }

  if (!context.mounted) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          completedToday
              ? 'Unmarked "${previousTask.title}" as done'
              : 'Marked "${previousTask.title}" as done',
        ),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => controller.saveTask(item.homeItem.id, previousTask),
        ),
      ),
    );
}
