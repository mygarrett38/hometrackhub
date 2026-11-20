import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../models/maintenance_interval.dart';
import '../../../models/maintenance_task.dart';
import '../../../models/task_reminder.dart';
import '../../../state/home_item_controller.dart';
import '../../../utils/date_utils.dart';
import '../../../utils/id_generator.dart';
import '../../widgets/form_rows.dart';
import '../../widgets/notification_permission.dart';
import '../../widgets/screen_padding.dart';

/// Form for adding a maintenance task or changing an existing one,
/// including how often it repeats and when the user is reminded about it.
///
/// Changes to an existing task are saved as they're made, with no Save
/// button. A new task is only created when the user taps Add; going back
/// without tapping it discards it.
class TaskFormScreen extends StatefulWidget {
  const TaskFormScreen({
    super.key,
    required this.homeItemId,
    required this.homeItemName,
    this.existing,
  }) : onSaved = null;

  /// Edits a task for a home item that hasn't been saved yet. Instead of
  /// being stored, the task is handed to [onSaved] whenever it's saved.
  const TaskFormScreen.unsaved({
    super.key,
    required this.homeItemName,
    required ValueChanged<MaintenanceTask> this.onSaved,
    this.existing,
  }) : homeItemId = null;

  /// The home item the task belongs to, or `null` for a home item that
  /// hasn't been saved yet.
  final String? homeItemId;

  /// Shown so the user knows which home item the task is for.
  final String homeItemName;

  /// The task being edited, or `null` when adding a new task.
  final MaintenanceTask? existing;

  /// Receives the task each time it's saved, for a home item that hasn't
  /// been saved yet.
  final ValueChanged<MaintenanceTask>? onSaved;

  @override
  State<TaskFormScreen> createState() => _TaskFormScreenState();
}

/// The values of a task's fields, to tell whether they've changed since
/// they were last saved.
typedef _TaskFields = ({
  String title,
  String description,
  String amount,
  IntervalUnit unit,
  DateTime? lastCompleted,
  TaskReminder reminder,
});

class _TaskFormScreenState extends State<TaskFormScreen> {
  /// The reminder choice for not being reminded at all.
  static const _never = -1;

  /// Choices for whether, and how far ahead of the due date, the reminder
  /// is sent.
  static const _reminderOptions = {
    _never: 'Never',
    0: 'On the due date',
    1: '1 day before',
    2: '2 days before',
    3: '3 days before',
    7: '1 week before',
    14: '2 weeks before',
    30: '1 month before',
  };

  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _amount = TextEditingController(text: '1');

  IntervalUnit _unit = IntervalUnit.months;
  DateTime? _lastCompleted;
  TaskReminder _reminder = const TaskReminder();

  /// Whether notifications turned out to be blocked when the reminder was
  /// turned on, so it won't arrive.
  bool _notificationsBlocked = false;

  late final HomeItemController _homeItems;

  /// Saves typed changes once the user pauses.
  Timer? _saveTimer;

  /// The fields as they were last saved, for an existing task.
  _TaskFields? _savedFields;

  MaintenanceTask? get _existing => widget.existing;
  bool get _isNew => _existing == null;

  @override
  void initState() {
    super.initState();
    _homeItems = context.read<HomeItemController>();
    final existing = _existing;
    if (existing != null) {
      _title.text = existing.title;
      _description.text = existing.description;
      _setInterval(existing.interval);
      _lastCompleted = existing.lastCompleted;
      _reminder = existing.reminder;
      _savedFields = _fields;
      for (final controller in [_title, _description, _amount]) {
        controller.addListener(_scheduleSave);
      }
    }
  }

  _TaskFields get _fields => (
    title: _title.text.trim(),
    description: _description.text.trim(),
    amount: _amount.text.trim(),
    unit: _unit,
    lastCompleted: _lastCompleted,
    reminder: _reminder,
  );

