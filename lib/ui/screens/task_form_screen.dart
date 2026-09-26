import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/maintenance_interval.dart';
import '../../models/maintenance_task.dart';
import '../../state/equipment_controller.dart';
import '../../utils/date_utils.dart';
import '../../utils/id_generator.dart';
import '../widgets/date_field.dart';
import '../widgets/dropdown_field.dart';

/// Form for adding a maintenance task or changing an existing one,
/// including how often it repeats.
class TaskFormScreen extends StatefulWidget {
  const TaskFormScreen({super.key, required this.equipmentId, this.existing});

  final String equipmentId;

  /// The task being edited, or `null` when adding a new task.
  final MaintenanceTask? existing;

  @override
  State<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends State<TaskFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _amount = TextEditingController(text: '1');

  IntervalUnit _unit = IntervalUnit.months;
  DateTime? _lastCompleted;
  bool _remindersEnabled = true;

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
      _remindersEnabled = existing.remindersEnabled;
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final task = MaintenanceTask(
      id: _existing?.id ?? generateId(),
      title: _title.text.trim(),
      description: _description.text.trim(),
      interval: _interval!,
      recommendedInterval: _existing?.recommendedInterval,
      startDate: _startDate,
      lastCompleted: _lastCompleted,
      remindersEnabled: _remindersEnabled,
    );

    final navigator = Navigator.of(context);
    await context.read<EquipmentController>().saveTask(
      widget.equipmentId,
      task,
    );
    navigator.pop();
  }

  Future<void> _delete() async {
    final controller = context.read<EquipmentController>();
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
      await controller.deleteTask(widget.equipmentId, _existing!.id);
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
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Remind me when this is due'),
              value: _remindersEnabled,
              onChanged: (value) => setState(() => _remindersEnabled = value),
            ),
          ],
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
