import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/home_item_task.dart';
import '../../../state/home_item_controller.dart';
import '../../../utils/date_utils.dart';
import '../../widgets/task_tile.dart';
import '../home_items/home_item_form_screen.dart';

/// A month calendar showing each active maintenance task on its due dates.
/// Its data comes directly from [HomeItemController], so adding or editing an
/// appliance/task is reflected as soon as this screen rebuilds.
class MaintenanceCalendarScreen extends StatefulWidget {
  const MaintenanceCalendarScreen({super.key});

  @override
  State<MaintenanceCalendarScreen> createState() =>
      _MaintenanceCalendarScreenState();
}

class _MaintenanceCalendarScreenState extends State<MaintenanceCalendarScreen> {
  late DateTime _month;
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    final today = dateOnly(DateTime.now());
    _month = DateTime(today.year, today.month);
    _selectedDay = today;
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HomeItemController>();
    final dueByDay = _dueTasksByDay(controller.allTasks, _month);
    final selectedTasks = dueByDay[_dayKey(_selectedDay)] ?? const <HomeItemTask>[];
    final firstOffset = DateTime(_month.year, _month.month, 1).weekday % 7;
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final cellCount = ((firstOffset + daysInMonth + 6) ~/ 7) * 7;

    return Scaffold(
      appBar: AppBar(title: const Text('Maintenance Calendar')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Previous month',
                  onPressed: _canGoBack ? () => _changeMonth(-1) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    '${_monthName(_month.month)} ${_month.year}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Next month',
                  onPressed: () => _changeMonth(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
          Row(
            children: const ['S', 'M', 'T', 'W', 'T', 'F', 'S']
                .map((day) => Expanded(
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text(day, style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ))
                .toList(),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: cellCount,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisExtent: 54,
              ),
              itemBuilder: (context, index) {
                final dayNumber = index - firstOffset + 1;
                if (dayNumber < 1 || dayNumber > daysInMonth) {
                  return const SizedBox.shrink();
                }
                final day = DateTime(_month.year, _month.month, dayNumber);
                final tasks = dueByDay[_dayKey(day)] ?? const <HomeItemTask>[];
                final selected = _sameDay(day, _selectedDay);
                final today = _sameDay(day, dateOnly(DateTime.now()));
                final color = selected
                    ? Theme.of(context).colorScheme.primary
                    : today
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Colors.transparent;
                return Semantics(
                  button: true,
                  label: '${_monthName(day.month)} ${day.day}, ${tasks.length} tasks due',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _selectedDay = day),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                          child: Text(
                            '$dayNumber',
                            style: TextStyle(
                              color: selected
                                  ? Theme.of(context).colorScheme.onPrimary
                                  : null,
                              fontWeight: today || selected ? FontWeight.bold : null,
                            ),
                          ),
                        ),
                        if (tasks.isNotEmpty)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              tasks.length.clamp(1, 3).toInt(),
                              (_) => Container(
                                width: 4,
                                height: 4,
                                margin: const EdgeInsets.symmetric(horizontal: 1),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 20),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${_monthName(_selectedDay.month)} ${_selectedDay.day}, ${_selectedDay.year} · ${selectedTasks.length} ${selectedTasks.length == 1 ? 'task' : 'tasks'}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          Expanded(
            child: selectedTasks.isEmpty
                ? Center(
                    child: Text(
                      'No maintenance due this day',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : ListView(
                    children: [
                      for (final item in selectedTasks)
                        TaskTile(
                          item: item,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => HomeItemFormScreen(existing: item.homeItem),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  bool get _canGoBack {
    final now = DateTime.now();
    return _month.year > now.year || (_month.year == now.year && _month.month > now.month);
  }

  void _changeMonth(int amount) {
    setState(() {
      _month = DateTime(_month.year, _month.month + amount);
      _selectedDay = DateTime(_month.year, _month.month, 1);
    });
  }
}

Map<String, List<HomeItemTask>> _dueTasksByDay(
  List<HomeItemTask> tasks,
  DateTime month,
) {
  final result = <String, List<HomeItemTask>>{};
  final monthStart = DateTime(month.year, month.month);
  final monthEnd = DateTime(month.year, month.month + 1);
  for (final item in tasks) {
    var due = dateOnly(item.dueDate);
    var steps = 0;
    while (due.isBefore(monthStart) && steps++ < 100000) {
      due = item.task.interval.addTo(due);
    }
    while (due.isBefore(monthEnd) && steps++ < 100000) {
      (result[_dayKey(due)] ??= []).add(item);
      due = item.task.interval.addTo(due);
    }
  }
  for (final dayTasks in result.values) {
    dayTasks.sort((a, b) => a.task.title.toLowerCase().compareTo(b.task.title.toLowerCase()));
  }
  return result;
}

String _dayKey(DateTime date) => '${date.year}-${date.month}-${date.day}';
bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

String _monthName(int month) => const [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ][month - 1];
