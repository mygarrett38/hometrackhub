import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/home_expense.dart';
import '../../../state/home_item_controller.dart';
import '../../../utils/date_utils.dart';
import '../../../utils/id_generator.dart';
import '../../widgets/form_rows.dart';
import '../../widgets/screen_padding.dart';

/// Records what was spent on one of the user's home items, such as a
/// repair. It's added once the user taps Add; going back discards it. Only
/// opened when the user has at least one home item.
class AddExpenseScreen extends StatefulWidget {
  const AddExpenseScreen({super.key});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _description = TextEditingController();
  final _amount = TextEditingController();
  late String _homeItemId = context
      .read<HomeItemController>()
      .homeItems
      .first
      .id;
  DateTime _date = dateOnly(DateTime.now());

  /// Problems are only pointed out once the user tries to add the expense,
  /// then cleared as each field is fixed.
  AutovalidateMode _autovalidate = AutovalidateMode.disabled;

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  /// The amount entered, or `null` if it isn't more than $0.
  double? get _amountValue {
    final amount = double.tryParse(_amount.text.trim());
    return amount != null && amount > 0 ? amount : null;
  }

  Future<void> _add() async {
    if (!_formKey.currentState!.validate()) {
      setState(() => _autovalidate = AutovalidateMode.onUserInteraction);
      return;
    }
    final navigator = Navigator.of(context);
    await context.read<HomeItemController>().addExpense(
      _homeItemId,
      HomeExpense(
        id: generateId(),
        description: _description.text.trim(),
        amount: _amountValue!,
        date: _date,
      ),
    );
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final homeItems = context.watch<HomeItemController>().homeItems;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add expense'),
        actions: [TextButton(onPressed: _add, child: const Text('Add'))],
      ),
      body: Form(
        key: _formKey,
        autovalidateMode: _autovalidate,
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
                    choices: {for (final item in homeItems) item.id: item.name},
                    onChanged: (id) => setState(() => _homeItemId = id),
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
                      if (date != null) setState(() => _date = dateOnly(date));
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
