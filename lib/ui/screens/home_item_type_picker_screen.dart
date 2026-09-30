import 'package:flutter/material.dart';

import '../../data/home_item_catalog.dart';
import '../../models/home_item_category.dart';
import '../widgets/category_icon.dart';
import 'home_item_form_screen.dart';

/// Lets the user pick a common kind of home item from the built-in catalog.
class HomeItemTypePickerScreen extends StatefulWidget {
  const HomeItemTypePickerScreen({super.key});

  @override
  State<HomeItemTypePickerScreen> createState() =>
      _HomeItemTypePickerScreenState();
}

class _HomeItemTypePickerScreenState extends State<HomeItemTypePickerScreen> {
  String _search = '';

  void _open(Widget screen) {
    Navigator.of(context)
        .pushReplacement(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.trim().toLowerCase();
    final matches = homeItemCatalog
        .where((type) => type.name.toLowerCase().contains(query))
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Choose home item type')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search, e.g. "water heater"',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _search = value),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.edit_note),
            title: const Text('Not listed? Create custom home item'),
            onTap: () => _open(const HomeItemFormScreen()),
          ),
          const Divider(),
          for (final category in HomeItemCategory.values)
            ..._categorySection(category, matches),
        ],
      ),
    );
  }

  List<Widget> _categorySection(
    HomeItemCategory category,
    List<HomeItemType> matches,
  ) {
    final types = matches.where((type) => type.category == category).toList();
    if (types.isEmpty) return [];

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          category.label,
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
      for (final type in types)
        ListTile(
          leading: Icon(type.category.icon),
          title: Text(type.name),
          subtitle: Text(
            '${type.tasks.length} recommended '
            '${type.tasks.length == 1 ? 'task' : 'tasks'}',
          ),
          onTap: () => _open(HomeItemFormScreen(initialType: type)),
        ),
    ];
  }
}
