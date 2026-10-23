import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/home_item.dart';
import '../../../state/home_item_controller.dart';
import '../home_items/add_home_item_screen.dart';
import '../home_items/task_form_screen.dart';

/// Guides users through setup until their first maintenance task is saved.
class DashboardSetupCard extends StatelessWidget {
  const DashboardSetupCard({super.key});

  @override
  Widget build(BuildContext context) {
    final items = context.watch<HomeItemController>().homeItems;
    final needsItem = items.isEmpty;
    final theme = Theme.of(context);

    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              needsItem ? Icons.home_outlined : Icons.event_available_outlined,
              color: theme.colorScheme.onPrimaryContainer,
              size: 32,
            ),
            const SizedBox(height: 12),
            Text(
              needsItem
                  ? 'Start with one thing in your home'
                  : 'Set up your first maintenance reminder',
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              needsItem
                  ? 'Add an appliance, vehicle, or other home item to start '
                        'tracking its maintenance.'
                  : 'Add a task for a home item and choose how often it needs '
                        'maintenance.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                if (needsItem) {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AddHomeItemScreen(),
                    ),
                  );
                } else {
                  _addTask(context, items);
                }
              },
              icon: const Icon(Icons.add),
              label: Text(needsItem ? 'Add home item' : 'Add maintenance task'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addTask(BuildContext context, List<HomeItem> items) async {
    final item = items.length == 1
        ? items.single
        : await showDialog<HomeItem>(
            context: context,
            builder: (context) => SimpleDialog(
              title: const Text('Choose a home item'),
              children: [
                for (final item in items)
                  SimpleDialogOption(
                    onPressed: () => Navigator.of(context).pop(item),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        item.location.isEmpty
                            ? item.name
                            : '${item.name} · ${item.location}',
                      ),
                    ),
                  ),
                SimpleDialogOption(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          );
    if (item == null || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            TaskFormScreen(homeItemId: item.id, homeItemName: item.name),
      ),
    );
  }
}
