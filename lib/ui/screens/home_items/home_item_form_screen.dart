import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/home_item_catalog.dart';
import '../../../models/home_item.dart';
import '../../../models/home_item_category.dart';
import '../../../services/device_discovery_service.dart';
import '../../../state/home_item_controller.dart';
import '../../../utils/date_utils.dart';
import '../../../utils/id_generator.dart';
import '../../widgets/date_field.dart';
import '../../widgets/dropdown_field.dart';
import 'home_item_detail_screen.dart';

/// Form for adding a new home item or editing an existing one.
///
/// A new home item can start from a catalog type ([initialType]), from a
/// device found on the network ([discoveredDevice]), or from scratch,
/// optionally within a chosen category ([initialCategory]).
class HomeItemFormScreen extends StatefulWidget {
  const HomeItemFormScreen({
    super.key,
    this.existing,
    this.initialType,
    this.initialCategory,
    this.discoveredDevice,
  });

  /// The home item being edited, or `null` when adding a new one.
  final HomeItem? existing;
  final HomeItemType? initialType;

  /// The category selected when creating a custom home item.
  final HomeItemCategory? initialCategory;
  final DiscoveredDevice? discoveredDevice;

  @override
  State<HomeItemFormScreen> createState() => _HomeItemFormScreenState();
}

class _HomeItemFormScreenState extends State<HomeItemFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _manufacturer = TextEditingController();
  final _modelNumber = TextEditingController();
  final _serialNumber = TextEditingController();
  final _location = TextEditingController();
  final _notes = TextEditingController();

  HomeItemCategory _category = HomeItemCategory.custom;
  DateTime? _purchaseDate;

  /// The catalog type whose recommended tasks will be added. Only used when
  /// adding a new home item.
  HomeItemType? _template;

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
      _template = findHomeItemType(device.suggestedTypeId);
      _name.text = device.name;
      _manufacturer.text = device.manufacturer;
      _modelNumber.text = device.model;
      _category = HomeItemCategory.smartDevice;
      if (device.address != null) {
        _notes.text = 'Network address: ${device.address}';
      }
    } else if (widget.initialType != null) {
      _template = widget.initialType;
      _name.text = widget.initialType!.name;
      _category = widget.initialType!.category;
    } else if (widget.initialCategory != null) {
      _category = widget.initialCategory!;
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

  void _changeTemplate(HomeItemType? newTemplate) {
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

    final controller = context.read<HomeItemController>();
    final navigator = Navigator.of(context);
    final existing = widget.existing;

    final homeItem = HomeItem(
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
      await controller.updateHomeItem(homeItem);
      navigator.pop();
    } else {
      await controller.addHomeItem(homeItem);
      // Show the new home item so the user can review or add tasks.
      final detailRoute = MaterialPageRoute<void>(
        builder: (_) => HomeItemDetailScreen(homeItemId: homeItem.id),
      );
      if (widget.discoveredDevice != null) {
        // Going back returns to the scan results to add more devices.
        navigator.pushReplacement(detailRoute);
      } else {
        // Going back skips the category and type pickers and returns to
        // the list of home items.
        navigator.pushAndRemoveUntil(detailRoute, (route) => route.isFirst);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 16);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit home item' : 'Add home item'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!_isEditing) ...[
              DropdownField<HomeItemType?>(
                label: 'Maintenance recommendations',
                value: _template,
                onChanged: _changeTemplate,
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('None - I\'ll add my own tasks'),
                  ),
                  for (final type in homeItemCatalog)
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
            DropdownField<HomeItemCategory>(
              label: 'Category',
              value: _category,
              onChanged: (value) => setState(() => _category = value),
              items: [
                for (final category in HomeItemCategory.values)
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

/// Shows which maintenance tasks will be added with the new home item.
class _TaskPreview extends StatelessWidget {
  const _TaskPreview({required this.template});

  final HomeItemType? template;

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
