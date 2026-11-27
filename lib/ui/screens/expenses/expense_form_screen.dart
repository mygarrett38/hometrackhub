import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/home_expense.dart';
import '../../../state/home_item_controller.dart';
import '../../../utils/date_utils.dart';
import '../../../utils/id_generator.dart';
import '../../widgets/form_rows.dart';
import '../../widgets/screen_padding.dart';
import 'expense_views.dart';

/// Records what was spent on one of the user's home items, such as a
/// repair, or changes or deletes the [existing] expense. A new expense is
/// added once the user taps Add, and going back discards it; changes to an
/// existing one are saved as they're made. Only opened when the user has at
/// least one home item.
class ExpenseFormScreen extends StatefulWidget {
  const ExpenseFormScreen({super.key, this.existing});

  /// The expense to edit, and the home item it was spent on, or `null` to
  /// add one.
  final Spending? existing;

  @override
  State<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

/// What can be changed about an expense, to tell whether it has been.
typedef _ExpenseFields = ({
  String homeItemId,
  String description,
  String amount,
  DateTime date,
});

class _ExpenseFormScreenState extends State<ExpenseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final HomeItemController _homeItems = context.read<HomeItemController>();

  /// Saves typed changes once the user pauses.
  Timer? _saveTimer;

  /// The fields as they were last saved, for an existing expense.
  _ExpenseFields? _savedFields;

  /// Set once the expense is deleted, so nothing saves it again.
  bool _deleted = false;

  late final _description = TextEditingController(
    text: widget.existing?.expense.description,
  );
  late final _amount = TextEditingController(
    text: widget.existing?.expense.amount.toStringAsFixed(2),
  );
  late String _homeItemId =
      widget.existing?.homeItem.id ?? _homeItems.homeItems.first.id;
  late DateTime _date = dateOnly(
    widget.existing?.expense.date ?? DateTime.now(),
  );

  /// For a new expense, problems are only pointed out once the user tries
  /// to add it, then cleared as each field is fixed.
  AutovalidateMode _autovalidate = AutovalidateMode.disabled;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _savedFields = _fields;
      _description.addListener(_scheduleSave);
      _amount.addListener(_scheduleSave);
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  _ExpenseFields get _fields => (
    homeItemId: _homeItemId,
    description: _description.text.trim(),
    amount: _amount.text.trim(),
    date: _date,
  );

  /// The amount entered, or `null` if it isn't more than $0.
  double? get _amountValue {
    final amount = double.tryParse(_amount.text.trim());
    return amount != null && amount > 0 ? amount : null;
  }

  /// The expense as entered on the form, or `null` if it isn't filled in
  /// correctly.
  HomeExpense? get _expense {
    final description = _description.text.trim();
    final amount = _amountValue;
    if (description.isEmpty || amount == null) return null;
    return HomeExpense(
      id: widget.existing?.expense.id ?? generateId(),
      description: description,
      amount: amount,
      date: _date,
    );
  }

  /// Saves the typed changes to an existing expense once the user pauses.
  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(autosaveDelay, _saveChanges);
  }

  /// Saves any changes to an existing expense. Nothing is saved while a
  /// field isn't filled in correctly; the form shows why instead.
  void _saveChanges() {
    _saveTimer?.cancel();
    if (!_isEditing || _deleted) return;
    final fields = _fields;
    final expense = _expense;
    if (fields == _savedFields || expense == null) return;
    _savedFields = fields;
    _homeItems.saveExpense(_homeItemId, expense);
  }

  /// Adds the new expense, if the form is filled in correctly.
  Future<void> _add() async {
    final expense = _expense;
    if (!_formKey.currentState!.validate() || expense == null) {
      setState(() => _autovalidate = AutovalidateMode.onUserInteraction);
      return;
    }
    final navigator = Navigator.of(context);
    await _homeItems.saveExpense(_homeItemId, expense);
    navigator.pop();
  }

  Future<void> _confirmDelete() async {
    // Changes waiting to be saved are saved first, so the expense is
    // described as it's shown, on the home item it's now on.
    _saveChanges();
    final id = widget.existing!.expense.id;
    final homeItem = _homeItems.homeItems.firstWhere(
      (item) => item.expenses.any((expense) => expense.id == id),
      orElse: () => widget.existing!.homeItem,
    );
    final expense = homeItem.expenses.firstWhere(
      (expense) => expense.id == id,
      orElse: () => widget.existing!.expense,
    );
    final navigator = Navigator.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${expense.description}"?'),
        content: Text(
          '${formatMoney(expense.amount)} spent on ${homeItem.name} will no '
          'longer be counted.',
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
      await _homeItems.deleteExpense(homeItem.id, id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final homeItems = context.watch<HomeItemController>().homeItems;

    return PopScope(
      // Saves changes still waiting for the user to pause typing.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _saveChanges();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEditing ? 'Edit expense' : 'Add expense'),
          actions: [
            if (_isEditing)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete expense',
                onPressed: _confirmDelete,
              )
            else
              TextButton(onPressed: _add, child: const Text('Add')),
          ],
        ),
        body: Form(
          key: _formKey,
          // There's no Save button to check the fields of an existing
          // expense, so problems show as the user edits.
          autovalidateMode: _isEditing
              ? AutovalidateMode.onUserInteraction
              : _autovalidate,
          child: ListView(
            padding: screenPadding(context),
            children: [
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    InlineChoiceRow<String>(
                      label: 'Home item',
                      value: _homeItemId,
                      choices: {
                        for (final item in homeItems) item.id: item.name,
                      },
                      onChanged: (id) {
                        setState(() => _homeItemId = id);
                        _saveChanges();
                      },
                    ),
                    formRowDivider,
                    InlineTextRow(
                      label: 'Description',
                      controller: _description,
                      hint: 'Required',
                      validator: (value) => (value ?? '').trim().isEmpty
                          ? 'Enter a description'
                          : null,
                    ),
                    formRowDivider,
                    InlineTextRow(
                      label: 'Amount',
                      controller: _amount,
                      hint: '0.00',
                      prefixText: r'$',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (_) => _amountValue == null
                          ? r'Enter an amount above $0'
                          : null,
                    ),
                    formRowDivider,
                    InlineDateRow(
                      label: 'Date',
                      value: _date,
                      canClear: false,
                      onChanged: (date) {
                        if (date == null) return;
                        setState(() => _date = dateOnly(date));
                        _saveChanges();
                      },
                    ),
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
