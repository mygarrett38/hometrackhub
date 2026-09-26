import 'package:flutter/material.dart';

/// A form row that shows a date and opens a date picker when tapped.
///
/// Only past dates and today can be picked, because the app uses this for
/// things that already happened, like purchase and completion dates.
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.emptyText = 'Not set',
    this.allowClear = true,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  /// Shown when [value] is `null`.
  final String emptyText;

  /// Whether to show a button that clears the date.
  final bool allowClear;

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: value ?? now,
      firstDate: DateTime(1950),
      lastDate: now,
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final date = value;
    return InkWell(
      onTap: () => _pickDate(context),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: allowClear && date != null
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: 'Clear date',
                  onPressed: () => onChanged(null),
                )
              : const Icon(Icons.calendar_today),
        ),
        child: Text(
          date == null
              ? emptyText
              : MaterialLocalizations.of(context).formatMediumDate(date),
        ),
      ),
    );
  }
}
