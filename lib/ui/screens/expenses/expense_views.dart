import 'package:flutter/material.dart';

import '../../../models/home_expense.dart';
import '../../../models/home_item.dart';
import '../../../utils/date_utils.dart';

/// One expense and the home item it was spent on.
typedef Spending = ({HomeItem homeItem, HomeExpense expense});

/// Every expense on [homeItems] spent on a day that [includes], latest
/// first.
List<Spending> spendingOn(
  List<HomeItem> homeItems,
  bool Function(DateTime day) includes,
) => [
  for (final homeItem in homeItems)
    for (final expense in homeItem.expenses)
      if (includes(dateOnly(expense.date)))
        (homeItem: homeItem, expense: expense),
]..sort((a, b) => b.expense.date.compareTo(a.expense.date));

/// What [spending] adds up to.
double totalOf(Iterable<Spending> spending) =>
    spending.fold(0, (total, spending) => total + spending.expense.amount);

/// An amount of money, such as "$25.00".
String formatMoney(double amount) => '\$${amount.toStringAsFixed(2)}';

/// [spending] in a card, one expense to a row, in the order given.
class ExpenseList extends StatelessWidget {
  const ExpenseList({super.key, required this.spending});

  final List<Spending> spending;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (index, item) in spending.indexed) ...[
            if (index > 0) const Divider(height: 1),
            _ExpenseTile(spending: item),
          ],
        ],
      ),
    );
  }
}

/// Each month of [year] up to [months], latest first, with what was spent
/// in it. A month with expenses opens to list them.
class ExpensesByMonth extends StatelessWidget {
  const ExpensesByMonth({
    super.key,
    required this.year,
    required this.spending,
    required this.months,
  });

  final int year;

  /// What was spent in [year], latest first.
  final List<Spending> spending;

  /// How many months to show, from January.
  final int months;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var month = months; month >= 1; month--) ...[
            if (month < months) const Divider(height: 1),
            Builder(
              builder: (context) {
                final inMonth = [
                  for (final item in spending)
                    if (item.expense.date.month == month) item,
                ];
                final title = Row(
                  children: [
                    Expanded(child: Text(monthName(month))),
                    Text(
                      formatMoney(totalOf(inMonth)),
                      // The same size as the expenses' amounts.
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                );
                final count = inMonth.length;
                final subtitle = Text(
                  count == 0
                      ? 'No expenses'
                      : '$count ${count == 1 ? 'expense' : 'expenses'}',
                );
                if (inMonth.isEmpty) {
                  return ListTile(
                    title: title,
                    subtitle: subtitle,
                    // Lines the total up with those of the months that open.
                    trailing: const SizedBox(width: 24),
                  );
                }
                return ExpansionTile(
                  title: title,
                  subtitle: subtitle,
                  // The card already draws the outline.
                  shape: const Border(),
                  collapsedShape: const Border(),
                  children: [
                    for (final item in inMonth) ...[
                      const Divider(height: 1),
                      _ExpenseTile(spending: item),
                    ],
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// One expense: what it was for, the home item and date, and how much.
class _ExpenseTile extends StatelessWidget {
  const _ExpenseTile({required this.spending});

  final Spending spending;

  @override
  Widget build(BuildContext context) {
    final (:homeItem, :expense) = spending;
    final date = MaterialLocalizations.of(context)
        .formatMediumDate(expense.date);
    return ListTile(
      leading: const Icon(Icons.receipt_long_outlined),
      title: Text(expense.description),
      subtitle: Text('${homeItem.name} · $date'),
      trailing: Text(
        formatMoney(expense.amount),
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}
