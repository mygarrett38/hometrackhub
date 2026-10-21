import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/home_locations.dart';
import '../../../models/home_item.dart';
import '../../../state/home_item_controller.dart';
import '../../../utils/date_utils.dart';
import '../../widgets/category_icon.dart';
import '../../widgets/screen_padding.dart';
import 'add_home_item_screen.dart';
import 'home_item_form_screen.dart';

/// My Home tab: everything the user tracks, grouped by room. Rooms and the
/// items in each are in alphabetical order, with items that have no room
/// last under "Unknown".
class HomeItemListScreen extends StatelessWidget {
  const HomeItemListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final homeItems = context.watch<HomeItemController>().homeItems;

    return Scaffold(
      appBar: AppBar(title: const Text('My Home')),
      floatingActionButton: FloatingActionButton(
        heroTag: 'home_item_fab',
        tooltip: 'Add home item',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AddHomeItemScreen()),
        ),
        child: const Icon(Icons.add),
      ),
      body: homeItems.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'You are not tracking any home items yet.\n\n'
                  'Tap the + button to choose a category and pick a common '
                  'appliance or vehicle, create your own, or find smart '
                  'devices on your Wi-Fi network.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              // Leave room so the last card isn't hidden by the button.
              padding: screenPadding(context)
                  .copyWith(bottom: 88 + MediaQuery.paddingOf(context).bottom),
              children: [
                for (final (room, items) in _groupByRoom(homeItems))
                  _RoomCard(key: ValueKey(room), room: room, items: items),
              ],
            ),
    );
  }

  /// Sorts [homeItems] into rooms, ignoring differences in capitalization
  /// such as "kitchen" and "Kitchen". Items without a room come last under
  /// "Unknown".
  static List<(String, List<HomeItem>)> _groupByRoom(List<HomeItem> homeItems) {
    final rooms = <String, (String, List<HomeItem>)>{};
    for (final item in homeItems) {
      final location = item.location.trim();
      final key = location.toLowerCase();
      rooms.putIfAbsent(key, () => (_roomName(location), [])).$2.add(item);
    }

    int byName(String a, String b) =>
        a.toLowerCase().compareTo(b.toLowerCase());
    final keys = rooms.keys.where((key) => key.isNotEmpty).toList()
      ..sort(byName);
    if (rooms.containsKey('')) keys.add('');

    return [
      for (final key in keys)
        (
          rooms[key]!.$1,
          rooms[key]!.$2..sort((a, b) => byName(a.name, b.name)),
        ),
    ];
  }

  /// The heading for a room, using the usual spelling of a common room.
  static String _roomName(String location) {
    if (location.isEmpty) return 'Unknown';
    return defaultHomeLocations.firstWhere(
      (room) => room.toLowerCase() == location.toLowerCase(),
      orElse: () => location,
    );
  }
}

/// One room's home items in a card that can be collapsed to just its
/// heading. The heading also shows how many items are in the room.
class _RoomCard extends StatefulWidget {
  const _RoomCard({super.key, required this.room, required this.items});

  final String room;
  final List<HomeItem> items;

  @override
  State<_RoomCard> createState() => _RoomCardState();
}

class _RoomCardState extends State<_RoomCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = widget.items.length;

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        initiallyExpanded: true,
        onExpansionChanged: (expanded) => setState(() => _expanded = expanded),
        // The card already draws the outline, so the tile shouldn't add its
        // own borders when expanded.
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(widget.room, style: theme.textTheme.titleMedium),
        // Replacing the trailing arrow means turning it ourselves.
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$count',
              // Read aloud with the word, since a bare number is unclear.
              semanticsLabel: '$count ${count == 1 ? 'item' : 'items'}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            AnimatedRotation(
              turns: _expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: const Icon(Icons.expand_more),
            ),
          ],
        ),
        children: [
          const Divider(height: 1),
          for (final item in widget.items) _HomeItemTile(homeItem: item),
        ],
      ),
    );
  }
}

/// When the soonest of [homeItem]'s tasks is due, or `null` if it has none.
DateTime? _nextDueDate(HomeItem homeItem) => homeItem.tasks.isEmpty
    ? null
    : homeItem.tasks
          .map((task) => task.nextDueDate)
          .reduce((a, b) => a.isBefore(b) ? a : b);

class _HomeItemTile extends StatelessWidget {
  const _HomeItemTile({required this.homeItem});

  final HomeItem homeItem;

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(DateTime.now());
    final nextDue = _nextDueDate(homeItem);

    final makeAndModel = [
      homeItem.manufacturer,
      homeItem.modelNumber,
    ].where((part) => part.isNotEmpty).join(' ');
    // The room is already the heading above.
    final subtitle = [
      if (makeAndModel.isNotEmpty) makeAndModel,
      if (nextDue != null) describeNextTaskDue(nextDue, today),
    ].join(' · ');

    return ListTile(
      leading: Icon(homeItem.category.icon),
      title: Text(homeItem.name),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => HomeItemFormScreen(existing: homeItem),
        ),
      ),
    );
  }
}
