import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/home_expense.dart';
import '../../../models/home_item.dart';
import '../../../models/home_item_task.dart';
import '../../../state/home_item_controller.dart';
import '../../../utils/date_utils.dart';
import '../../../utils/id_generator.dart';
import '../home_items/task_form_screen.dart';

/// The first tab: a live summary of saved maintenance and expense data.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late String _greeting;
  Timer? _greetingTimer;

  @override
  void initState() {
    super.initState();
    _greeting = _greetingFor(DateTime.now());
    _greetingTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      final greeting = _greetingFor(DateTime.now());
      if (greeting != _greeting && mounted) {
        setState(() => _greeting = greeting);
      }
    });
  }

  @override
  void dispose() {
    _greetingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HomeItemController>();
    final now = DateTime.now();
    final today = dateOnly(now);
    final monthStart = DateTime(now.year, now.month);
    final nextMonth = DateTime(now.year, now.month + 1);
    final activeTasks = controller.allTasks
        .where((task) => !controller.isListedAsDone(task))
        .toList();
    final overdue = activeTasks
        .where((task) => calendarDaysBetween(today, task.dueDate) < 0)
        .length;
    final dueSoon = activeTasks.where((task) {
      final days = calendarDaysBetween(today, task.dueDate);
      return days >= 0 && days <= 30;
    }).length;
    final completedThisMonth = controller.allTasks
        .expand((task) => task.task.completionDates)
        .where((date) => !date.isBefore(monthStart) && date.isBefore(nextMonth))
        .length;
    final spentThisMonth = controller.homeItems
        .expand((item) => item.expenses)
        .where(
          (expense) =>
              !expense.date.isBefore(monthStart) &&
              expense.date.isBefore(nextMonth),
        )
        .fold<double>(0, (total, expense) => total + expense.amount);
    final nextTasks = controller.orderForList(activeTasks).take(5).toList();
    final completionHistory = [
      for (final item in controller.allTasks)
        for (final date in item.task.completionDates)
          _CompletionHistoryEntry(item, date),
    ]..sort((a, b) => b.date.compareTo(a.date));
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('HomeTrack Hub'),
        actions: [
          IconButton(
            tooltip: 'Record an expense',
            onPressed: controller.homeItems.isEmpty
                ? null
                : () => _recordExpense(context, controller),
            icon: const Icon(Icons.add_card_outlined),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final horizontal = constraints.maxWidth >= 640 ? 28.0 : 16.0;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(horizontal, 20, horizontal, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _greeting,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Your home at a glance',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(height: 20),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: constraints.maxWidth < 360
                      ? 0.95
                      : constraints.maxWidth < 640
                      ? 1.08
                      : 1.32,
                  children: [
                    _SummaryCard(
                      label: 'Due Soon',
                      value: '$dueSoon',
                      icon: Icons.schedule,
                      color: colors.primary,
                    ),
                    _SummaryCard(
                      label: 'Overdue',
                      value: '$overdue',
                      icon: Icons.warning_amber_rounded,
                      color: colors.error,
                    ),
                    _SummaryCard(
                      label: 'Completed This Month',
                      value: '$completedThisMonth',
                      icon: Icons.task_alt,
                      color: colors.secondary,
                    ),
                    _SummaryCard(
                      label: 'Spent This Month',
                      value: '\$${spentThisMonth.toStringAsFixed(2)}',
                      icon: Icons.account_balance_wallet_outlined,
                      color: colors.tertiary,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text('Next Up', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                if (nextTasks.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Center(
                        child: Text(
                          controller.allTasks.isEmpty
                              ? 'Add a home item to start planning maintenance.'
                              : 'You’re all caught up for now.',
                        ),
                      ),
                    ),
                  )
                else
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (var i = 0; i < nextTasks.length; i++) ...[
                          if (i > 0) const Divider(height: 1, indent: 16),
                          _NextTaskTile(item: nextTasks[i]),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
                Text(
                  'Completion History',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                if (completionHistory.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Center(
                        child: Text(
                          'Tasks you check off will appear here with their completion dates.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  )
                else
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (final entry in completionHistory.take(5)) ...[
                          if (entry != completionHistory.first)
                            const Divider(height: 1, indent: 16),
                          _CompletionHistoryTile(entry: entry),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _recordExpense(
    BuildContext context,
    HomeItemController controller,
  ) async {
    final entry = await showDialog<_ExpenseEntry>(
      context: context,
      builder: (_) => _RecordExpenseDialog(items: controller.homeItems),
    );
    if (entry == null || !context.mounted) return;
    await controller.addExpense(entry.homeItemId, entry.expense);
  }
}

String _greetingFor(DateTime time) {
  if (time.hour < 12) return 'Good Morning!';
  if (time.hour < 17) return 'Good Afternoon!';
  return 'Good Evening!';
}

class _ExpenseEntry {
  const _ExpenseEntry(this.homeItemId, this.expense);

  final String homeItemId;
  final HomeExpense expense;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: color, size: 27),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700, color: color),
                  ),
                ),
                const SizedBox(height: 2),
                Text(label, style: Theme.of(context).textTheme.labelLarge),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NextTaskTile extends StatelessWidget {
  const _NextTaskTile({required this.item});

  final HomeItemTask item;

  @override
  Widget build(BuildContext context) {
    final date = MaterialLocalizations.of(context)
        .formatMediumDate(item.dueDate);
    return ListTile(
      leading: const Icon(Icons.home_repair_service_outlined),
      title: Text(
        item.task.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text('${item.homeItem.name} · Due $date'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TaskFormScreen(
            homeItemId: item.homeItem.id,
            homeItemName: item.homeItem.name,
            existing: item.task,
          ),
        ),
      ),
    );
  }
}

class _CompletionHistoryEntry {
  const _CompletionHistoryEntry(this.item, this.date);

  final HomeItemTask item;
  final DateTime date;
}

class _CompletionHistoryTile extends StatelessWidget {
  const _CompletionHistoryTile({required this.entry});

  final _CompletionHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final date = MaterialLocalizations.of(context).formatMediumDate(entry.date);
    return ListTile(
      leading: const Icon(Icons.task_alt_outlined),
      title: Text(
        entry.item.task.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text('${entry.item.homeItem.name} · Completed $date'),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TaskFormScreen(
            homeItemId: entry.item.homeItem.id,
            homeItemName: entry.item.homeItem.name,
            existing: entry.item.task,
          ),
        ),
      ),
    );
  }
}

class _RecordExpenseDialog extends StatefulWidget {
  const _RecordExpenseDialog({required this.items});

  final List<HomeItem> items;

  @override
  State<_RecordExpenseDialog> createState() => _RecordExpenseDialogState();
}

class _RecordExpenseDialogState extends State<_RecordExpenseDialog> {
  final _description = TextEditingController();
  final _amount = TextEditingController();
  late String _itemId;
  DateTime _date = dateOnly(DateTime.now());

  @override
  void initState() {
    super.initState();
    _itemId = widget.items.first.id;
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Record an expense'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _itemId,
              decoration: const InputDecoration(labelText: 'Home item'),
              items: [
                for (final item in widget.items)
                  DropdownMenuItem<String>(
                    value: item.id,
                    child: Text(item.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) => setState(() => _itemId = value!),
            ),
            TextField(
              controller: _description,
              decoration: const InputDecoration(labelText: 'Description'),
              textCapitalization: TextCapitalization.sentences,
            ),
            TextField(
              controller: _amount,
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '\$',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            TextButton.icon(
              onPressed: () async {
                final selected = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                );
                if (selected != null) {
                  setState(() => _date = dateOnly(selected));
                }
              },
              icon: const Icon(Icons.calendar_today),
              label: Text(
                MaterialLocalizations.of(context).formatMediumDate(_date),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final amount = double.tryParse(_amount.text.trim());
            if (amount == null ||
                amount <= 0 ||
                _description.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Enter a description and valid amount.'),
                ),
              );
              return;
            }
            Navigator.of(context).pop(
              _ExpenseEntry(
                _itemId,
                HomeExpense(
                  id: generateId(),
                  description: _description.text.trim(),
                  amount: amount,
                  date: _date,
                ),
              ),
            );
          },
          child: const Text('Save expense'),
        ),
      ],
    );
  }
}
