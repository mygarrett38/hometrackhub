import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/equipment.dart';
import '../../models/equipment_task.dart';
import '../../state/equipment_controller.dart';
import '../widgets/category_icon.dart';
import '../widgets/task_tile.dart';
import 'equipment_form_screen.dart';
import 'task_form_screen.dart';

/// Shows one piece of equipment and its maintenance schedule.
class EquipmentDetailScreen extends StatelessWidget {
  const EquipmentDetailScreen({super.key, required this.equipmentId});

  final String equipmentId;

  @override
  Widget build(BuildContext context) {
    final equipment = context.watch<EquipmentController>().findById(
      equipmentId,
    );

    // The equipment may have just been deleted.
    if (equipment == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This equipment no longer exists.')),
      );
    }

    final tasks = [
      for (final task in equipment.tasks) EquipmentTask(equipment, task),
    ]..sort((a, b) => a.dueDate.compareTo(b.dueDate));

    return Scaffold(
      appBar: AppBar(
        title: Text(equipment.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit details',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => EquipmentFormScreen(existing: equipment),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete equipment',
            onPressed: () => _confirmDelete(context, equipment),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TaskFormScreen(equipmentId: equipment.id),
          ),
        ),
        icon: const Icon(Icons.add_task),
        label: const Text('Add task'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          _DetailsCard(equipment: equipment),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'Maintenance schedule',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (tasks.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No maintenance tasks yet. Tap "Add task" to create one.',
              ),
            ),
          for (final item in tasks)
            TaskTile(
              item: item,
              showEquipmentName: false,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TaskFormScreen(
                    equipmentId: equipment.id,
                    existing: item.task,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Equipment equipment) async {
    final controller = context.read<EquipmentController>();
    final navigator = Navigator.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${equipment.name}?'),
        content: const Text(
          'This also deletes its maintenance history and reminders.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      navigator.pop();
      await controller.deleteEquipment(equipment.id);
    }
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.equipment});

  final Equipment equipment;

  @override
  Widget build(BuildContext context) {
    final purchaseDate = equipment.purchaseDate;
    final details = <(String, String)>[
      ('Category', equipment.category.label),
      if (equipment.manufacturer.isNotEmpty)
        ('Manufacturer', equipment.manufacturer),
      if (equipment.modelNumber.isNotEmpty) ('Model', equipment.modelNumber),
      if (equipment.serialNumber.isNotEmpty)
        ('Serial number', equipment.serialNumber),
      if (equipment.location.isNotEmpty) ('Location', equipment.location),
      if (purchaseDate != null)
        (
          'Purchased',
          MaterialLocalizations.of(context).formatMediumDate(purchaseDate),
        ),
      if (equipment.notes.isNotEmpty) ('Notes', equipment.notes),
    ];

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(equipment.category.icon),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    equipment.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final (label, value) in details)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('$label: $value'),
              ),
          ],
        ),
      ),
    );
  }
}
