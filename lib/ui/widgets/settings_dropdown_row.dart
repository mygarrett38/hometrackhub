import 'package:flutter/material.dart';

/// A setting chosen from a menu: its [icon] and [title], with the menu in the
/// top right and a [description] below that runs the full width after the
/// icon. A [ListTile] would squeeze the description in beside the menu.
class SettingsDropdownRow<T> extends StatelessWidget {
  const SettingsDropdownRow({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.value,
    required this.choices,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String description;
  final T value;

  /// Each value the menu offers, with its label.
  final Map<T, String> choices;
  final ValueChanged<T> onChanged;

  /// As tall as the menu, so the title lines up with it.
  static const _menuHeight = 48.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // The same spacing and text styles as the list rows around it.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: _menuHeight, child: Icon(icon)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // At least as tall as the menu, but taller for large text.
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: _menuHeight),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(title, style: theme.textTheme.bodyLarge),
                      ),
                      DropdownButton<T>(
                        value: value,
                        // The choice sits against the right edge, however
                        // short it is.
                        alignment: AlignmentDirectional.centerEnd,
                        onChanged: (value) {
                          if (value != null) onChanged(value);
                        },
                        items: [
                          for (final MapEntry(key: value, value: label)
                              in choices.entries)
                            DropdownMenuItem(value: value, child: Text(label)),
                        ],
                      ),
                    ],
                  ),
                ),
                Text(
                  description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
