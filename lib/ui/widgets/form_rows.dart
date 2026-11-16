import 'package:flutter/material.dart';

// Rows for forms laid out as cards of label/value rows, like a settings
// screen. Each row shows its label on the left and its value on the right,
// edited in place.

/// Form rows are at least as tall as a [ListTile].
const formRowHeight = 56.0;

/// The divider placed between rows in a form card.
const formRowDivider = Divider(height: 1);

/// How long after the user stops typing a form saves their changes, on forms
/// that save as they're edited. Other changes, such as picking a date, are
/// saved straight away.
const autosaveDelay = Duration(milliseconds: 500);

/// Shows a date picker limited to past dates and today. Returns `null` if
/// the user cancels.
Future<DateTime?> pickPastDate(BuildContext context, {DateTime? initialDate}) {
  final now = DateTime.now();
  return showDatePicker(
    context: context,
    initialDate: initialDate ?? now,
    firstDate: DateTime(1950),
    lastDate: now,
  );
}

/// A form row with a borderless text field on the right.
///
/// If [choices] are given, a menu button at the end of the row fills the
/// field with one of them. The user can still type their own value.
///
/// If [obscureText] is true, the value is hidden. If [onObscureTextChanged]
/// is given, an eye button next to the label hides or shows it.
///
/// If [onHelp] is given, a help button next to the label calls it, for
/// example to explain why the field can't be changed.
class InlineTextRow extends StatelessWidget {
  const InlineTextRow({
    super.key,
    required this.label,
    required this.controller,
    this.hint = 'Unknown',
    this.validator,
    this.choices = const [],
    this.obscureText = false,
    this.onObscureTextChanged,
    this.readOnly = false,
    this.onHelp,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final FormFieldValidator<String>? validator;
  final List<String> choices;
  final bool obscureText;
  final ValueChanged<bool>? onObscureTextChanged;
  final bool readOnly;
  final VoidCallback? onHelp;

  @override
  Widget build(BuildContext context) {
    final onObscureTextChanged = this.onObscureTextChanged;
    return Padding(
      padding: EdgeInsets.only(left: 16, right: choices.isEmpty ? 16 : 4),
      child: Row(
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyLarge),
          if (onObscureTextChanged != null)
            IconButton(
              tooltip: obscureText ? 'Show $label' : 'Hide $label',
              visualDensity: VisualDensity.compact,
              icon: Icon(obscureText ? Icons.visibility : Icons.visibility_off),
              onPressed: () => onObscureTextChanged(!obscureText),
            ),
          if (onHelp != null)
            IconButton(
              tooltip: 'About $label',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.help_outline),
              onPressed: onHelp,
            ),
          const SizedBox(width: 16),
          Expanded(
            child: TextFormField(
              controller: controller,
              validator: validator,
              textAlign: TextAlign.end,
              textCapitalization: TextCapitalization.sentences,
              obscureText: obscureText,
              readOnly: readOnly,
              decoration: InputDecoration(
                hintText: hint,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          if (choices.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: 'Choose ${label.toLowerCase()}',
              onSelected: (choice) => controller.text = choice,
              itemBuilder: (context) => [
                for (final choice in choices)
                  PopupMenuItem(value: choice, child: Text(choice)),
              ],
              // Spaced like the arrow of a [ChoiceMenuButton].
              child: const Padding(
                padding: EdgeInsets.fromLTRB(4, 12, 12, 12),
                child: Icon(Icons.arrow_drop_down),
              ),
            ),
        ],
      ),
    );
  }
}

/// A form row that shows a date on the right and opens a date picker
/// when tapped. Only past dates and today can be picked.
class InlineDateRow extends StatelessWidget {
  const InlineDateRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.emptyText = 'Unknown',
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  /// Shown when [value] is `null`.
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = value;

    return InkWell(
      onTap: () async {
        final picked = await pickPastDate(context, initialDate: date);
        if (picked != null) onChanged(picked);
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: formRowHeight),
        child: Padding(
          padding: EdgeInsets.only(left: 16, right: date == null ? 16 : 4),
          child: Row(
            children: [
              Text(label, style: theme.textTheme.bodyLarge),
              const Spacer(),
              Text(
                date == null
                    ? emptyText
                    // With the year, such as "Nov 4, 2026", since dates
                    // here can be years apart.
                    : MaterialLocalizations.of(context).formatShortDate(date),
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: date == null
                      ? theme.colorScheme.onSurfaceVariant
                      : null,
                ),
              ),
              if (date != null)
                IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: 'Clear date',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => onChanged(null),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A form row that shows a value on the right. If [onTap] is given, the row
/// can be tapped to change the value, for example with a picker.
class InlineValueRow extends StatelessWidget {
  const InlineValueRow({
    super.key,
    required this.label,
    required this.value,
    this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: formRowHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(label, style: textTheme.bodyLarge),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  style: textTheme.bodyLarge,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A form row whose value is picked from a menu of [choices], shown as the
/// text of each choice.
class InlineChoiceRow<T> extends StatelessWidget {
  const InlineChoiceRow({
    super.key,
    required this.label,
    required this.value,
    required this.choices,
    required this.onChanged,
  });

  final String label;
  final T value;
  final Map<T, String> choices;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: formRowHeight),
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 4),
        child: Row(
          children: [
            Text(label, style: Theme.of(context).textTheme.bodyLarge),
            const Spacer(),
            ChoiceMenuButton<T>(
              tooltip: 'Choose ${label.toLowerCase()}',
              value: value,
              choices: choices,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

/// The current choice followed by a dropdown arrow. Tapping it opens a menu
/// of [choices].
class ChoiceMenuButton<T> extends StatelessWidget {
  const ChoiceMenuButton({
    super.key,
    required this.tooltip,
    required this.value,
    required this.choices,
    required this.onChanged,
  });

  final String tooltip;
  final T value;
  final Map<T, String> choices;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      tooltip: tooltip,
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final MapEntry(key: choice, value: text) in choices.entries)
          PopupMenuItem(value: choice, child: Text(text)),
      ],
      // Keep the arrow's spacing in step with [InlineTextRow]'s menu arrow.
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              choices[value] ?? '',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}

/// A form row with a label and a multi-line text field below it.
class InlineNotesRow extends StatelessWidget {
  const InlineNotesRow({
    super.key,
    required this.controller,
    this.label = 'Notes',
    this.hint = 'Add notes',
  });

  final TextEditingController controller;
  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyLarge),
          TextFormField(
            controller: controller,
            minLines: 3,
            maxLines: null,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: hint,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ],
      ),
    );
  }
}
