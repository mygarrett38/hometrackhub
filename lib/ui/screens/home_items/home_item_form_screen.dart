import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/home_item_catalog.dart';
import '../../../data/home_locations.dart';
import '../../../models/home_item.dart';
import '../../../models/home_item_category.dart';
import '../../../models/maintenance_task.dart';
import '../../../services/device_discovery_service.dart';
import '../../../state/home_item_controller.dart';
import '../../../utils/date_utils.dart';
import '../../../utils/id_generator.dart';
import '../../widgets/date_field.dart';
import 'home_item_detail_screen.dart';
import 'task_form_screen.dart';

/// Form for adding a new home item or editing an existing one.
///
/// A new home item can start from a catalog type ([initialType]), from a
/// device found on the network ([discoveredDevice]), or from scratch within
/// a chosen category ([initialCategory]). The category and recommended
/// maintenance come from where the user started and can't be changed here.
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

  /// Tasks to create with a new home item, including any changes the user
  /// made to them before saving.
  List<MaintenanceTask> _newTasks = [];

  /// Ids of tasks in [_newTasks] that the user unticked.
  final Set<String> _skippedTaskIds = {};

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

    if (existing == null) {
      _newTasks =
          _template?.createTasks(startDate: dateOnly(DateTime.now())) ?? [];
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
          [
            for (final task in _newTasks)
              if (!_skippedTaskIds.contains(task.id)) task,
          ],
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

  /// Opens the task form for one of the new tasks, or for a new custom task
  /// when [task] is `null`, and keeps the result if the user saves it.
  Future<void> _editNewTask([MaintenanceTask? task]) async {
    final edited = await Navigator.of(context).push<MaintenanceTask>(
      MaterialPageRoute(builder: (_) => TaskFormScreen.unsaved(existing: task)),
    );
    if (edited == null) return;
    setState(() {
      final index = _newTasks.indexWhere((t) => t.id == edited.id);
      if (index == -1) {
        _newTasks = [..._newTasks, edited];
      } else {
        _newTasks = [..._newTasks]..[index] = edited;
      }
      // Changing or adding a task means the user wants it.
      _skippedTaskIds.remove(edited.id);
    });
  }

  /// The default home locations followed by any other locations the user
  /// has typed for their home items.
  List<String> _locationChoices() {
    final choices = [...defaultHomeLocations];
    for (final homeItem in context.read<HomeItemController>().homeItems) {
      final location = homeItem.location.trim();
      final alreadyListed = choices.any(
        (choice) => choice.toLowerCase() == location.toLowerCase(),
      );
      if (location.isNotEmpty && !alreadyListed) choices.add(location);
    }
    return choices;
  }

  @override
  Widget build(BuildContext context) {
    const divider = Divider(height: 1, indent: 16);
    final isVehicle = _category == HomeItemCategory.vehicle;
    final hasDetails = [
      _manufacturer,
      _modelNumber,
      _serialNumber,
    ].any((controller) => controller.text.isNotEmpty);

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
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _InlineTextRow(
                    label: 'Name',
                    controller: _name,
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                        ? 'Please enter a name'
                        : null,
                  ),
                  divider,
                  _InlineTextRow(
                    label: 'Location',
                    controller: _location,
                    choices: _locationChoices(),
                  ),
                  divider,
                  _InlineDateRow(
                    label: 'Purchase date',
                    value: _purchaseDate,
                    onChanged: (date) => setState(() => _purchaseDate = date),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  ExpansionTile(
                    title: const Text('Details'),
                    // Start open when there is something to show, such as
                    // when editing or adding a device found by scanning.
                    initiallyExpanded: hasDetails,
                    // The card already draws the outline, so the tile
                    // shouldn't add its own borders when expanded.
                    shape: const Border(),
                    collapsedShape: const Border(),
                    children: [
                      divider,
                      _InlineTextRow(
                        label: isVehicle ? 'Make' : 'Manufacturer',
                        controller: _manufacturer,
                      ),
                      divider,
                      _InlineTextRow(label: 'Model', controller: _modelNumber),
                      divider,
                      _InlineTextRow(
                        label: isVehicle ? 'VIN' : 'Serial #',
                        controller: _serialNumber,
                      ),
                    ],
                  ),
                  divider,
                  _NotesRow(controller: _notes),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (!_isEditing)
              _NewTaskList(
                tasks: _newTasks,
                skippedTaskIds: _skippedTaskIds,
                onSelected: (task, selected) => setState(
                  () => selected
                      ? _skippedTaskIds.remove(task.id)
                      : _skippedTaskIds.add(task.id),
                ),
                onEdit: _editNewTask,
                onAdd: _editNewTask,
              ),
          ],
        ),
      ),
    );
  }
}

