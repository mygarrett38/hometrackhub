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
    // Matches the style ListTile uses for subtitles.
    final theme = Theme.of(context);
    final countStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Scaffold(
      appBar: AppBar(title: Text(category.label)),
      body: ListView(
        children: [
          for (final type in types)
            ListTile(
              leading: Icon(category.icon),
              title: Text(type.name),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${type.tasks.length}', style: countStyle),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right),
                ],
              ),
              onTap: () =>
                  _open(context, HomeItemFormScreen(initialType: type)),
            ),
          if (category == HomeItemCategory.smartDevice) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.wifi_find),
              title: const Text('Find smart devices nearby'),
              onTap: () => _open(context, const DeviceDiscoveryScreen()),
            ),
          ],
        ],
      ),
    );
  }
}
