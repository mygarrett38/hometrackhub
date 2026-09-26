import 'package:flutter/material.dart';

import '../../data/equipment_catalog.dart';
import '../../models/equipment_category.dart';
import '../widgets/category_icon.dart';
import 'equipment_form_screen.dart';

/// Lets the user pick a common kind of equipment from the built-in catalog.
class EquipmentTypePickerScreen extends StatefulWidget {
  const EquipmentTypePickerScreen({super.key});

  @override
  State<EquipmentTypePickerScreen> createState() =>
      _EquipmentTypePickerScreenState();
}

class _EquipmentTypePickerScreenState extends State<EquipmentTypePickerScreen> {
  String _search = '';

  void _open(Widget screen) {
    Navigator.of(context)
        .pushReplacement(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.trim().toLowerCase();
    final matches = equipmentCatalog
        .where((type) => type.name.toLowerCase().contains(query))
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Choose equipment type')),
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
            title: const Text('Not listed? Create custom equipment'),
            onTap: () => _open(const EquipmentFormScreen()),
          ),
          const Divider(),
          for (final category in EquipmentCategory.values)
            ..._categorySection(category, matches),
        ],
      ),
    );
  }

  List<Widget> _categorySection(
    EquipmentCategory category,
    List<EquipmentType> matches,
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
          onTap: () => _open(EquipmentFormScreen(initialType: type)),
        ),
    ];
  }
}
