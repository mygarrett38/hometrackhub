import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/home_item_task.dart';
import '../../state/home_item_controller.dart';
import '../../utils/date_utils.dart';
import '../widgets/task_tile.dart';
import 'home_item_detail_screen.dart';

/// Home tab: every maintenance task, grouped into overdue, due soon and
/// later.
class UpcomingScreen extends StatelessWidget {
  const UpcomingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upcoming Maintenance')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => {},
        child: const Icon(Icons.add),
      ),
      body: context.watch<HomeItemController>().hasNoTasks
          ? const _EmptyMessage()
          : const _TaskMessage(),
    );
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
          'Add your appliances, vehicles and other home items on the '
          'My Home tab to start tracking maintenance.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _TaskMessage extends StatelessWidget {
  const _TaskMessage();

  /// Tasks due within this many days are listed under "Due soon".
  static const dueSoonDays = 30;

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(DateTime.now());

    final overdue = <HomeItemTask>[];
    final dueSoon = <HomeItemTask>[];
    final later = <HomeItemTask>[];
    for (final item in context.watch<HomeItemController>().allTasks) {
      final days = calendarDaysBetween(today, item.dueDate);
      if (days < 0) {
        overdue.add(item);
      } else if (days <= dueSoonDays) {
        dueSoon.add(item);
      } else {
        later.add(item);
      }
    }

    return ListView(
      children: [
        ..._section(context, 'Overdue', overdue),
        ..._section(context, 'Due in the next $dueSoonDays days', dueSoon),
        ..._section(context, 'Later', later),
      ],
    );
  }

  List<Widget> _section(
    BuildContext context,
    String title,
    List<HomeItemTask> items,
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
                  HomeItemDetailScreen(homeItemId: item.homeItem.id),
            ),
          ),
        ),
    ];
  }
}
