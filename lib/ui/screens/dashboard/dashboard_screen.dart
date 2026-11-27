import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/calendar_period.dart';
import '../../../models/home_item_task.dart';
import '../../../services/reminder_planner.dart';
import '../../../state/home_item_controller.dart';
import '../../../state/settings_controller.dart';
import '../../../utils/date_utils.dart';
import '../../widgets/task_section_card.dart';
import 'dashboard_setup_card.dart';

/// The tasks listed on the Overview below its cards, each in its own card
/// like the calendar's. Tapping a summary card lists only its tasks.
enum _TaskSection { overdue, upcoming, completed }

/// Asks the Overview to list only the upcoming or only the overdue tasks,
/// scrolled to and flashed, as when a reminder about them is tapped. Each
/// request is acted on once, so asking again takes a new one.
class ShowTasksRequest {
  ShowTasksRequest(this.kind);

  final ReminderKind kind;
}

/// The first tab: a live summary of saved maintenance and expense data,
/// with the overdue, upcoming and completed tasks below it.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.onAssistPressed,
    this.onShowExpenses,
    this.isShown = true,
    this.showTasks,
  });

  final VoidCallback onAssistPressed;

  /// Shows the expenses of the current month or year, the period that
  /// spending is counted over here.
  final ValueChanged<CalendarPeriod>? onShowExpenses;

  /// Whether this is the tab being shown. Leaving it lists all the tasks
  /// again, rather than only those of the summary card that was tapped.
  final bool isShown;

  /// The latest request to show only the upcoming or overdue tasks.
  final ShowTasksRequest? showTasks;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TaskDoneChangeUndo {
  late String _greeting;
  Timer? _greetingTimer;

  /// The section whose summary card was tapped to list only its tasks, or
  /// `null` to list them all.
  _TaskSection? _shownSection;

  /// Lists only [section]'s tasks, or all of them again if it already was.
  void _toggleSection(_TaskSection section) {
    final picking = _shownSection != section;
    setState(() {
      _shownSection = picking ? section : null;
      _flashSection = null;
    });
    // Tapping the picked card again only lists all the tasks, leaving the
    // page where it is.
    if (picking) _scrollToTasks();
  }

  /// The tasks are below the cards, so brings them into view once they've
  /// been rebuilt, then flashes the picked card's tasks.
  void _scrollToTasks() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final tasks = _tasksKey.currentContext;
      if (tasks == null || !tasks.mounted) return;
      await Scrollable.ensureVisible(
        tasks,
        duration: MediaQuery.disableAnimationsOf(tasks)
            ? Duration.zero
            : const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      if (mounted && _shownSection != null) {
        setState(() {
          _flashSection = _shownSection;
          _flashes++;
        });
      }
    });
  }

  /// Marks the top of the tasks, to scroll to them.
  final _tasksKey = GlobalKey();

  /// The section whose tasks flash, once they've been scrolled to.
  _TaskSection? _flashSection;

  /// Counts up each time [_flashSection]'s tasks should flash.
  int _flashes = 0;

  @override
  void didUpdateWidget(DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isShown) _shownSection = null;
    final request = widget.showTasks;
    if (request != null && !identical(request, oldWidget.showTasks)) {
      _shownSection = switch (request.kind) {
        ReminderKind.upcoming => _TaskSection.upcoming,
        ReminderKind.overdue => _TaskSection.overdue,
      };
      _flashSection = null;
      _scrollToTasks();
    }
  }

  @override
  void initState() {
    super.initState();
    _greeting = _greetingFor(DateTime.now());
    _greetingTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      final greeting = _greetingFor(DateTime.now());
      if (greeting != _greeting && mounted) {
        setState(() => _greeting = greeting);
      }
    });
  }

  @override
  void dispose() {
    _greetingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HomeItemController>();
    final now = DateTime.now();
    final today = dateOnly(now);
    // The Upcoming and Recently Completed cards look a week, month or year
    // ahead and back from today, as chosen in Appearance settings. Overdue tasks are all
    // counted, however long ago they were due.
    final settings = context.watch<SettingsController>().settings;
    final period = settings.calendarPeriod;
    final dueBy = period.shift(today, 1);
    final completedSince = period.shift(today, -1);
    // Spending is counted by this month or year, like a budget.
    final budgetPeriod = period.budgetPeriod;
    final (budgetStart, budgetEnd) = budgetPeriod.rangeOf(today);
    final activeTasks = controller.allTasks.where(
      (task) => !controller.isListedAsDone(task),
    );
    // A task just marked done stays listed by the date it was due, so it
    // can be undone before it moves on.
    int daysUntilDue(HomeItemTask task) =>
        calendarDaysBetween(today, controller.listDueDate(task));
    final overdueTasks = controller.orderForList(
      activeTasks.where((task) => daysUntilDue(task) < 0),
    );
    final upcomingTasks = controller.orderForList(
      activeTasks.where((task) {
        final days = daysUntilDue(task);
        return days >= 0 && days <= calendarDaysBetween(today, dueBy);
      }),
    );
    final overdue = overdueTasks.length;
    final upcoming = upcomingTasks.length;

    // Every time a task was done in the past week, month or year, newest
    // first: the tasks the Recently Completed card counts. A task done more than once
    // gets a row for each, so each row is its own [HomeItemTask].
    final completedOn = <HomeItemTask, DateTime>{
      for (final item in controller.allTasks)
        for (final date in item.task.completionDates)
          if (!dateOnly(date).isBefore(completedSince))
            HomeItemTask(item.homeItem, item.task): date,
    };
    final completedTasks = completedOn.keys.toList()
      ..sort((a, b) => completedOn[b]!.compareTo(completedOn[a]!));
    final completedInPeriod = completedTasks.length;
    final spentInPeriod = controller.homeItems
        .expand((item) => item.expenses)
        .where(
          (expense) =>
              !expense.date.isBefore(budgetStart) &&
              expense.date.isBefore(budgetEnd),
        )
        .fold<double>(0, (total, expense) => total + expense.amount);
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      // There is no app bar, so the content keeps clear of the status bar.
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontal = constraints.maxWidth >= 640 ? 28.0 : 16.0;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(horizontal, 40, horizontal, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _greeting,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Your home at a glance',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (controller.hasNoTasks) ...[
                    const DashboardSetupCard(),
                    const SizedBox(height: 20),
                  ],
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: constraints.maxWidth < 360
                        ? 0.95
                        : constraints.maxWidth < 640
                        ? 1.08
                        : 1.32,
                    children: [
                      _SummaryCard(
                        label: 'Upcoming',
                        value: '$upcoming',
                        icon: Icons.schedule,
                        color: colors.primary,
                        selected: _shownSection == _TaskSection.upcoming,
                        onTap: () => _toggleSection(_TaskSection.upcoming),
                      ),
                      _SummaryCard(
                        label: 'Overdue',
                        value: '$overdue',
                        icon: Icons.warning_amber_rounded,
                        color: colors.error,
                        selected: _shownSection == _TaskSection.overdue,
                        onTap: () => _toggleSection(_TaskSection.overdue),
                      ),
                      _SummaryCard(
                        label: 'Recently Completed',
                        value: '$completedInPeriod',
                        icon: Icons.task_alt,
                        color: colors.secondary,
                        selected: _shownSection == _TaskSection.completed,
                        onTap: () => _toggleSection(_TaskSection.completed),
                      ),
                      _SummaryCard(
                        label: settings.expensesEnabled
                            ? 'Spent This ${budgetPeriod.label}'
                            : 'Expense tracking disabled',
                        value: '\$${spentInPeriod.toStringAsFixed(2)}',
                        icon: Icons.account_balance_wallet_outlined,
                        color: colors.tertiary,
                        // Turned on in Appearance settings.
                        enabled: settings.expensesEnabled,
                        // The calendar's expenses, for the month or year
                        // counted here.
                        onTap: () => widget.onShowExpenses?.call(budgetPeriod),
                      ),
                    ],
                  ),
                  // Hidden when the assistant is turned off in settings.
                  if (settings.assistantEnabled) ...[
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: widget.onAssistPressed,
                        icon: const Icon(Icons.forum_outlined),
                        label: const Text('Have a home question? Ask AI Assist'),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (!controller.hasNoTasks)
                    ..._taskSections(
                      context,
                      overdueTasks: overdueTasks,
                      upcomingTasks: upcomingTasks,
                      completedTasks: completedTasks,
                      completedOn: completedOn,
                      period: period,
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// The overdue, upcoming and completed tasks, in that order, each in a
  /// card like the calendar's, below a line. Only [_shownSection]'s are
  /// listed if one of the summary cards was tapped.
  List<Widget> _taskSections(
    BuildContext context, {
    required List<HomeItemTask> overdueTasks,
    required List<HomeItemTask> upcomingTasks,
    required List<HomeItemTask> completedTasks,
    required Map<HomeItemTask, DateTime> completedOn,
    required CalendarPeriod period,
  }) {
    final colors = Theme.of(context).colorScheme;
    final shown = _shownSection;
    final cards = [
      (_TaskSection.overdue, 'Overdue', overdueTasks, colors.error),
      (_TaskSection.upcoming, 'Upcoming', upcomingTasks, colors.primary),
      (
        _TaskSection.completed,
        'Recently completed',
        completedTasks,
        colors.secondary,
      ),
    ];
    // Cards without tasks stay in place but aren't shown, so one whose last
    // task just moved on can fade out.
    final shownCards = [
      for (final card in cards)
        if (shown == null || shown == card.$1) card,
    ];

    return [
      // Sets the tasks apart from the summary above.
      Padding(
        key: _tasksKey,
        padding: const EdgeInsets.only(top: 24, bottom: 8),
        child: const Divider(height: 1),
      ),
      for (final (section, title, items, accent) in shownCards)
        TaskSectionCard(
          // Keeps each card's flash with it as the others come and go.
          key: ValueKey(section),
          title: title,
          items: items,
          accent: accent,
          completedOn: completedOn,
          // Finished tasks are a record, so they don't open.
          opensTasks: section != _TaskSection.completed,
          padding: const EdgeInsets.only(top: 8),
          flash: section == _flashSection ? _flashes : null,
          doneChange: doneChangeFor(title, {
            for (final (_, title, items, _) in cards) title: items,
          }),
          onDoneChanged: (change) => showDoneChange(change, title),
          onUndo: undoDoneChange,
        ),
      if (shown != null && shownCards.every((card) => card.$3.isEmpty))
        Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Text(switch (shown) {
              _TaskSection.overdue => 'No overdue tasks.',
              _TaskSection.upcoming =>
                'No tasks are due within the next ${period.name}.',
              _TaskSection.completed =>
                'No tasks completed in the past ${period.name}.',
            }, textAlign: TextAlign.center),
          ),
        ),
    ];
  }
}

String _greetingFor(DateTime time) {
  if (time.hour < 12) return 'Good Morning!';
  if (time.hour < 17) return 'Good Afternoon!';
  return 'Good Evening!';
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.selected = false,
    this.enabled = true,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  /// Whether what the card counts is turned on. When it isn't, the card is
  /// greyed out with only its [label], which says so, and can't be tapped.
  final bool enabled;

  /// Whether only this card's tasks are listed below the cards. A selected
  /// card is outlined in its [color].
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabledColor = theme.colorScheme.onSurface.withValues(alpha: 0.38);
    final color = enabled ? this.color : disabledColor;
    return Card(
      clipBehavior: Clip.antiAlias,
      // The same corners as other cards.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: selected ? BorderSide(color: color, width: 2) : BorderSide.none,
      ),
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Semantics(
          selected: selected,
          enabled: enabled,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: color, size: 27),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left out when turned off, but its space is kept so
                    // the cards line up.
                    Visibility.maintain(
                      visible: enabled,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          value,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: enabled ? null : disabledColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
