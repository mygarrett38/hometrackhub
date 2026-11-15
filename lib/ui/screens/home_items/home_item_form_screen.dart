import 'dart:async';

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
import '../../../state/settings_controller.dart';
import '../../../utils/date_utils.dart';
import '../../../utils/id_generator.dart';
import '../../widgets/form_rows.dart';
import '../../widgets/task_tile.dart';
import '../../widgets/screen_padding.dart';
import 'task_form_screen.dart';

/// Form for adding a new home item or editing an existing one. When editing,
/// it also shows the item's maintenance schedule and can delete the item.
///
/// Changes to an existing home item are saved as they're made, with no Save
/// button. A new home item is only created when the user taps Add; going
/// back without tapping it discards it.
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

/// The values of a home item's fields, to tell whether they've changed
/// since they were last saved.
typedef _HomeItemFields = ({
  String name,
  String manufacturer,
  String modelNumber,
  String serialNumber,
  String location,
  String notes,
  DateTime? purchaseDate,
});

class _HomeItemFormScreenState extends State<HomeItemFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final HomeItemController _homeItems;

  /// Saves typed changes once the user pauses.
  Timer? _saveTimer;

  /// The fields as they were last saved, for an existing home item.
  _HomeItemFields? _savedFields;

  /// Set once the home item is deleted, so nothing saves it again.
  bool _deleted = false;
  final _name = TextEditingController();
  final _manufacturer = TextEditingController();
  final _modelNumber = TextEditingController();
  final _serialNumber = TextEditingController();
  final _location = TextEditingController();
  final _notes = TextEditingController();

  HomeItemCategory _category = HomeItemCategory.custom;
  DateTime? _purchaseDate;

  /// The catalog type whose recommended tasks the user can add. Only used
  /// when adding a new home item.
  HomeItemType? _template;

  /// The catalog type's recommended tasks, created once so that adding them
  /// again after removing some doesn't duplicate the others.
  List<MaintenanceTask> _recommendedTasks = [];

  /// Tasks to create with a new home item, including any changes the user
  /// made to them before saving.
  List<MaintenanceTask> _newTasks = [];

  bool get _isEditing => widget.existing != null;

  /// Whether the VIN or serial number is always hidden, from the privacy
  /// settings. Read once so changing the setting doesn't affect an open form.
  late final bool _hideSerialNumber;

  /// Whether the VIN or serial number is hidden right now. When the setting
  /// is off, the user can hide or show it with the eye button.
  late bool _serialNumberObscured = _hideSerialNumber;

  /// A new home item's serial number can always be typed in. An existing
  /// one can only be changed while it's shown.
  bool get _serialNumberReadOnly => _isEditing && _serialNumberObscured;

  @override
  void initState() {
    super.initState();
    _homeItems = context.read<HomeItemController>();
    _hideSerialNumber = context
        .read<SettingsController>()
        .settings
        .hideSerialNumbers;
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
      _recommendedTasks =
          _template?.createTasks(startDate: dateOnly(DateTime.now())) ?? [];
    } else {
      _savedFields = _fields;
      for (final controller in _textControllers) {
        controller.addListener(_scheduleSave);
      }
    }
  }

  List<TextEditingController> get _textControllers => [
    _name,
    _manufacturer,
    _modelNumber,
    _serialNumber,
    _location,
    _notes,
  ];

  _HomeItemFields get _fields => (
    name: _name.text.trim(),
    manufacturer: _manufacturer.text.trim(),
    modelNumber: _modelNumber.text.trim(),
    serialNumber: _serialNumber.text.trim(),
    location: _location.text.trim(),
    notes: _notes.text.trim(),
    purchaseDate: _purchaseDate,
  );

  /// Saves the typed changes to an existing home item once the user pauses.
  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(autosaveDelay, _saveChanges);
  }

  /// Saves any changes to an existing home item. Nothing is saved while the
  /// name is empty; the form shows why instead.
  void _saveChanges() {
    _saveTimer?.cancel();
    if (!_isEditing || _deleted) return;
    final fields = _fields;
    if (fields == _savedFields || fields.name.isEmpty) return;
    _savedFields = fields;
    _homeItems.updateHomeItem(_buildHomeItem());
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
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

  /// The home item as entered on the form.
  HomeItem _buildHomeItem() {
    final controller = _homeItems;
    final existing = widget.existing;

    // Tasks on an existing home item are saved as soon as they're changed,
    // so use the latest ones rather than those from when this form opened.
    final existingTasks = existing == null
        ? null
        : controller.findById(existing.id)?.tasks ?? existing.tasks;
    final existingExpenses = existing == null
        ? null
        : controller.findById(existing.id)?.expenses ?? existing.expenses;

    return HomeItem(
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
      tasks: existingTasks ?? _newTasks,
      expenses: existingExpenses ?? const [],
    );
  }

  /// Creates the new home item, if the form is filled in correctly.
  Future<void> _add() async {
    if (!_formKey.currentState!.validate()) return;

    final navigator = Navigator.of(context);
    await _homeItems.addHomeItem(_buildHomeItem());
    if (widget.discoveredDevice != null) {
      // Return to the scan results so the user can add more devices.
      navigator.pop();
    } else {
      // Skip the category and type pickers and return to the main screen.
      navigator.popUntil((route) => route.isFirst);
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
      _deleted = true;
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

  /// Explains why the VIN or serial number is hidden and how to change it.
  void _showSerialNumberHelp(bool isVehicle) {
    final name = isVehicle ? 'VIN' : 'serial number';
    final label = isVehicle ? 'VIN' : 'Serial #';
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Hidden $name'),
        content: Text(
          'The Hide serial numbers privacy setting keeps your $name '
          "hidden. While it's on, the $name can only be typed in when "
          'adding a home item.\n\n'
          'To see or change it, turn off Hide serial numbers in Settings > '
          'Privacy, then tap the eye next to $label.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Opens the task form for one of the new tasks, or for a new custom task
  /// when [task] is `null`. Changes to a task are kept as they're made, and
  /// a new one once the user taps Add.
  Future<void> _editNewTask([MaintenanceTask? task]) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => TaskFormScreen.unsaved(
          homeItemName: _currentName,
          existing: task,
          onSaved: _keepNewTask,
        ),
      ),
    );
  }

  /// Adds [task] to the new tasks, or replaces the one with the same id.
  void _keepNewTask(MaintenanceTask task) {
    if (!mounted) return;
    setState(() {
      final index = _newTasks.indexWhere((t) => t.id == task.id);
      if (index == -1) {
        _newTasks = [..._newTasks, task];
      } else {
        _newTasks = [..._newTasks]..[index] = task;
      }
    });
  }

  /// Removes one of the new tasks once the user confirms.
  Future<void> _removeNewTask(MaintenanceTask task) async {
    if (!await _confirmDeleteTask(context, task.title, isSaved: false)) return;
    setState(() {
      _newTasks = [
        for (final t in _newTasks)
          if (t.id != task.id) t,
      ];
    });
  }

  /// Whether any recommended task isn't in the list, such as before the
  /// user has asked for them or after they removed one.
  bool get _canUseRecommended => _recommendedTasks.any(
    (recommended) => !_newTasks.any((task) => task.id == recommended.id),
  );

  /// Adds the recommended tasks that aren't already in the list.
  void _useRecommended() {
    setState(() {
      _newTasks = [
        ..._newTasks,
        for (final recommended in _recommendedTasks)
          if (!_newTasks.any((task) => task.id == recommended.id)) recommended,
      ];
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

    return PopScope(
      // Saves changes still waiting for the user to pause typing.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _saveChanges();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('${_isEditing ? 'Edit' : 'Add'} ${_category.itemName}'),
          actions: [
            if (_isEditing)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete home item',
                onPressed: _confirmDelete,
              )
            else
              TextButton(onPressed: _add, child: const Text('Add')),
          ],
        ),
        body: Form(
          key: _formKey,
          // There's no Save button to check the fields, so problems show as
          // the user edits.
          autovalidateMode: _isEditing
              ? AutovalidateMode.onUserInteraction
              : AutovalidateMode.disabled,
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
                      onChanged: (date) {
                        setState(() => _purchaseDate = date);
                        _saveChanges();
                      },
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
                          obscureText: _serialNumberObscured,
                          // No eye when the setting always hides it.
                          onObscureTextChanged: _hideSerialNumber
                              ? null
                              : (obscured) => setState(
                                  () => _serialNumberObscured = obscured,
                                ),
                          readOnly: _serialNumberReadOnly,
                          // Without the eye, explain why it can't be shown.
                          onHelp: _hideSerialNumber
                              ? () => _showSerialNumberHelp(isVehicle)
                              : null,
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
                  onUseRecommended: _canUseRecommended ? _useRecommended : null,
                  onRemove: _removeNewTask,
                  onEdit: _editNewTask,
                  onAdd: _editNewTask,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The maintenance schedule of a home item being edited. Tasks are saved as
/// soon as they're changed, added or deleted. They're marked done from the
/// overview instead.
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

  Future<void> _deleteTask(BuildContext context, MaintenanceTask task) async {
    final controller = context.read<HomeItemController>();
    if (await _confirmDeleteTask(context, task.title)) {
      await controller.deleteTask(homeItemId, task.id);
    }
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
              'Tasks',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final item in tasks)
            TaskTile(
              item: item,
              showHomeItemName: false,
              // The home item's tasks are its schedule, not a to-do list.
              showTiming: false,
              showArrow: true,
              onTap: () => _openTask(context, item.task),
              onDelete: () => _deleteTask(context, item.task),
            ),
          const Divider(height: 1),
          _AddTaskButton(onPressed: () => _openTask(context)),
        ],
      ),
    );
  }
}

