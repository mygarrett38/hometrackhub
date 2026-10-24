import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/home_item_task.dart';
import '../../../state/home_item_controller.dart';
import '../../../utils/date_utils.dart';
import '../../widgets/task_tile.dart';
import '../home_items/task_form_screen.dart';

/// How much time the calendar shows at once.
enum CalendarPeriod {
  week('Week'),
  month('Month'),
  year('Year');

  const CalendarPeriod(this.label);

  final String label;
}

/// Calendar tab: a week, month or year of maintenance, with every task due
/// or completed in that time listed below it. Tapping a day narrows the list
/// to that day.
///
/// Its data comes directly from [HomeItemController], so adding or editing an
/// appliance/task is reflected as soon as this screen rebuilds.
class MaintenanceCalendarScreen extends StatefulWidget {
  const MaintenanceCalendarScreen({super.key});

  @override
  State<MaintenanceCalendarScreen> createState() =>
      _MaintenanceCalendarScreenState();
}

class _MaintenanceCalendarScreenState extends State<MaintenanceCalendarScreen> {
  /// The page showing the period [_anchorDay] is in. Pages before and after
  /// it show earlier and later periods, with plenty to swipe through either
  /// way.
  static const _anchorPage = 10000;

  var _period = CalendarPeriod.month;

  /// The day the screen was opened, which pages are counted from.
  late final DateTime _anchorDay;

  /// A day inside the period being shown.
  late DateTime _focusDay;

  /// The day the list is narrowed to, or `null` to list the whole period.
  DateTime? _selectedDay;

  late final PageController _pages;

  /// The task just marked done or undone, shown with an Undo button between
  /// the calendar and the task lists for a few seconds.
  TaskDoneChange? _doneChange;
  Timer? _doneChangeTimer;

  /// The section ("Overdue", "Due" or "Completed") whose card [_doneChange]
  /// was made in.
  String? _doneChangeSection;

  @override
  void initState() {
    super.initState();
    _anchorDay = dateOnly(DateTime.now());
    _focusDay = _anchorDay;
    _pages = PageController(initialPage: _anchorPage);
  }

  @override
  void dispose() {
    _doneChangeTimer?.cancel();
    _pages.dispose();
    super.dispose();
  }