  /// Saves the typed changes to an existing task once the user pauses.
  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(autosaveDelay, _saveChanges);
  }

  /// Saves any changes to an existing task. Nothing is saved while the task
  /// has no name or a repeat that isn't valid; the form shows why instead.
  void _saveChanges() {
    _saveTimer?.cancel();
    if (_isNew) return;
    final fields = _fields;
    final task = _buildTask();
    if (fields == _savedFields || fields.title.isEmpty || task == null) {
      return;
    }
    _savedFields = fields;
    _store(task);
  }

  /// Stores [task] on its home item, or hands it to [TaskFormScreen.onSaved]
  /// for a home item that hasn't been saved yet.
  Future<void> _store(MaintenanceTask task) async {
    final homeItemId = widget.homeItemId;
    if (homeItemId == null) {
      widget.onSaved!(task);
    } else {
      await _homeItems.saveTask(homeItemId, task);
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _title.dispose();
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _setInterval(MaintenanceInterval interval) {
    _amount.text = interval.amount.toString();
    _unit = interval.unit;
  }

  /// The interval currently entered, or `null` if the amount is invalid.
  MaintenanceInterval? get _interval {
    final amount = int.tryParse(_amount.text);
    if (amount == null || amount < 1) return null;
    return MaintenanceInterval(amount, _unit);
  }

  DateTime get _startDate => _existing?.startDate ?? dateOnly(DateTime.now());

  /// The task as currently entered, or `null` if the interval is invalid.
  MaintenanceTask? _buildTask() {
    final interval = _interval;
    if (interval == null) return null;
    final existing = _existing;
    final completionDates = [...?existing?.completionDates];
    if (existing?.lastCompleted != _lastCompleted) {
      final oldDate = existing?.lastCompleted;
      if (oldDate != null) {
        final oldDateIndex = completionDates.lastIndexWhere(
          (date) =>
              date.year == oldDate.year &&
              date.month == oldDate.month &&
              date.day == oldDate.day,
        );
        if (oldDateIndex >= 0) completionDates.removeAt(oldDateIndex);
      }
      if (_lastCompleted != null) completionDates.add(_lastCompleted!);
    }
    return MaintenanceTask(
      id: existing?.id ?? generateId(),
      title: _title.text.trim(),
      description: _description.text.trim(),
      interval: interval,
      recommendedInterval: existing?.recommendedInterval,
      startDate: _startDate,
      lastCompleted: _lastCompleted,
      previousLastCompleted: existing?.previousLastCompleted,
      completionDates: completionDates,
      reminder: _reminder,
    );
  }

  /// The selected entry of [_reminderOptions].
  int get _reminderChoice {
    if (!_reminder.enabled) return _never;
    // Fall back for a lead time that isn't one of the choices.
    return _reminderOptions.containsKey(_reminder.daysBefore)
        ? _reminder.daysBefore
        : 0;
  }

  Future<void> _setReminderChoice(int choice) async {
    final wasEnabled = _reminder.enabled;
    setState(
      () => _reminder = choice == _never
          ? _reminder.copyWith(enabled: false)
          : _reminder.copyWith(enabled: true, daysBefore: choice),
    );
    _saveChanges();
    if (!wasEnabled && _reminder.enabled) {
      final allowed = await requestNotificationPermission(context);
      if (mounted) setState(() => _notificationsBlocked = !allowed);
    }
  }

  /// Creates the new task, if the form is filled in correctly.
  Future<void> _add() async {
    if (!_formKey.currentState!.validate()) return;

    final navigator = Navigator.of(context);
    await _store(_buildTask()!);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final recommended = _existing?.recommendedInterval;
    final interval = _interval;

    return PopScope(
      // Saves changes still waiting for the user to pause typing.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _saveChanges();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isNew ? 'Add task' : 'Edit task'),
          actions: [
            if (_isNew) TextButton(onPressed: _add, child: const Text('Add')),
          ],
        ),
        body: Form(
          key: _formKey,
          // There's no Save button to check the fields, so problems show as
          // the user edits.
          autovalidateMode: _isNew
              ? AutovalidateMode.disabled
              : AutovalidateMode.onUserInteraction,
          child: ListView(
            padding: screenPadding(context),
            children: [
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    InlineTextRow(
                      label: 'Task',
                      controller: _title,
                      hint: 'Required',
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                          ? 'Please describe the task'
                          : null,
                    ),
                    formRowDivider,
                    InlineValueRow(label: 'For', value: widget.homeItemName),
                    formRowDivider,
                    InlineNotesRow(
                      controller: _description,
                      label: 'Instructions',
                      hint: 'Add instructions or notes',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _RepeatRow(
                      amount: _amount,
                      unit: _unit,
                      // Rebuild so the next due date updates.
                      onAmountChanged: () => setState(() {}),
                      onUnitChanged: (unit) {
                        setState(() => _unit = unit);
                        _saveChanges();
                      },
                      validator: (_) =>
                          _interval == null ? 'Enter 1 or more' : null,
                    ),
                    if (recommended != null)
                      _RecommendationRow(
                        recommended: recommended,
                        isFollowing: interval == recommended,
                        onReset: () {
                          setState(() => _setInterval(recommended));
                          _saveChanges();
                        },
                      ),
                    formRowDivider,
                    InlineDateRow(
                      label: 'Last done',
                      value: _lastCompleted,
                      emptyText: 'Never / not sure',
                      onChanged: (date) {
                        setState(() => _lastCompleted = date);
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (interval != null) ...[
                      InlineValueRow(
                        label: 'Next due',
                        // With the year, like the date rows.
                        value: MaterialLocalizations.of(context)
                            .formatShortDate(
                              interval.addTo(_lastCompleted ?? _startDate),
                            ),
                      ),
                      formRowDivider,
                    ],
                    InlineChoiceRow<int>(
                      label: 'Start notifying me',
                      value: _reminderChoice,
                      choices: _reminderOptions,
                      onChanged: _setReminderChoice,
                    ),
                    if (_reminder.enabled && _notificationsBlocked)
                      const NotificationsBlockedNotice(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows the manufacturer's recommended interval with a button to go back
/// to it after the user has changed the interval.
class _RecommendationRow extends StatelessWidget {
  const _RecommendationRow({
    required this.recommended,
    required this.isFollowing,
    required this.onReset,
  });

  final MaintenanceInterval recommended;
  final bool isFollowing;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 8, isFollowing ? 16 : 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Manufacturer recommendation: ${recommended.label.toLowerCase()}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (!isFollowing)
            TextButton(onPressed: onReset, child: const Text('Use this')),
        ],
      ),
    );
  }
}

/// The "Repeat every" row: a number typed in place, followed by a menu to
/// choose days, weeks, months or years.
class _RepeatRow extends StatelessWidget {
  const _RepeatRow({
    required this.amount,
    required this.unit,
    required this.onAmountChanged,
    required this.onUnitChanged,
    required this.validator,
  });

  final TextEditingController amount;
  final IntervalUnit unit;
  final VoidCallback onAmountChanged;
  final ValueChanged<IntervalUnit> onUnitChanged;
  final FormFieldValidator<String> validator;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 4),
      child: Row(
        children: [
          Text('Repeat every', style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(width: 16),
          Expanded(
            child: TextFormField(
              controller: amount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.end,
              decoration: const InputDecoration(
                hintText: '1',
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 16),
              ),
              onChanged: (_) => onAmountChanged(),
              validator: validator,
            ),
          ),
          const SizedBox(width: 8),
          ChoiceMenuButton<IntervalUnit>(
            tooltip: 'Choose unit',
            value: unit,
            choices: {
              for (final unit in IntervalUnit.values) unit: unit.plural,
            },
            onChanged: onUnitChanged,
          ),
        ],
      ),
    );
  }
}