/// The maintenance tasks that will be created with a new home item. Each
/// can be deleted, or tapped to change it before saving.
class _NewTaskList extends StatelessWidget {
  const _NewTaskList({
    required this.tasks,
    required this.onUseRecommended,
    required this.onRemove,
    required this.onEdit,
    required this.onAdd,
  });

  final List<MaintenanceTask> tasks;

  /// Adds the home item type's recommended tasks. The button is hidden when
  /// this is `null`, because there are none left to add.
  final VoidCallback? onUseRecommended;
  final ValueChanged<MaintenanceTask> onRemove;
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
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
            child: Row(
              children: [
                // As tall as the button, so the heading stays put when the
                // button goes away.
                const SizedBox(height: 48),
                Expanded(
                  child: Text('Tasks', style: theme.textTheme.titleMedium),
                ),
                if (onUseRecommended != null)
                  TextButton(
                    onPressed: onUseRecommended,
                    child: const Text('Add recommended tasks'),
                  ),
              ],
            ),
          ),
          for (final task in tasks)
            ListTile(
              // Keeps the delete button lined up with the heading's left edge.
              contentPadding: const EdgeInsets.only(left: 4, right: 16),
              horizontalTitleGap: 4,
              leading: IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete task',
                onPressed: () => onRemove(task),
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

/// Asks the user to confirm deleting the task named [title], returning
/// whether they did. A task that [isSaved] also loses its history.
Future<bool> _confirmDeleteTask(
  BuildContext context,
  String title, {
  bool isSaved = true,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Delete "$title"?'),
      content: isSaved
          ? const Text('This also deletes its history and reminders.')
          : null,
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
  return confirmed ?? false;
}
