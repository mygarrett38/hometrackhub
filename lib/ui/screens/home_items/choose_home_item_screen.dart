import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/home_item.dart';
import '../../../state/home_item_controller.dart';
import '../../widgets/category_icon.dart';
import '../../widgets/screen_padding.dart';
import 'home_item_list_screen.dart';

/// Asks which home item a new task is for, such as one the assistant
/// suggested, and returns the one the user taps. The home items are grouped
/// by room, as on the My Home tab, so a long list is easy to look through.
class ChooseHomeItemScreen extends StatelessWidget {
  const ChooseHomeItemScreen({
    super.key,
    required this.taskTitle,
    required this.taskRepeat,
  });

  /// The task being added, and how often it repeats, shown at the top so
  /// the user remembers what they're choosing for.
  final String taskTitle;
  final String taskRepeat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final homeItems = context.watch<HomeItemController>().homeItems;

    return Scaffold(
      appBar: AppBar(title: const Text('Choose home item')),
      body: ListView(
        padding: screenPadding(context),
        children: [
          Card(
            margin: const EdgeInsets.only(bottom: 16),
            color: theme.colorScheme.secondaryContainer,
            child: ListTile(
              leading: Icon(
                Icons.add_task,
                color: theme.colorScheme.onSecondaryContainer,
              ),
              title: Text(
                taskTitle,
                style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
              ),
              subtitle: Text(
                taskRepeat,
                style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
              ),
            ),
          ),
          if (homeItems.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                "You don't have any home items yet. Add one on the My Home "
                'tab, then come back to add this task to it.',
                textAlign: TextAlign.center,
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text(
                'Which home item is this task for?',
                style: theme.textTheme.titleMedium,
              ),
            ),
            for (final (room, items) in HomeItemListScreen.groupByRoom(
              homeItems,
            ))
              _RoomCard(room: room, homeItems: items),
          ],
        ],
      ),
    );
  }
}

/// One room's home items, under its name. Tapping one chooses it.
class _RoomCard extends StatelessWidget {
  const _RoomCard({required this.room, required this.homeItems});

  final String room;
  final List<HomeItem> homeItems;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(room, style: theme.textTheme.titleMedium),
          ),
          const Divider(height: 1),
          for (final homeItem in homeItems)
            ListTile(
              leading: Icon(homeItem.category.icon),
              title: Text(homeItem.name),
              subtitle: Text(homeItem.category.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).pop(homeItem),
            ),
        ],
      ),
    );
  }
}