  void _showDoneChange(TaskDoneChange change, String section) {
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

  /// The section whose card shows [_doneChange]: the one it was made in,
  /// or if the task has since left that card, the first one it's now in.
  String? _doneChangeNoteSection(_ListedTasks listed) {
    final change = _doneChange;
    if (change == null) return null;
    final sections = {
      'Overdue': listed.overdue,
      'Due': listed.due,
      'Completed': listed.completed,
    };
    bool listsTask(String section) =>
        sections[section]!.any((item) => item.task.id == change.taskId);
    if (_doneChangeSection case final section?
        when sections.containsKey(section) && listsTask(section)) {
      return section;
    }
    return sections.keys.where(listsTask).firstOrNull;
  }

  Future<void> _undoDoneChange() async {
    final change = _doneChange;
    if (change == null) return;
    _doneChangeTimer?.cancel();
    setState(() => _doneChange = null);
    await change.undo();
  }

  /// The page that shows the period [day] is in.
  int _pageFor(DateTime day) {
    final anchor = _anchorDay;
    return _anchorPage +
        switch (_period) {
          CalendarPeriod.week =>
            calendarDaysBetween(_weekStart(anchor), _weekStart(day)) ~/ 7,
          CalendarPeriod.month =>
            (day.year - anchor.year) * 12 + day.month - anchor.month,
          CalendarPeriod.year => day.year - anchor.year,
        };
  }

  /// A day inside the period that [page] shows.
  DateTime _dayOnPage(int page) {
    final offset = page - _anchorPage;
    final anchor = _anchorDay;
    if (offset == 0) return anchor;
    return switch (_period) {
      CalendarPeriod.week => DateTime(
        anchor.year,
        anchor.month,
        anchor.day + 7 * offset,
      ),
      CalendarPeriod.month => DateTime(anchor.year, anchor.month + offset),
      CalendarPeriod.year => DateTime(anchor.year + offset, anchor.month),
    };
  }

  /// The week, month or year that [day] is in.
  _DayRange _periodOf(DateTime day) {
    return switch (_period) {
      CalendarPeriod.week => _DayRange.days(_weekStart(day), 7),
      CalendarPeriod.month => _DayRange(
        DateTime(day.year, day.month),
        DateTime(day.year, day.month + 1),
      ),
      CalendarPeriod.year => _DayRange(
        DateTime(day.year),
        DateTime(day.year + 1),
      ),
    };
  }

  double get _pageHeight => switch (_period) {
    CalendarPeriod.week => _DayGrid.heightFor(weeks: 1),
    CalendarPeriod.month => _DayGrid.heightFor(weeks: 6),
    CalendarPeriod.year => _YearGrid.height,
  };

  void _onPageChanged(int page) {
    setState(() {
      // Keeps the focus day if the page was changed to show it.
      if (_pageFor(_focusDay) != page) _focusDay = _dayOnPage(page);
      // Keeps the selected day only if it is on the new page, such as a
      // faded day that was tapped to move to its month.
      final selectedDay = _selectedDay;
      if (selectedDay != null && _pageFor(selectedDay) != page) {
        _selectedDay = null;
      }
    });
  }

  /// Switches to [period] and shows the part of it that [day] is in, with
  /// [select] as the selected day.
  void _show(DateTime day, CalendarPeriod period, {DateTime? select}) {
    final samePeriod = period == _period;
    setState(() {
      _period = period;
      _focusDay = day;
      _selectedDay = select;
    });
    if (!_pages.hasClients) return;
    final page = _pageFor(day);
    final current = _pages.page?.round() ?? page;
    if (samePeriod && (page - current).abs() == 1) {
      _pages.animateToPage(
        page,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _pages.jumpToPage(page);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HomeItemController>();
    final colors = Theme.of(context).colorScheme;
    final today = dateOnly(DateTime.now());
    final range = _periodOf(_focusDay);
    final selectedDay = _selectedDay;
    final listed = _ListedTasks.between(
      controller,
      selectedDay == null ? range : _DayRange.days(selectedDay, 1),
      today,
    );
    final noteSection = _doneChangeNoteSection(listed);

    return Scaffold(
      // There is no app bar, so the list keeps clear of the status bar.
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            // The period's name, which opens a menu to switch between weeks,
            // months and years. As tall as an app bar, with the name centered
            // in it, so it lines up with the other tabs' titles.
            Container(
              height: kToolbarHeight,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: PopupMenuButton<CalendarPeriod>(
                        tooltip: 'Show week, month or year',
                        initialValue: _period,
                        onSelected: (period) => _show(_focusDay, period),
                        itemBuilder: (context) => [
                          for (final period in CalendarPeriod.values)
                            CheckedPopupMenuItem(
                              value: period,
                              checked: period == _period,
                              child: Text(period.label),
                            ),
                        ],
                        // Lines the title up with the cards below, 16 from
                        // the edge.
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  _title(range),
                                  style: Theme.of(context).textTheme.titleLarge,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Icon(Icons.arrow_drop_down),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_period != CalendarPeriod.year) const _WeekdayLabels(),
            // Swipe left or right for the next or previous period.
            SizedBox(
              height: _pageHeight,
              child: PageView.builder(
                controller: _pages,
                onPageChanged: _onPageChanged,
                itemBuilder: (context, page) =>
                    _buildPage(context, page, controller, today),
              ),
            ),
            const Divider(height: 12),
            if (selectedDay != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_monthName(selectedDay.month)} ${selectedDay.day}, '
                        '${selectedDay.year}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _selectedDay = null),
                      child: Text('Show whole ${_period.name}'),
                    ),
                  ],
                ),
              ),
            if (controller.hasNoTasks)
              const _EmptyMessage(
                'No maintenance scheduled yet.\n\n'
                'Add your appliances, vehicles and other home items on the '
                'My Home tab to start tracking maintenance.',
              )
            else if (listed.isEmpty)
              _EmptyMessage(
                selectedDay != null
                    ? 'No maintenance on this day'
                    : 'No maintenance this ${_period.name}',
              )
            else ...[
              // Tinted with the colors of the matching Overview cards.
              ..._section(
                context,
                'Overdue',
                listed.overdue,
                accent: colors.error,
                dueOn: listed.dueOn,
                showsDoneChange: noteSection == 'Overdue',
              ),
              ..._section(
                context,
                'Due',
                listed.due,
                accent: colors.primary,
                dueOn: listed.dueOn,
                showsDoneChange: noteSection == 'Due',
              ),
              ..._section(
                context,
                'Completed',
                listed.completed,
                accent: colors.secondary,
                completedOn: listed.completedOn,
                // Finished tasks are a record, so they don't open.
                opensTasks: false,
                showsDoneChange: noteSection == 'Completed',
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _title(_DayRange range) {
    final start = range.start;
    switch (_period) {
      case CalendarPeriod.year:
        return '${start.year}';
      case CalendarPeriod.month:
        return '${_monthName(start.month)} ${start.year}';
      case CalendarPeriod.week:
        final last = range.lastDay;
        if (start.year != last.year) {
          return '${_shortDate(start)}, ${start.year} – '
              '${_shortDate(last)}, ${last.year}';
        }
        if (start.month != last.month) {
          return '${_shortDate(start)} – ${_shortDate(last)}, ${start.year}';
        }
        return '${_shortDate(start)} – ${last.day}, ${start.year}';
    }
  }

  /// One swipeable page: the calendar for one week, month or year.
  Widget _buildPage(
    BuildContext context,
    int page,
    HomeItemController controller,
    DateTime today,
  ) {
    final range = _periodOf(_dayOnPage(page));
    if (_period == CalendarPeriod.year) {
      return _YearGrid(
        year: range.start.year,
        controller: controller,
        today: today,
        onMonthTap: (month) => _show(
          month.year == today.year && month.month == today.month
              ? today
              : month,
          CalendarPeriod.month,
        ),
      );
    }

    // A month always shows six whole weeks, so every page is the same
    // height. A week belongs to the month most of its days are in.
    final days = _period == CalendarPeriod.month
        ? _DayRange.days(_weekStart(range.start), 7 * 6)
        : range;
    final month = _period == CalendarPeriod.month
        ? range.start.month
        : DateTime(
            range.start.year,
            range.start.month,
            range.start.day + 3,
          ).month;
    return _DayGrid(
      days: days,
      month: month,
      markers: _DayMarkers.between(controller, days, today),
      today: today,
      selectedDay: _selectedDay,
      onDayTap: (day) {
        // A faded day in a month view moves to its own month.
        if (_period == CalendarPeriod.month && day.month != month) {
          _show(day, CalendarPeriod.month, select: day);
        } else {
          setState(() => _selectedDay = _selectedDay == day ? null : day);
        }
      },
    );
  }

  List<Widget> _section(
    BuildContext context,
    String title,
    List<HomeItemTask> items, {
    required Color accent,
    Map<HomeItemTask, DateTime> dueOn = const {},
    Map<HomeItemTask, DateTime> completedOn = const {},
    bool opensTasks = true,
    bool showsDoneChange = false,
  }) {
    if (items.isEmpty) return [];
    final theme = Theme.of(context);
    final cardColor =
        theme.cardTheme.color ?? theme.colorScheme.surfaceContainerLow;
    // A card like the home item screen's maintenance tasks, with a light
    // wash of [accent]. At 12% every text color in the rows keeps a
    // contrast of at least 4.5:1. The margin lines the card's edges up 16
    // from the screen's.
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Card(
          color: Color.lerp(cardColor, accent, 0.12),
          clipBehavior: Clip.antiAlias,
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
                        child: showsDoneChange && _doneChange != null
                            ? _DoneChangeNote(
                                // The same key for every note, so a new one
                                // replaces the last in place rather than
                                // showing through it as it fades.
                                key: const ValueKey('note'),
                                change: _doneChange!,
                                onUndo: _undoDoneChange,
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
                  onDoneChanged: (change) => _showDoneChange(change, title),
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
      ),
    ];
  }
}

/// A short note that a task was just marked done or undone, with a button
/// to undo it, for the top right of the card the task is in.
class _DoneChangeNote extends StatelessWidget {
  const _DoneChangeNote({
    super.key,
    required this.change,
    required this.onUndo,
  });

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

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Text(message, textAlign: TextAlign.center),
    );
  }
}

/// The letters for the days of the week, above the swipeable pages so they
/// stay still while the days move.
class _WeekdayLabels extends StatelessWidget {
  const _WeekdayLabels();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _DayGrid.inset),
      child: SizedBox(
        height: 24,
        child: Row(
          children: [
            for (final day in const ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
              Expanded(
                child: Center(
                  child: Text(
                    day,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The days of a week or month, with dots under each day for the tasks due
/// or completed on it. Days from other months are faded.
class _DayGrid extends StatelessWidget {
  const _DayGrid({
    required this.days,
    required this.month,
    required this.markers,
    required this.today,
    required this.selectedDay,
    required this.onDayTap,
  });

  static const _rowHeight = 44.0;

  /// Space at each side. [_WeekdayLabels] uses the same, so each letter sits
  /// centered over its column of days.
  static const inset = 8.0;

  /// The height of a grid showing [weeks] weeks.
  static double heightFor({required int weeks}) => weeks * _rowHeight;

  /// Whole weeks, starting on a Sunday.
  final _DayRange days;

  /// The month being shown. Days in other months are faded.
  final int month;
  final _DayMarkers markers;
  final DateTime today;
  final DateTime? selectedDay;
  final ValueChanged<DateTime> onDayTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: inset),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: days.dayCount,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          mainAxisExtent: _rowHeight,
        ),
        itemBuilder: (context, index) {
          final day = DateTime(
            days.start.year,
            days.start.month,
            days.start.day + index,
          );
          final due = markers.dueByDay[day] ?? 0;
          final done = markers.doneByDay[day] ?? 0;
          final selected = day == selectedDay;
          final isToday = day == today;
          final color = selected
              ? colors.primary
              : isToday
              ? colors.primaryContainer
              : Colors.transparent;
          // Due dots come first, then completed ones, three at most.
          final dueColor = day.isBefore(today) ? colors.error : colors.primary;
          final dotColors = [
            for (var i = 0; i < due; i++) dueColor,
            for (var i = 0; i < done; i++) colors.outline,
          ].take(3);

          return Semantics(
            button: true,
            selected: selected,
            label:
                '${_monthName(day.month)} ${day.day}, $due due, '
                '$done completed',
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onDayTap(day),
              child: Opacity(
                opacity: day.month == month ? 1 : 0.5,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${day.day}',
                        style: TextStyle(
                          color: selected
                              ? colors.onPrimary
                              : isToday
                              ? _onTodayColor(colors)
                              : null,
                          fontWeight: isToday || selected
                              ? FontWeight.bold
                              : null,
                        ),
                      ),
                    ),
                    if (dotColors.isNotEmpty)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (final dotColor in dotColors)
                            Container(
                              width: 4,
                              height: 4,
                              margin: const EdgeInsets.symmetric(horizontal: 1),
                              decoration: BoxDecoration(
                                color: dotColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The twelve months of a year, each showing how many tasks are due and
/// completed in it. Tapping a month opens it.
class _YearGrid extends StatelessWidget {
  const _YearGrid({
    required this.year,
    required this.controller,
    required this.today,
    required this.onMonthTap,
  });

  static const _cardHeight = 60.0;
  static const _spacing = 6.0;
  static const _padding = 4.0;

  /// The height of the twelve months, in four rows.
  static const height = 4 * _cardHeight + 3 * _spacing + 2 * _padding;

  final int year;
  final HomeItemController controller;
  final DateTime today;
  final ValueChanged<DateTime> onMonthTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: _padding),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 12,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisExtent: _cardHeight,
          mainAxisSpacing: _spacing,
          crossAxisSpacing: _spacing,
        ),
        itemBuilder: (context, index) {
          final month = DateTime(year, index + 1);
          final listed = _ListedTasks.between(
            controller,
            _DayRange(month, DateTime(year, index + 2)),
            today,
          );
          final due = listed.overdue.length + listed.due.length;
          final done = listed.completed.length;
          final isThisMonth =
              month.year == today.year && month.month == today.month;

          return Semantics(
            button: true,
            label: '${_monthName(month.month)}, $due due, $done completed',
            excludeSemantics: true,
            child: Material(
              // Other months match the cards used on the other screens.
              color: isThisMonth
                  ? theme.colorScheme.primaryContainer
                  : theme.cardTheme.color ??
                        theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onMonthTap(month),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _monthName(month.month).substring(0, 3),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: isThisMonth
                              ? _onTodayColor(theme.colorScheme)
                              : null,
                        ),
                      ),
                      const Spacer(),
                      // Both counts share one line to keep the card short.
                      Text.rich(
                        TextSpan(
                          children: [
                            if (due > 0)
                              TextSpan(
                                text: '$due due',
                                style: TextStyle(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            if (due > 0 && done > 0)
                              const TextSpan(text: ' · '),
                            if (done > 0)
                              TextSpan(
                                text: '$done done',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                        style: theme.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The days from [start] up to, but not including, [end].
@immutable
class _DayRange {
  const _DayRange(this.start, this.end);

  _DayRange.days(DateTime start, int count)
    : this(start, DateTime(start.year, start.month, start.day + count));

  final DateTime start;
  final DateTime end;

  DateTime get lastDay => DateTime(end.year, end.month, end.day - 1);

  int get dayCount => calendarDaysBetween(start, end);

  bool contains(DateTime day) => !day.isBefore(start) && day.isBefore(end);
}

/// The tasks to list for a range of days, split into overdue, due and
/// completed. A task is listed at most once in each group, even if it is due
/// or was completed several times in the range.
class _ListedTasks {
  _ListedTasks._(
    this.overdue,
    this.due,
    this.completed,
    this.dueOn,
    this.completedOn,
  );

  factory _ListedTasks.between(
    HomeItemController controller,
    _DayRange range,
    DateTime today,
  ) {
    final overdue = <(DateTime, HomeItemTask)>[];
    final due = <(DateTime, HomeItemTask)>[];
    final completed = <(DateTime, HomeItemTask)>[];

    for (final item in controller.allTasks) {
      final nextDue = dateOnly(controller.listDueDate(item));
      // Overdue tasks are listed for the day they were due and for today,
      // since they still need doing.
      if (nextDue.isBefore(today) &&
          (range.contains(nextDue) || range.contains(today))) {
        overdue.add((nextDue, item));
      } else {
        final firstDue = _dueDates(controller, item, range, today).firstOrNull;
        if (firstDue != null) due.add((firstDue, item));
      }

      final lastCompleted = _completionDates(
        controller,
        item,
        range,
        today,
      ).lastOrNull;
      if (lastCompleted != null) completed.add((lastCompleted, item));
    }

    int byDateThenTitle(
      (DateTime, HomeItemTask) a,
      (DateTime, HomeItemTask) b,
    ) {
      final byDate = a.$1.compareTo(b.$1);
      if (byDate != 0) return byDate;
      return a.$2.task.title.toLowerCase().compareTo(
        b.$2.task.title.toLowerCase(),
      );
    }

    overdue.sort(byDateThenTitle);
    due.sort(byDateThenTitle);
    // Most recently completed first.
    completed.sort((a, b) => byDateThenTitle(b, a));
    return _ListedTasks._(
      [for (final (_, item) in overdue) item],
      [for (final (_, item) in due) item],
      [for (final (_, item) in completed) item],
      Map.identity()..addEntries([
        for (final (date, item) in [...overdue, ...due]) MapEntry(item, date),
      ]),
      Map.identity()..addEntries([
        for (final (date, item) in completed) MapEntry(item, date),
      ]),
    );
  }

  final List<HomeItemTask> overdue;
  final List<HomeItemTask> due;
  final List<HomeItemTask> completed;

  /// The day each of [overdue] and [due] is listed for, which they're sorted
  /// by. For a period after this one, that's the first time the task repeats
  /// in it rather than its next due date.
  final Map<HomeItemTask, DateTime> dueOn;

  /// The latest day in the range that each of [completed] was done.
  final Map<HomeItemTask, DateTime> completedOn;

  bool get isEmpty => overdue.isEmpty && due.isEmpty && completed.isEmpty;
}

/// How many tasks are due and completed on each day of a range.
class _DayMarkers {
  _DayMarkers._(this.dueByDay, this.doneByDay);

  factory _DayMarkers.between(
    HomeItemController controller,
    _DayRange range,
    DateTime today,
  ) {
    final dueByDay = <DateTime, int>{};
    final doneByDay = <DateTime, int>{};
    for (final item in controller.allTasks) {
      for (final day in _dueDates(controller, item, range, today)) {
        dueByDay[day] = (dueByDay[day] ?? 0) + 1;
      }
      for (final day in _completionDates(controller, item, range, today)) {
        doneByDay[day] = (doneByDay[day] ?? 0) + 1;
      }
    }
    return _DayMarkers._(dueByDay, doneByDay);
  }

  final Map<DateTime, int> dueByDay;
  final Map<DateTime, int> doneByDay;
}

/// Every date in [range] that [item] is due, in order: its next due date,
/// then the dates it repeats on after that.
///
/// Repeats that would fall before [today] are left out, since an overdue task
/// doesn't come due again until it is done.
Iterable<DateTime> _dueDates(
  HomeItemController controller,
  HomeItemTask item,
  _DayRange range,
  DateTime today,
) sync* {
  final interval = item.task.interval;
  final nextDue = dateOnly(controller.listDueDate(item));
  if (range.contains(nextDue)) yield nextDue;

  final from = range.start.isAfter(today) ? range.start : today;
  var due = interval.addTo(nextDue);
  var steps = 0;
  while (due.isBefore(from) && steps++ < 100000) {
    due = interval.addTo(due);
  }
  while (due.isBefore(range.end) && steps++ < 100000) {
    yield due;
    due = interval.addTo(due);
  }
}

/// Every date in [range] that [item] was completed, in order.
///
/// A task that was just marked done today isn't counted until it moves to
/// the completed tasks, so it doesn't jump away as soon as the user taps it.
Iterable<DateTime> _completionDates(
  HomeItemController controller,
  HomeItemTask item,
  _DayRange range,
  DateTime today,
) {
  final dates = {
    for (final date in item.task.completionDates)
      if (range.contains(dateOnly(date)) &&
          (dateOnly(date) != today || controller.isListedAsDone(item)))
        dateOnly(date),
  }.toList()..sort();
  return dates;
}

/// The text color for today's day and this month's name, which sit on a
/// sage highlight: the light cream of the navigation bar. In dark mode the
/// bar is navy, so the logo's cream is used instead.
Color _onTodayColor(ColorScheme colors) => colors.brightness == Brightness.light
    ? colors.surfaceContainer
    : colors.onPrimaryContainer;

/// The Sunday on or before [day].
DateTime _weekStart(DateTime day) =>
    DateTime(day.year, day.month, day.day - day.weekday % 7);

String _shortDate(DateTime date) =>
    '${_monthName(date.month).substring(0, 3)} ${date.day}';

String _monthName(int month) => const [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
][month - 1];
