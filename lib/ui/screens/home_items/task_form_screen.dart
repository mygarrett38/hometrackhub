import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../models/maintenance_interval.dart';
import '../../../models/maintenance_task.dart';
import '../../../models/task_reminder.dart';
import '../../../services/reminder_planner.dart';
import '../../../state/home_item_controller.dart';
import '../../../utils/date_utils.dart';
import '../../../utils/id_generator.dart';
import '../../widgets/form_rows.dart';
import '../../widgets/notification_permission.dart';
import '../../widgets/screen_padding.dart';

/// Form for adding a maintenance task or changing an existing one,
/// including how often it repeats and when the user is reminded about it.
class TaskFormScreen extends StatefulWidget {
  const TaskFormScreen({
    super.key,
    required this.homeItemId,
    required this.homeItemName,
    this.existing,
  });

  /// Edits a task for a home item that hasn't been saved yet. Saving pops
  /// this screen with the task instead of storing it.
  const TaskFormScreen.unsaved({
    super.key,
    required this.homeItemName,
    this.existing,
  }) : homeItemId = null;

  /// The home item the task belongs to, or `null` for a home item that
  /// hasn't been saved yet.
  final String? homeItemId;

  /// Shown so the user knows which home item the task is for.
  final String homeItemName;

  /// The task being edited, or `null` when adding a new task.
  final MaintenanceTask? existing;

  @override
  State<TaskFormScreen> createState() => _TaskFormScreenState();
}

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

  MaintenanceTask? get _existing => widget.existing;

  @override
  void initState() {
    super.initState();
    final existing = _existing;
    if (existing != null) {
      _title.text = existing.title;
      _description.text = existing.description;
      _setInterval(existing.interval);
      _lastCompleted = existing.lastCompleted;
      _reminder = existing.reminder;
    }
  }

  @override
  void dispose() {
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
    if (!wasEnabled && _reminder.enabled) {
      await requestNotificationPermission(context);
    }
  }

  Future<void> _pickReminderTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _reminder.hour, minute: _reminder.minute),
    );
    if (picked != null) {
      setState(
        () => _reminder = _reminder.copyWith(
          hour: picked.hour,
          minute: picked.minute,
        ),
      );
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final task = _buildTask()!;
    final navigator = Navigator.of(context);
    final homeItemId = widget.homeItemId;
    if (homeItemId == null) {
      navigator.pop(task);
      return;
    }
    await context.read<HomeItemController>().saveTask(homeItemId, task);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final recommended = _existing?.recommendedInterval;
    final interval = _interval;

    return Scaffold(
      appBar: AppBar(
        title: Text(_existing == null ? 'Add task' : 'Edit task'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
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
                    onUnitChanged: (unit) => setState(() => _unit = unit),
                    validator: (_) =>
                        _interval == null ? 'Enter 1 or more' : null,
                  ),
                  if (recommended != null)
                    _RecommendationRow(
                      recommended: recommended,
                      isFollowing: interval == recommended,
                      onReset: () => setState(() => _setInterval(recommended)),
                    ),
                  formRowDivider,
                  InlineDateRow(
                    label: 'Last done',
                    value: _lastCompleted,
                    emptyText: 'Never / not sure',
                    onChanged: (date) => setState(() => _lastCompleted = date),
                  ),
                  if (interval != null) ...[
                    formRowDivider,
                    InlineValueRow(
                      label: 'Next due',
                      value: MaterialLocalizations.of(context).formatMediumDate(
                        interval.addTo(_lastCompleted ?? _startDate),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InlineChoiceRow<int>(
                    label: 'Remind me',
                    value: _reminderChoice,
                    choices: _reminderOptions,
                    onChanged: _setReminderChoice,
                  ),
                  if (_reminder.enabled) ...[
                    formRowDivider,
                    InlineValueRow(
                      label: 'Time',
                      value: TimeOfDay(
                        hour: _reminder.hour,
                        minute: _reminder.minute,
                      ).format(context),
                      onTap: _pickReminderTime,
                    ),
                    if (_buildTask() case final task?)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Text(
                          _describeNextReminder(context, task),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// For example "Next reminder: Monday, October 5, 2026 at 9:00 AM".
String _describeNextReminder(BuildContext context, MaintenanceTask task) {
  final time = nextReminderTime(task, DateTime.now());
  final localizations = MaterialLocalizations.of(context);
  final date = localizations.formatFullDate(time);
  final timeOfDay = localizations.formatTimeOfDay(TimeOfDay.fromDateTime(time));
  return 'Next reminder: $date at $timeOfDay';
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
