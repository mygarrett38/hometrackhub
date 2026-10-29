import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/home_expense.dart';
import '../../../models/home_item.dart';
import '../../../models/home_item_task.dart';
import '../../../state/home_item_controller.dart';
import '../../../utils/date_utils.dart';
import '../../../utils/id_generator.dart';
import '../../widgets/task_tile.dart';
import '../home_items/task_form_screen.dart';
import 'dashboard_setup_card.dart';

/// The first tab: a live summary of saved maintenance and expense data.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.onAssistPressed});

  final VoidCallback onAssistPressed;

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
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      // There is no app bar, so the content keeps clear of the status bar.
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontal = constraints.maxWidth >= 640 ? 28.0 : 16.0;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(horizontal, 40, horizontal, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _greeting,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
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
                  if (controller.hasNoTasks) ...[
                    const DashboardSetupCard(),
                    const SizedBox(height: 20),
                  ],
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
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const _TaskListScreen(
                              kind: _TaskListKind.dueSoon,
                            ),
                          ),
                        ),
                      ),
                      _SummaryCard(
                        label: 'Overdue',
                        value: '$overdue',
                        icon: Icons.warning_amber_rounded,
                        color: colors.error,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const _TaskListScreen(
                              kind: _TaskListKind.overdue,
                            ),
                          ),
                        ),
                      ),
                      _SummaryCard(
                        label: 'Completed This Month',
                        value: '$completedThisMonth',
                        icon: Icons.task_alt,
                        color: colors.secondary,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const _CompletionHistoryScreen(),
                          ),
                        ),
                      ),
                      _SummaryCard(
                        label: 'Spent This Month',
                        value: '\$${spentThisMonth.toStringAsFixed(2)}',
                        icon: Icons.account_balance_wallet_outlined,
                        color: colors.tertiary,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => _MonthlyExpensesScreen(
                              month: now,
                              onRecordExpense: () =>
                                  _recordExpense(context, controller),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: widget.onAssistPressed,
                      icon: const Icon(Icons.forum_outlined),
                      label: const Text('Have a home question? Ask AI Assist'),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
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
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
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
      ),
    );
  }
}

class _ExpenseDetailEntry {
  const _ExpenseDetailEntry(this.item, this.expense);

  final HomeItem item;
  final HomeExpense expense;
}

class _MonthlyExpensesScreen extends StatelessWidget {
  const _MonthlyExpensesScreen({
    required this.month,
    required this.onRecordExpense,
  });

