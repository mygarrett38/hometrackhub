import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/home_item_task.dart';
import '../../state/home_item_controller.dart';
import '../screens/home_items/task_form_screen.dart';
import 'task_tile.dart';

/// A card listing a group of tasks, such as the overdue ones, under a
/// heading with how many there are. The card has a light wash of [accent],
/// the color of the matching Overview card.
///
/// Each row says when its task is due or was done, can be checked off, and
/// opens the task when tapped (unless [opensTasks] is false). After a task
/// is checked off, the heading can show [doneChange] with a button to undo
/// it.
class TaskSectionCard extends StatelessWidget {
  const TaskSectionCard({
    super.key,
    required this.title,
    required this.items,
    required this.accent,
    this.dueOn = const {},
    this.completedOn = const {},
    this.opensTasks = true,
    this.doneChange,
    this.onDoneChanged,
    this.onUndo,
    this.padding = const EdgeInsets.fromLTRB(12, 8, 12, 0),
    this.flash,
  });

  final String title;
  final List<HomeItemTask> items;
  final Color accent;

  /// The due date each row stands for, when it isn't the task's next one.
  final Map<HomeItemTask, DateTime> dueOn;

  /// The completion each row stands for, in a list of completed tasks.
  final Map<HomeItemTask, DateTime> completedOn;

  /// Whether tapping a row opens its task. Finished tasks are a record, so
  /// lists of them don't.
  final bool opensTasks;

  /// The task just checked off or unchecked, to show in the heading with an
  /// Undo button. `null` when there's nothing to show in this card.
  final TaskDoneChange? doneChange;
  final ValueChanged<TaskDoneChange>? onDoneChanged;
  final VoidCallback? onUndo;

  /// Space around the card. The default lines the card's edges up 16 from
  /// the edges of a list that has no padding of its own.
  final EdgeInsetsGeometry padding;

  /// Changing this to a new value flashes an outline in [accent] around the
  /// card once, to draw the eye to it, such as after it was picked out from
  /// elsewhere on the screen. `null` never flashes.
  final Object? flash;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final cardColor =
        theme.cardTheme.color ?? theme.colorScheme.surfaceContainerLow;
    final change = doneChange;

    // A card like the home item screen's maintenance tasks, with a light
    // wash of [accent]. At 12% every text color in the rows keeps a
    // contrast of at least 4.5:1.
    return Padding(
      padding: padding,
      child: _FlashingCard(
        flash: flash,
        outline: accent,
        color: Color.lerp(cardColor, accent, 0.12)!,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // A fixed height that fits the Undo button, so the card doesn't
            // change size when the note comes and goes.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
              child: SizedBox(
                height: 40,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$title (${items.length})',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    // Appears straight away, but fades out when it goes.
                    AnimatedSwitcher(
                      duration: Duration.zero,
                      reverseDuration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 250),
                      child: change != null && onUndo != null
                          ? DoneChangeNote(
                              // The same key for every note, so a new one
                              // replaces the last in place rather than
                              // showing through it as it fades.
                              key: const ValueKey('note'),
                              change: change,
                              onUndo: onUndo!,
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
            for (final item in items)
              TaskTile(
                item: item,
                // When it's due or was done matters more here than how
                // often it repeats.
                showInterval: false,
                dueDate: dueOn[item],
                completedOn: completedOn[item],
                showArrow: opensTasks,
                onDoneChanged: onDoneChanged,
                onTap: opensTasks
                    ? () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => TaskFormScreen(
                            homeItemId: item.homeItem.id,
                            homeItemName: item.homeItem.name,
                            existing: item.task,
                          ),
                        ),
                      )
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}

/// A [Card] that flashes an [outline] around itself once whenever [flash]
/// changes to a new value.
class _FlashingCard extends StatefulWidget {
  const _FlashingCard({
    required this.flash,
    required this.outline,
    required this.color,
    required this.child,
  });

  final Object? flash;
  final Color outline;
  final Color color;
  final Widget child;

  @override
  State<_FlashingCard> createState() => _FlashingCardState();
}

class _FlashingCardState extends State<_FlashingCard>
    with SingleTickerProviderStateMixin {
  /// How much of the outline shows: in quickly, held, then fading out.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final Animation<double> _opacity = TweenSequence([
    TweenSequenceItem(
      tween: Tween(
        begin: 0.0,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 15,
    ),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 35),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 0.0,
      ).chain(CurveTween(curve: Curves.easeIn)),
      weight: 50,
    ),
  ]).animate(_controller);

  @override
  void didUpdateWidget(_FlashingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.flash != null && widget.flash != oldWidget.flash) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacity,
      child: widget.child,
      builder: (context, child) => Card(
        color: widget.color,
        clipBehavior: Clip.antiAlias,
        // The same corners as other cards. The outline only changes how
        // the edge looks, so the rows' text stays as easy to read.
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: _opacity.value == 0
              ? BorderSide.none
              : BorderSide(
                  color: widget.outline.withValues(alpha: _opacity.value),
                  width: 2,
                ),
        ),
        child: child,
      ),
    );
  }
}

/// A short note that a task was just marked done or undone, with a button
/// to undo it, for the top right of the card the task is in.
class DoneChangeNote extends StatelessWidget {
  const DoneChangeNote({super.key, required this.change, required this.onUndo});

  final TaskDoneChange change;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      container: true,
      liveRegion: true,
      // A light tint of the usual dark message color, so it reads as a
      // message without standing out as much as a solid one.
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.inverseSurface.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                change.markedDone ? 'Marked as done' : 'Marked incomplete',
                // The card has no room for the task's name, but screen
                // readers still hear it.
                semanticsLabel: change.message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurface,
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: onUndo,
                child: const Text('Undo'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Keeps track of the task just checked off or unchecked on a screen of
/// [TaskSectionCard]s, so the card it's in can offer to undo it for a few
/// seconds.
mixin TaskDoneChangeUndo<T extends StatefulWidget> on State<T> {
  TaskDoneChange? _doneChange;
  Timer? _doneChangeTimer;

  /// The title of the card [_doneChange] was made in.
  String? _doneChangeSection;

  @override
  void dispose() {
    _doneChangeTimer?.cancel();
    super.dispose();
  }

  /// Shows [change] in the card titled [section].
  void showDoneChange(TaskDoneChange change, String section) {
    if (!mounted) return;
    setState(() {
      _doneChange = change;
      _doneChangeSection = section;
    });
    // Undo stays available while the task returns to its list position.
    _doneChangeTimer?.cancel();
    _doneChangeTimer = Timer(HomeItemController.doneTaskMoveDelay, () {
      if (mounted) setState(() => _doneChange = null);
    });
  }

  Future<void> undoDoneChange() async {
    final change = _doneChange;
    if (change == null) return;
    _doneChangeTimer?.cancel();
    setState(() => _doneChange = null);
    await change.undo();
  }

  /// The change to show in the card titled [section], out of [sections]:
  /// the card it was made in, or if the task has since left that card, the
  /// first one it's now in. `null` for every other card.
  TaskDoneChange? doneChangeFor(
    String section,
    Map<String, List<HomeItemTask>> sections,
  ) {
    final change = _doneChange;
    if (change == null) return null;
    bool listsTask(String title) =>
        sections[title]?.any((item) => item.task.id == change.taskId) ?? false;
    final shownIn = _doneChangeSection != null && listsTask(_doneChangeSection!)
        ? _doneChangeSection
        : sections.keys.where(listsTask).firstOrNull;
    return shownIn == section ? change : null;
  }
}
