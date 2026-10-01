import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/home_item.dart';
import '../../../models/home_item_category.dart';
import '../../../state/home_item_controller.dart';
import '../../../utils/date_utils.dart';
import '../../widgets/category_icon.dart';
import 'add_home_item_screen.dart';
import 'home_item_detail_screen.dart';

/// My Home tab: everything the user tracks, grouped by category.
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
              // Leave room so the last item isn't hidden by the button.
              padding: const EdgeInsets.only(bottom: 88),
              children: [
                for (final category in HomeItemCategory.values)
                  ..._categorySection(context, category, homeItems),
              ],
            ),
    );
  }

  List<Widget> _categorySection(
    BuildContext context,
    HomeItemCategory category,
    List<HomeItem> allHomeItems,
  ) {
    final items = allHomeItems
        .where((item) => item.category == category)
        .toList();
    if (items.isEmpty) return [];

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          category.label,
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
      for (final item in items) _HomeItemTile(homeItem: item),
    ];
  }
}

class _HomeItemTile extends StatelessWidget {
  const _HomeItemTile({required this.homeItem});

  final HomeItem homeItem;

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(DateTime.now());
    final nextDue = homeItem.tasks.isEmpty
        ? null
        : homeItem.tasks
              .map((task) => task.nextDueDate)
              .reduce((a, b) => a.isBefore(b) ? a : b);

    final makeAndModel = [
      homeItem.manufacturer,
      homeItem.modelNumber,
    ].where((part) => part.isNotEmpty).join(' ');
    final taskCount = homeItem.tasks.length;
    final subtitle = [
      if (makeAndModel.isNotEmpty) makeAndModel,
      if (homeItem.location.isNotEmpty) homeItem.location,
      '$taskCount ${taskCount == 1 ? 'task' : 'tasks'}',
      if (nextDue != null) 'Next: ${describeDueDate(nextDue, today)}',
    ].join(' · ');

    return ListTile(
      leading: Icon(homeItem.category.icon),
      title: Text(homeItem.name),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => HomeItemDetailScreen(homeItemId: homeItem.id),
        ),
      ),
    );
  }
}
