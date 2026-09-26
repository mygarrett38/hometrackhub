import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/equipment_catalog.dart';
import '../../models/equipment.dart';
import '../../models/equipment_category.dart';
import '../../services/device_discovery_service.dart';
import '../../state/equipment_controller.dart';
import '../../utils/date_utils.dart';
import '../../utils/id_generator.dart';
import '../widgets/date_field.dart';
import '../widgets/dropdown_field.dart';
import 'equipment_detail_screen.dart';

/// Form for adding new equipment or editing existing equipment.
///
/// New equipment can start from a catalog type ([initialType]), from a
/// device found on the network ([discoveredDevice]), or from scratch.
class EquipmentFormScreen extends StatefulWidget {
  const EquipmentFormScreen({
    super.key,
    this.existing,
    this.initialType,
    this.discoveredDevice,
  });

  /// The equipment being edited, or `null` when adding new equipment.
  final Equipment? existing;
  final EquipmentType? initialType;
  final DiscoveredDevice? discoveredDevice;

  @override
  State<EquipmentFormScreen> createState() => _EquipmentFormScreenState();
}

class _EquipmentFormScreenState extends State<EquipmentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _manufacturer = TextEditingController();
  final _modelNumber = TextEditingController();
  final _serialNumber = TextEditingController();
  final _location = TextEditingController();
  final _notes = TextEditingController();

  EquipmentCategory _category = EquipmentCategory.other;
  DateTime? _purchaseDate;

  /// The catalog type whose recommended tasks will be added. Only used when
  /// adding new equipment.
  EquipmentType? _template;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final device = widget.discoveredDevice;

    if (existing != null) {
      _name.text = existing.name;
      _manufacturer.text = existing.manufacturer;
      _modelNumber.text = existing.modelNumber;
      _serialNumber.text = existing.serialNumber;
      _location.text = existing.location;
      _notes.text = existing.notes;
      _category = existing.category;
      _purchaseDate = existing.purchaseDate;
    } else if (device != null) {
      _template = findEquipmentType(device.suggestedTypeId);
      _name.text = device.name;
      _manufacturer.text = device.manufacturer;
      _modelNumber.text = device.model;
      _category = EquipmentCategory.smartDevice;
      if (device.address != null) {
        _notes.text = 'Network address: ${device.address}';
      }
    } else if (widget.initialType != null) {
      _template = widget.initialType;
      _name.text = widget.initialType!.name;
      _category = widget.initialType!.category;
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _manufacturer,
      _modelNumber,
      _serialNumber,
      _location,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _changeTemplate(EquipmentType? newTemplate) {
    setState(() {
      // Replace the name only if the user hasn't typed their own.
      final nameIsDefault =
          _name.text.trim().isEmpty || _name.text == _template?.name;
      if (newTemplate != null && nameIsDefault) {
        _name.text = newTemplate.name;
      }
      if (newTemplate != null) _category = newTemplate.category;
      _template = newTemplate;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final controller = context.read<EquipmentController>();
    final navigator = Navigator.of(context);
    final existing = widget.existing;

    final equipment = Equipment(
      id: existing?.id ?? generateId(),
      name: _name.text.trim(),
      category: _category,
      catalogTypeId: existing != null ? existing.catalogTypeId : _template?.id,
      manufacturer: _manufacturer.text.trim(),
      modelNumber: _modelNumber.text.trim(),
      serialNumber: _serialNumber.text.trim(),
      location: _location.text.trim(),
      notes: _notes.text.trim(),
      purchaseDate: _purchaseDate,
      networkId: existing?.networkId ?? widget.discoveredDevice?.id,
      tasks:
          existing?.tasks ??
          _template?.createTasks(startDate: dateOnly(DateTime.now())) ??
          [],
    );

    if (existing != null) {
      await controller.updateEquipment(equipment);
      navigator.pop();
    } else {
      await controller.addEquipment(equipment);
      // Show the new equipment so the user can review or add tasks.
      navigator.pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => EquipmentDetailScreen(equipmentId: equipment.id),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 16);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit equipment' : 'Add equipment'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!_isEditing) ...[
              DropdownField<EquipmentType?>(
                label: 'Maintenance recommendations',
                value: _template,
                onChanged: _changeTemplate,
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('None - I\'ll add my own tasks'),
                  ),
                  for (final type in equipmentCatalog)
                    DropdownMenuItem(value: type, child: Text(type.name)),
                ],
              ),
              gap,
            ],
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Kitchen refrigerator',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.sentences,
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Please enter a name'
                  : null,
            ),
            gap,
            DropdownField<EquipmentCategory>(
              label: 'Category',
              value: _category,
              onChanged: (value) => setState(() => _category = value),
              items: [
                for (final category in EquipmentCategory.values)
                  DropdownMenuItem(
                    value: category,
                    child: Text(category.label),
                  ),
              ],
            ),
            gap,
            _textField(_manufacturer, 'Manufacturer / make'),
            gap,
            _textField(_modelNumber, 'Model'),
            gap,
            _textField(_serialNumber, 'Serial number or VIN'),
            gap,
            _textField(_location, 'Location', hint: 'e.g. Kitchen, Garage'),
            gap,
            DateField(
              label: 'Purchase date',
              value: _purchaseDate,
              onChanged: (date) => setState(() => _purchaseDate = date),
            ),
            gap,
            _textField(_notes, 'Notes', maxLines: 3),
            gap,
            if (!_isEditing) _TaskPreview(template: _template),
          ],
        ),
      ),
    );
  }

  Widget _textField(
    TextEditingController controller,
    String label, {
    String? hint,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

/// Shows which maintenance tasks will be added with the new equipment.
class _TaskPreview extends StatelessWidget {
  const _TaskPreview({required this.template});

  final EquipmentType? template;

  @override
  Widget build(BuildContext context) {
    final template = this.template;
    if (template == null) {
      return const Text('You can add your own maintenance tasks after saving.');
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recommended maintenance',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text(
              'These tasks will be added using the manufacturer\'s '
              'recommended schedule. You can change or remove them after '
              'saving.',
            ),
            const SizedBox(height: 8),
            for (final task in template.tasks)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('• ${task.title} - ${task.interval.label}'),
              ),
          ],
        ),
      ),
    );
  }
}
