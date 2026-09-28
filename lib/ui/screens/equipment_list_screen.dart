import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/equipment.dart';
import '../../models/equipment_category.dart';
import '../../state/equipment_controller.dart';
import '../../utils/date_utils.dart';
import '../widgets/category_icon.dart';
import 'device_discovery_screen.dart';
import 'equipment_detail_screen.dart';
import 'equipment_form_screen.dart';
import 'equipment_type_picker_screen.dart';

/// Equipment tab: everything the user tracks, grouped by category.
class EquipmentListScreen extends StatelessWidget {
  const EquipmentListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final equipment = context.watch<EquipmentController>().equipment;

    return Scaffold(
      appBar: AppBar(title: const Text('My equipment')),
      floatingActionButton: FloatingActionButton(
        heroTag: 'equipment_fab',
        onPressed: () => _showAddOptions(context),
        child: const Icon(Icons.add)
      ),
      body: equipment.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'You are not tracking any equipment yet.\n\n'
                  'Tap "Add equipment" to pick a common appliance or '
                  'vehicle, create your own, or find smart devices on '
                  'your Wi-Fi network.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              // Leave room so the last item isn't hidden by the button.
              padding: const EdgeInsets.only(bottom: 88),
              children: [
                for (final category in EquipmentCategory.values)
                  ..._categorySection(context, category, equipment),
              ],
            ),
    );
  }

  List<Widget> _categorySection(
    BuildContext context,
    EquipmentCategory category,
    List<Equipment> allEquipment,
  ) {
    final items = allEquipment
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
      for (final item in items) _EquipmentTile(equipment: item),
    ];
  }

  void _showAddOptions(BuildContext context) {
    final navigator = Navigator.of(context);

    void openScreen(Widget screen) {
      navigator.pop(); // Close the bottom sheet first.
      navigator.push(MaterialPageRoute<void>(builder: (_) => screen));
    }

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.list_alt),
              title: const Text('Choose a common type'),
              subtitle: const Text(
                'Appliances, vehicles and more, with the manufacturer\'s '
                'recommended maintenance already filled in.',
              ),
              onTap: () => openScreen(const EquipmentTypePickerScreen()),
            ),
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('Create custom equipment'),
              subtitle: const Text(
                'Describe anything else and set up your own maintenance tasks.',
              ),
              onTap: () => openScreen(const EquipmentFormScreen()),
            ),
            ListTile(
              leading: const Icon(Icons.wifi_find),
              title: const Text('Find smart devices on my network'),
              subtitle: const Text(
                'Scan your Wi-Fi network for smart TVs, speakers, hubs and '
                'more.',
              ),
              onTap: () => openScreen(const DeviceDiscoveryScreen()),
            ),
          ],
        ),
      ),
    );
  }
}

class _EquipmentTile extends StatelessWidget {
  const _EquipmentTile({required this.equipment});

  final Equipment equipment;

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(DateTime.now());
    final nextDue = equipment.tasks.isEmpty
        ? null
        : equipment.tasks
              .map((task) => task.nextDueDate)
              .reduce((a, b) => a.isBefore(b) ? a : b);

    final makeAndModel = [
      equipment.manufacturer,
      equipment.modelNumber,
    ].where((part) => part.isNotEmpty).join(' ');
    final taskCount = equipment.tasks.length;
    final subtitle = [
      if (makeAndModel.isNotEmpty) makeAndModel,
      if (equipment.location.isNotEmpty) equipment.location,
      '$taskCount ${taskCount == 1 ? 'task' : 'tasks'}',
      if (nextDue != null) 'Next: ${describeDueDate(nextDue, today)}',
    ].join(' · ');

    return ListTile(
      leading: Icon(equipment.category.icon),
      title: Text(equipment.name),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => EquipmentDetailScreen(equipmentId: equipment.id),
        ),
      ),
    );
  }
}
