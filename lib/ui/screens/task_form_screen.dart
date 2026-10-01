import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/maintenance_interval.dart';
import '../../models/maintenance_task.dart';
import '../../models/task_reminder.dart';
import '../../services/reminder_planner.dart';
import '../../state/home_item_controller.dart';
import '../../utils/date_utils.dart';
import '../../utils/id_generator.dart';
import '../widgets/date_field.dart';
import '../widgets/dropdown_field.dart';
import '../widgets/notification_permission.dart';

/// Form for adding a maintenance task or changing an existing one,
/// including how often it repeats and when the user is reminded about it.
class TaskFormScreen extends StatefulWidget {
  const TaskFormScreen({super.key, required this.homeItemId, this.existing});

  final String homeItemId;

  /// The task being edited, or `null` when adding a new task.
  final MaintenanceTask? existing;

  @override
  State<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends State<TaskFormScreen> {
  /// Choices for how far ahead of the due date the reminder is sent.
  static const _reminderLeadOptions = {
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
    return MaintenanceTask(
      id: _existing?.id ?? generateId(),
      title: _title.text.trim(),
      description: _description.text.trim(),
      interval: interval,
      recommendedInterval: _existing?.recommendedInterval,
      startDate: _startDate,
      lastCompleted: _lastCompleted,
      reminder: _reminder,
    );
  }

  Future<void> _setReminderEnabled(bool enabled) async {
    setState(() => _reminder = _reminder.copyWith(enabled: enabled));
    if (enabled) await requestNotificationPermission(context);
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
    await context.read<HomeItemController>().saveTask(widget.homeItemId, task);
    navigator.pop();
  }

  Future<void> _delete() async {
    final controller = context.read<HomeItemController>();
    final navigator = Navigator.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this task?'),
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
      await controller.deleteTask(widget.homeItemId, _existing!.id);
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 16);
    final recommended = _existing?.recommendedInterval;
    final interval = _interval;

    return Scaffold(
      appBar: AppBar(
        title: Text(_existing == null ? 'Add task' : 'Edit task'),
        actions: [
          if (_existing != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete task',
              onPressed: _delete,
            ),
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Task',
                hintText: 'e.g. Replace air filter',
                border: OutlineInputBorder(),
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Please describe the task'
                  : null,
            ),
            gap,
            TextFormField(
              controller: _description,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Instructions or notes (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            gap,
            Text('Repeat every', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 100,
                  child: TextFormField(
                    controller: _amount,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    // Rebuild so the next due date preview updates.
                    onChanged: (_) => setState(() {}),
                    validator: (_) =>
                        _interval == null ? 'Enter 1 or more' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownField<IntervalUnit>(
                    label: 'Unit',
                    value: _unit,
                    onChanged: (unit) => setState(() => _unit = unit),
                    items: [
                      for (final unit in IntervalUnit.values)
                        DropdownMenuItem(value: unit, child: Text(unit.plural)),
                    ],
                  ),
                ),
              ],
            ),
            if (recommended != null) ...[
              const SizedBox(height: 8),
              _RecommendationRow(
                recommended: recommended,
                isFollowing: interval == recommended,
                onReset: () => setState(() => _setInterval(recommended)),
              ),
            ],
            gap,
            DateField(
              label: 'Last done',
              value: _lastCompleted,
              emptyText: 'Never / not sure',
              onChanged: (date) => setState(() => _lastCompleted = date),
            ),
            if (interval != null) ...[
              const SizedBox(height: 8),
              Text(
                'Next due: ${MaterialLocalizations.of(context).formatFullDate(interval.addTo(_lastCompleted ?? _startDate))}',
              ),
            ],
            gap,
            Text('Reminder', style: Theme.of(context).textTheme.titleSmall),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Remind me about this task'),
              value: _reminder.enabled,
              onChanged: _setReminderEnabled,
            ),
            if (_reminder.enabled) ...[
              DropdownField<int>(
                label: 'When',
                value: _reminderLeadOptions.containsKey(_reminder.daysBefore)
                    ? _reminder.daysBefore
                    : 0,
                onChanged: (days) => setState(
                  () => _reminder = _reminder.copyWith(daysBefore: days),
                ),
                items: [
                  for (final MapEntry(key: days, value: label)
                      in _reminderLeadOptions.entries)
                    DropdownMenuItem(value: days, child: Text(label)),
                ],
              ),
              gap,
              InkWell(
                onTap: _pickReminderTime,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Time',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.schedule),
                  ),
                  child: Text(
                    TimeOfDay(
                      hour: _reminder.hour,
                      minute: _reminder.minute,
                    ).format(context),
                  ),
                ),
              ),
              if (_buildTask() case final task?) ...[
                const SizedBox(height: 8),
                Text(_describeNextReminder(context, task)),
              ],
            ],
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
    return Row(
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
    );
  }
}