/// Form rows are at least as tall as a [ListTile].
const _rowHeight = 56.0;

/// A form row with the label on the left and a borderless text field on
/// the right that is edited in place.
///
/// If [choices] are given, a menu button at the end of the row fills the
/// field with one of them. The user can still type their own value.
class _InlineTextRow extends StatelessWidget {
  const _InlineTextRow({
    required this.label,
    required this.controller,
    this.validator,
    this.choices = const [],
  });

  final String label;
  final TextEditingController controller;
  final FormFieldValidator<String>? validator;
  final List<String> choices;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 16, right: choices.isEmpty ? 16 : 4),
      child: Row(
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(width: 16),
          Expanded(
            child: TextFormField(
              controller: controller,
              validator: validator,
              textAlign: TextAlign.end,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Unknown',
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          if (choices.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Icons.arrow_drop_down),
              tooltip: 'Choose ${label.toLowerCase()}',
              onSelected: (choice) => controller.text = choice,
              itemBuilder: (context) => [
                for (final choice in choices)
                  PopupMenuItem(value: choice, child: Text(choice)),
              ],
            ),
        ],
      ),
    );
  }
}

/// A form row that shows a date on the right and opens a date picker
/// when tapped.
class _InlineDateRow extends StatelessWidget {
  const _InlineDateRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = value;

    return InkWell(
      onTap: () async {
        final picked = await pickPastDate(context, initialDate: date);
        if (picked != null) onChanged(picked);
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _rowHeight),
        child: Padding(
          padding: EdgeInsets.only(left: 16, right: date == null ? 16 : 4),
          child: Row(
            children: [
              Text(label, style: theme.textTheme.bodyLarge),
              const Spacer(),
              Text(
                date == null
                    ? 'Unknown'
                    : MaterialLocalizations.of(context).formatMediumDate(date),
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: date == null
                      ? theme.colorScheme.onSurfaceVariant
                      : null,
                ),
              ),
              if (date != null)
                IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: 'Clear date',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => onChanged(null),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A form row with a label and a multi-line notes field below it.
class _NotesRow extends StatelessWidget {
  const _NotesRow({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Notes', style: Theme.of(context).textTheme.bodyLarge),
          TextFormField(
            controller: controller,
            minLines: 3,
            maxLines: null,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Add notes',
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ],
      ),
    );
  }
}

/// The maintenance tasks that will be created with a new home item. Each
/// can be ticked or unticked, and tapped to change it before saving.
class _NewTaskList extends StatelessWidget {
  const _NewTaskList({
    required this.tasks,
    required this.skippedTaskIds,
    required this.onSelected,
    required this.onEdit,
    required this.onAdd,
  });

  final List<MaintenanceTask> tasks;
  final Set<String> skippedTaskIds;
  final void Function(MaintenanceTask task, bool selected) onSelected;
  final ValueChanged<MaintenanceTask> onEdit;
  final VoidCallback onAdd;

  /// For example "Every 3 months", noting when the user has changed the
  /// manufacturer's recommended interval.
  String _describeInterval(MaintenanceTask task) {
    final interval = task.interval.label;
    return task.isCustom || task.followsRecommendation
        ? interval
        : '$interval (recommended: ${task.recommendedInterval!.label.toLowerCase()})';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Maintenance tasks', style: theme.textTheme.titleMedium),
          ),
          for (final task in tasks)
            ListTile(
              // Keeps the checkbox lined up with the heading's left edge.
              contentPadding: const EdgeInsets.only(left: 8, right: 16),
              horizontalTitleGap: 8,
              leading: Checkbox(
                visualDensity: VisualDensity.standard,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                value: !skippedTaskIds.contains(task.id),
                onChanged: (selected) => onSelected(task, selected ?? false),
              ),
              title: Text(task.title),
              subtitle: Text(_describeInterval(task)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onEdit(task),
            ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Add task'),
            onTap: onAdd,
          ),
        ],
      ),
    );
  }
}
