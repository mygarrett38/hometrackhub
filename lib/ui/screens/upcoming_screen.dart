import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/equipment_task.dart';
import '../../state/equipment_controller.dart';
import '../../utils/date_utils.dart';
import '../widgets/task_tile.dart';
import 'equipment_detail_screen.dart';

/// Home tab: every maintenance task, grouped into overdue, due soon and
/// later.
class UpcomingScreen extends StatelessWidget {
  const UpcomingScreen({super.key});

  /// Tasks due within this many days are listed under "Due soon".
  static const dueSoonDays = 30;

  @override
  Widget build(BuildContext context) {
    final tasks = context.watch<EquipmentController>().allTasks;
    final today = dateOnly(DateTime.now());

    final overdue = <EquipmentTask>[];
    final dueSoon = <EquipmentTask>[];
    final later = <EquipmentTask>[];
    for (final item in tasks) {
      final days = calendarDaysBetween(today, item.dueDate);
      if (days < 0) {
        overdue.add(item);
      } else if (days <= dueSoonDays) {
        dueSoon.add(item);
      } else {
        later.add(item);
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Upcoming maintenance')),
      body: tasks.isEmpty
          ? const _EmptyMessage()
          : ListView(
              children: [
                ..._section(context, 'Overdue', overdue),
                ..._section(
                  context,
                  'Due in the next $dueSoonDays days',
                  dueSoon,
                ),
                ..._section(context, 'Later', later),
              ],
            ),
    );
  }

  List<Widget> _section(
    BuildContext context,
    String title,
    List<EquipmentTask> items,
  ) {
    if (items.isEmpty) return [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          '$title (${items.length})',
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
      for (final item in items)
        TaskTile(
          item: item,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  EquipmentDetailScreen(equipmentId: item.equipment.id),
            ),
          ),
        ),
    ];
  }
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          'No maintenance scheduled yet.\n\n'
          'Add your appliances, vehicles and other equipment on the '
          'Equipment tab to start tracking maintenance.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
