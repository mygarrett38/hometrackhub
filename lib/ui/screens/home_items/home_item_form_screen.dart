import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/home_item_catalog.dart';
import '../../../data/home_locations.dart';
import '../../../models/home_item.dart';
import '../../../models/home_item_category.dart';
import '../../../models/home_item_task.dart';
import '../../../models/maintenance_task.dart';
import '../../../services/device_discovery_service.dart';
import '../../../state/home_item_controller.dart';
import '../../../utils/date_utils.dart';
import '../../../utils/id_generator.dart';
import '../../widgets/form_rows.dart';
import '../../widgets/task_tile.dart';
import '../../widgets/screen_padding.dart';
import 'task_form_screen.dart';

/// Form for adding a new home item or editing an existing one. When editing,
/// it also shows the item's maintenance schedule and can delete the item.
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

    // Tasks on an existing home item are saved as soon as they're changed,
    // so use the latest ones rather than those from when this form opened.
    final existingTasks = existing == null
        ? null
        : controller.findById(existing.id)?.tasks ?? existing.tasks;
    final existingExpenses = existing == null
        ? null
        : controller.findById(existing.id)?.expenses ?? existing.expenses;

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
          existingTasks ??
          [
            for (final task in _newTasks)
              if (!_skippedTaskIds.contains(task.id)) task,
          ],
      expenses: existingExpenses ?? const [],
    );

    if (existing != null) {
      await controller.updateHomeItem(homeItem);
      navigator.pop();
    } else {
      await controller.addHomeItem(homeItem);
      if (widget.discoveredDevice != null) {
        // Return to the scan results so the user can add more devices.
        navigator.pop();
      } else {
        // Skip the category and type pickers and return to the main screen.
        navigator.popUntil((route) => route.isFirst);
      }
    }
  }

  Future<void> _confirmDelete() async {
    final homeItem = widget.existing!;
    final controller = context.read<HomeItemController>();
    final navigator = Navigator.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${homeItem.name}?'),
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
      await controller.deleteHomeItem(homeItem.id);
    }
  }

  /// The name to show on this home item's task screens: whatever the user
  /// has typed so far, even if it isn't saved yet.
  String get _currentName {
    final name = _name.text.trim();
    if (name.isNotEmpty) return name;
    return widget.existing?.name ?? 'New ${_category.itemName}';
  }

  /// Opens the task form for one of the new tasks, or for a new custom task
  /// when [task] is `null`, and keeps the result if the user saves it.
  Future<void> _editNewTask([MaintenanceTask? task]) async {
    final edited = await Navigator.of(context).push<MaintenanceTask>(
      MaterialPageRoute(
        builder: (_) =>
            TaskFormScreen.unsaved(homeItemName: _currentName, existing: task),
      ),
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
    const divider = formRowDivider;
    final isVehicle = _category == HomeItemCategory.vehicle;
    final hasDetails = [
      _manufacturer,
      _modelNumber,
      _serialNumber,
    ].any((controller) => controller.text.isNotEmpty);

    return Scaffold(
      appBar: AppBar(
        title: Text('${_isEditing ? 'Edit' : 'Add'} ${_category.itemName}'),
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete home item',
              onPressed: _confirmDelete,
            ),
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: screenPadding(context),
          children: [
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  InlineTextRow(
                    label: 'Name',
                    controller: _name,
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                        ? 'Please enter a name'
                        : null,
                  ),
                  divider,
                  InlineTextRow(
                    label: 'Location',
                    controller: _location,
                    choices: _locationChoices(),
                  ),
                  divider,
                  InlineDateRow(
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
                      InlineTextRow(
                        label: isVehicle ? 'Make' : 'Manufacturer',
                        controller: _manufacturer,
                      ),
                      divider,
                      InlineTextRow(label: 'Model', controller: _modelNumber),
                      divider,
                      InlineTextRow(
                        label: isVehicle ? 'VIN' : 'Serial #',
                        controller: _serialNumber,
                      ),
                    ],
                  ),
                  divider,
                  InlineNotesRow(controller: _notes),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (widget.existing case final existing?)
              _SavedTaskList(
                homeItemId: existing.id,
                homeItemName: () => _currentName,
              )
            else
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

/// The maintenance schedule of a home item being edited. Tasks are saved as
/// soon as they're changed, added or marked done.
class _SavedTaskList extends StatelessWidget {
  const _SavedTaskList({required this.homeItemId, required this.homeItemName});

  final String homeItemId;

  /// The home item's name as currently typed on the form.
  final ValueGetter<String> homeItemName;

  void _openTask(BuildContext context, [MaintenanceTask? task]) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TaskFormScreen(
          homeItemId: homeItemId,
          homeItemName: homeItemName(),
          existing: task,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HomeItemController>();
    final homeItem = controller.findById(homeItemId);
    // The home item may have just been deleted.
    if (homeItem == null) return const SizedBox.shrink();

    final tasks = controller.orderForList([
      for (final task in homeItem.tasks) HomeItemTask(homeItem, task),
    ]);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Maintenance tasks',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final item in tasks)
            TaskTile(
              item: item,
              showHomeItemName: false,
              onTap: () => _openTask(context, item.task),
            ),
          const Divider(height: 1),
          _AddTaskButton(onPressed: () => _openTask(context)),
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
            child: Text(
              'Maintenance tasks',
              style: theme.textTheme.titleMedium,
            ),
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
          _AddTaskButton(onPressed: onAdd),
        ],
      ),
    );
  }
}

/// A centered + button at the bottom of a task list.
class _AddTaskButton extends StatelessWidget {
  const _AddTaskButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: IconButton(
          icon: const Icon(Icons.add),
          tooltip: 'Add task',
          onPressed: onPressed,
        ),
      ),
    );
  }
}
