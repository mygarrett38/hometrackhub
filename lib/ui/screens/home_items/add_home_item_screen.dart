import 'package:flutter/material.dart';

import '../../../data/home_item_catalog.dart';
import '../../../models/home_item_category.dart';
import '../../widgets/category_icon.dart';
import 'device_discovery_screen.dart';
import 'home_item_form_screen.dart';
import 'home_item_type_picker_screen.dart';

/// First step of adding a home item: the user picks a category, then a
/// common type within it on [HomeItemTypePickerScreen].
///
/// Categories with no catalog types (such as Custom) go straight to the
/// home item form. Also offers scanning for nearby devices.
class AddHomeItemScreen extends StatelessWidget {
  const AddHomeItemScreen({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add to My Home')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.wifi_find),
            title: const Text('Find nearby devices'),
            subtitle: const Text('Scan for devices via Wi-Fi or Bluetooth'),
            onTap: () => _open(context, const DeviceDiscoveryScreen()),
          ),
          const Divider(),
          for (final category in HomeItemCategory.values)
            ListTile(
              leading: Icon(category.icon),
              title: Text(category.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(
                context,
                catalogTypesIn(category).isEmpty
                    ? HomeItemFormScreen(initialCategory: category)
                    : HomeItemTypePickerScreen(category: category),
              ),
            ),
        ],
      ),
    );
  }
}