  final DateTime month;
  final VoidCallback onRecordExpense;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HomeItemController>();
    final now = DateTime.now();
    final isCurrentMonth = month.year == now.year && month.month == now.month;
    final monthStart = DateTime(month.year, month.month);
    final nextMonth = DateTime(month.year, month.month + 1);
    final entries = [
      for (final item in controller.homeItems)
        for (final expense in item.expenses)
          if (!expense.date.isBefore(monthStart) && expense.date.isBefore(nextMonth))
            _ExpenseDetailEntry(item, expense),
    ]..sort((a, b) => b.expense.date.compareTo(a.expense.date));
    final total = entries.fold<double>(
      0,
      (sum, entry) => sum + entry.expense.amount,
    );
    final monthName = MaterialLocalizations.of(context).formatMonthYear(month);
    return Scaffold(
      appBar: AppBar(title: Text('$monthName Expenses')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _YearlyExpensesScreen(
                        initialYear: month.year,
                        onRecordExpense: onRecordExpense,
                      ),
                    ),
                  ),
                  child: const Text(
                    'Yearly History',
                    maxLines: 1,
                    softWrap: false,
                  ),
                ),
              ),
              if (isCurrentMonth) ...[
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: FilledButton.icon(
                    onPressed: controller.homeItems.isEmpty
                        ? null
                        : onRecordExpense,
                    icon: const Icon(Icons.add_card_outlined),
                    label: const Text(
                      'Record an expense',
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('Total spent'),
              trailing: Text(
                '\$${total.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('No expenses recorded this month.')),
            )
          else ...[
            const SizedBox(height: 8),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < entries.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: Text(entries[i].expense.description),
                      subtitle: Text(
                        '${entries[i].item.name} · ${MaterialLocalizations.of(context).formatMediumDate(entries[i].expense.date)}',
                      ),
                      trailing: Text(
                        '\$${entries[i].expense.amount.toStringAsFixed(2)}',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _YearlyExpensesScreen extends StatefulWidget {
  const _YearlyExpensesScreen({
    required this.initialYear,
    required this.onRecordExpense,
  });

  final int initialYear;
  final VoidCallback onRecordExpense;

  @override
  State<_YearlyExpensesScreen> createState() => _YearlyExpensesScreenState();
}

class _YearlyExpensesScreenState extends State<_YearlyExpensesScreen> {
  late int _year = widget.initialYear;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HomeItemController>();
    final localizations = MaterialLocalizations.of(context);
    final entriesByMonth = <int, List<_ExpenseDetailEntry>>{
      for (var month = 1; month <= 12; month++) month: <_ExpenseDetailEntry>[],
    };
    for (final item in controller.homeItems) {
      for (final expense in item.expenses) {
        if (expense.date.year == _year) {
          entriesByMonth[expense.date.month]!.add(
            _ExpenseDetailEntry(item, expense),
          );
        }
      }
    }
    for (final entries in entriesByMonth.values) {
      entries.sort((a, b) => b.expense.date.compareTo(a.expense.date));
    }
    final yearlyTotal = entriesByMonth.values
        .expand((entries) => entries)
        .fold<double>(0, (total, entry) => total + entry.expense.amount);

    return Scaffold(
      appBar: AppBar(
        title: Text('$_year Expense History'),
        actions: [
          IconButton(
            tooltip: 'Previous year',
            onPressed: () => setState(() => _year--),
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            tooltip: 'Next year',
            onPressed: _year >= DateTime.now().year
                ? null
                : () => setState(() => _year++),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('Year total'),
              trailing: Text(
                '\$${yearlyTotal.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var month = 1; month <= 12; month++) ...[
                  if (month > 1) const Divider(height: 1),
                  ListTile(
                    title: Text(
                      localizations.formatMonthYear(DateTime(_year, month)),
                    ),
                    subtitle: Text(
                      '${entriesByMonth[month]!.length} expenses',
                    ),
                    trailing: Text(
                      '\$${entriesByMonth[month]!.fold<double>(0, (total, entry) => total + entry.expense.amount).toStringAsFixed(2)}',
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => _MonthlyExpensesScreen(
                          month: DateTime(_year, month),
                          onRecordExpense: widget.onRecordExpense,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _TaskListKind { dueSoon, overdue }

class _TaskListScreen extends StatelessWidget {
  const _TaskListScreen({required this.kind});

  final _TaskListKind kind;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HomeItemController>();
    final today = dateOnly(DateTime.now());
    final activeTasks = controller.allTasks
        .where((item) => !controller.isListedAsDone(item));
    final items = controller.orderForList(activeTasks.where((item) {
      final days = calendarDaysBetween(today, item.dueDate);
      return kind == _TaskListKind.overdue
          ? days < 0
          : days >= 0 && days <= 30;
    }));
    final title = kind == _TaskListKind.overdue ? 'Overdue' : 'Due Soon';
    final emptyMessage = kind == _TaskListKind.overdue
        ? 'No overdue tasks.'
        : 'No tasks are due in the next 30 days.';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: items.isEmpty
          ? Center(child: Text(emptyMessage))
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return TaskTile(
                  item: item,
                  showArrow: true,
                  onTap: () => _openTask(context, item),
                );
              },
            ),
    );
  }
}

void _openTask(BuildContext context, HomeItemTask item) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => TaskFormScreen(
        homeItemId: item.homeItem.id,
        homeItemName: item.homeItem.name,
        existing: item.task,
      ),
    ),
  );
}

class _CompletionHistoryEntry {
  const _CompletionHistoryEntry(this.item, this.date);

  final HomeItemTask item;
  final DateTime date;
}

class _CompletionHistoryScreen extends StatelessWidget {
  const _CompletionHistoryScreen();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HomeItemController>();
    final entries = [
      for (final item in controller.allTasks)
        for (final date in item.task.completionDates)
          _CompletionHistoryEntry(item, date),
    ]..sort((a, b) => b.date.compareTo(a.date));

    return Scaffold(
      appBar: AppBar(title: const Text('Completion History')),
      body: entries.isEmpty
          ? const Center(child: Text('No completed tasks yet.'))
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                return TaskTile(
                  item: entry.item,
                  completedOn: entry.date,
                  showArrow: true,
                  onTap: () => _openTask(context, entry.item),
                );
              },
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

  /// Shown under a field after trying to save without filling it in
  /// properly, until the field is changed.
  String? _descriptionError;
  String? _amountError;

  @override
  void initState() {
    super.initState();
    _itemId = widget.items.first.id;
  }

  void _save() {
    final description = _description.text.trim();
    final amount = double.tryParse(_amount.text.trim());
    final validAmount = amount != null && amount > 0;
    if (description.isEmpty || !validAmount) {
      setState(() {
        _descriptionError = description.isEmpty
            ? 'Enter a description'
            : null;
        _amountError = validAmount ? null : 'Enter an amount above \$0';
      });
      return;
    }
    Navigator.of(context).pop(
      _ExpenseEntry(
        _itemId,
        HomeExpense(
          id: generateId(),
          description: description,
          amount: amount,
          date: _date,
        ),
      ),
    );
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
              decoration: InputDecoration(
                labelText: 'Description',
                errorText: _descriptionError,
              ),
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) {
                if (_descriptionError != null) {
                  setState(() => _descriptionError = null);
                }
              },
            ),
            TextField(
              controller: _amount,
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: '\$',
                errorText: _amountError,
              ),
              onChanged: (_) {
                if (_amountError != null) setState(() => _amountError = null);
              },
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
        FilledButton(onPressed: _save, child: const Text('Save expense')),
      ],
    );
  }
}
