import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/home_item_task.dart';
import '../../state/home_item_controller.dart';
import '../../utils/date_utils.dart';

/// A list row for one maintenance task showing how often it repeats, when it
/// is due, and a button to mark it done (or to delete it, see [onDelete]).
class TaskTile extends StatelessWidget {
  const TaskTile({
    super.key,
    required this.item,
    this.showHomeItemName = true,
    this.completedOn,
    this.onTap,
    this.onDelete,
  });

  final HomeItemTask item;

  /// Whether to include the home item's name. Hidden on the home item's own
  /// page, where it would be repeated on every row.
  final bool showHomeItemName;

  /// The completion this row stands for, in a list of completed tasks. The
  /// row is shown checked even if the task wasn't done today. Only the
  /// task's latest completion can be undone, so the check can't be tapped
  /// for an earlier one.
  final DateTime? completedOn;
  final VoidCallback? onTap;

  /// When set, the row has a delete button in place of the done button.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final task = item.task;
    final today = dateOnly(DateTime.now());
    final lastCompleted = task.lastCompleted;
    final completedToday =
        lastCompleted != null && dateOnly(lastCompleted) == today;
    final completedOn = this.completedOn;
    final checked = completedOn != null || completedToday;
    final canToggle =
        completedOn == null ||
        (lastCompleted != null &&
            dateOnly(lastCompleted) == dateOnly(completedOn));
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
      // Lines the done button's icon up with the left edge of the headings
      // above the list.
      contentPadding: const EdgeInsets.only(left: 4, right: 16),
      horizontalTitleGap: 4,
      leading: onDelete != null
          ? IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete task',
              onPressed: onDelete,
            )
          : Semantics(
              checked: checked,
              child: canToggle
                  ? IconButton(
                      icon: Icon(
                        checked
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                      ),
                      tooltip: !checked
                          ? 'Mark done today'
                          : completedToday
                          ? 'Unmark done today'
                          : 'Unmark done',
                      onPressed: () =>
                          markTaskDoneWithUndo(context, item, isDone: checked),
                    )
                  // Same size as the button, so the row lines up with the others.
                  : const SizedBox.square(
                      dimension: 48,
                      child: Icon(Icons.check_circle),
                    ),
            ),
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
    );
  }
}

/// Toggles today's completion and shows a message with an Undo button.
///
/// Pass [isDone] to say whether the row shows the task as done. When true,
/// the task's latest completion is undone, even if it wasn't today.
Future<void> markTaskDoneWithUndo(
  BuildContext context,
  HomeItemTask item, {
  bool? isDone,
}) async {
  final controller = context.read<HomeItemController>();
  final messenger = ScaffoldMessenger.of(context);
  final previousTask = item.task;
  final today = dateOnly(DateTime.now());
  final completedToday =
      isDone ??
      (previousTask.lastCompleted != null &&
          dateOnly(previousTask.lastCompleted!) == today);

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
  messenger.hideCurrentSnackBar();
  final snackBar = messenger.showSnackBar(
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

  // Keep Undo available briefly while the task returns to its list position.
  var closed = false;
  snackBar.closed.then((_) => closed = true);
  Future.delayed(HomeItemController.doneTaskMoveDelay, () {
    if (!closed) snackBar.close();
  });
}
