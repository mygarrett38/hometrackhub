import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/home_item.dart';
import '../../models/home_item_task.dart';
import '../../state/home_item_controller.dart';
import '../widgets/category_icon.dart';
import '../widgets/task_tile.dart';
import 'home_item_form_screen.dart';
import 'task_form_screen.dart';

/// Shows one home item and its maintenance schedule.
class HomeItemDetailScreen extends StatelessWidget {
  const HomeItemDetailScreen({super.key, required this.homeItemId});

  final String homeItemId;

  @override
  Widget build(BuildContext context) {
    final homeItem = context.watch<HomeItemController>().findById(homeItemId);

    // The home item may have just been deleted.
    if (homeItem == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This home item no longer exists.')),
      );
    }

    final tasks = [
      for (final task in homeItem.tasks) HomeItemTask(homeItem, task),
    ]..sort((a, b) => a.dueDate.compareTo(b.dueDate));

    return Scaffold(
      appBar: AppBar(
        title: Text(homeItem.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit details',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => HomeItemFormScreen(existing: homeItem),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete home item',
            onPressed: () => _confirmDelete(context, homeItem),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TaskFormScreen(homeItemId: homeItem.id),
          ),
        ),
        icon: const Icon(Icons.add_task),
        label: const Text('Add task'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          _DetailsCard(homeItem: homeItem),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'Maintenance schedule',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (tasks.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No maintenance tasks yet. Tap "Add task" to create one.',
              ),
            ),
          for (final item in tasks)
            TaskTile(
              item: item,
              showHomeItemName: false,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TaskFormScreen(
                    homeItemId: homeItem.id,
                    existing: item.task,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, HomeItem homeItem) async {
    final controller = context.read<HomeItemController>();
    final navigator = Navigator.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${homeItem.name}?'),
        content: const Text(
          'This also deletes its maintenance history and reminders.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      navigator.pop();
      await controller.deleteHomeItem(homeItem.id);
    }
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.homeItem});

  final HomeItem homeItem;

  @override
  Widget build(BuildContext context) {
    final purchaseDate = homeItem.purchaseDate;
    final details = <(String, String)>[
      ('Category', homeItem.category.label),
      if (homeItem.manufacturer.isNotEmpty)
        ('Manufacturer', homeItem.manufacturer),
      if (homeItem.modelNumber.isNotEmpty) ('Model', homeItem.modelNumber),
      if (homeItem.serialNumber.isNotEmpty)
        ('Serial number', homeItem.serialNumber),
      if (homeItem.location.isNotEmpty) ('Location', homeItem.location),
      if (purchaseDate != null)
        (
          'Purchased',
          MaterialLocalizations.of(context).formatMediumDate(purchaseDate),
        ),
      if (homeItem.notes.isNotEmpty) ('Notes', homeItem.notes),
    ];

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(homeItem.category.icon),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    homeItem.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final (label, value) in details)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('$label: $value'),
              ),
          ],
        ),
      ),
    );
  }
}
