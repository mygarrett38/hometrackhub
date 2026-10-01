import 'package:flutter/material.dart';

import '../../../data/home_item_catalog.dart';
import '../../../models/home_item_category.dart';
import '../../widgets/category_icon.dart';
import 'device_discovery_screen.dart';
import 'home_item_form_screen.dart';

/// Lets the user pick a common appliance or device within one [category]
/// from the built-in catalog.
class HomeItemTypePickerScreen extends StatelessWidget {
  const HomeItemTypePickerScreen({super.key, required this.category});

  final HomeItemCategory category;

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final types = catalogTypesIn(category);

    return Scaffold(
      appBar: AppBar(title: Text(category.label)),
      body: ListView(
        children: [
          for (final type in types)
            ListTile(
              leading: Icon(category.icon),
              title: Text(type.name),
              subtitle: Text(
                '${type.tasks.length} recommended '
                '${type.tasks.length == 1 ? 'task' : 'tasks'}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  _open(context, HomeItemFormScreen(initialType: type)),
            ),
          if (types.isNotEmpty) const Divider(),
          ListTile(
            leading: const Icon(Icons.edit_note),
            title: Text(
              types.isEmpty
                  ? 'Create custom home item'
                  : 'Not listed? Create custom home item',
            ),
            onTap: () =>
                _open(context, HomeItemFormScreen(initialCategory: category)),
          ),
          if (category == HomeItemCategory.smartDevice)
            ListTile(
              leading: const Icon(Icons.wifi_find),
              title: const Text('Find smart devices on my network'),
              onTap: () => _open(context, const DeviceDiscoveryScreen()),
            ),
        ],
      ),
    );
  }
}
