import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/calendar_period.dart';
import '../../../state/settings_controller.dart';
import '../../widgets/screen_padding.dart';
import '../../widgets/settings_card.dart';
import '../../widgets/settings_dropdown_row.dart';

/// Lets the user choose light mode, dark mode, or follow the device, and
/// how much time the calendar and Overview show.
class AppearanceSettingsScreen extends StatelessWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final settings = controller.settings;

    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: ListView(
        padding: screenPadding(context),
        children: [
          SettingsCard(
            children: [
              SettingsDropdownRow<ThemeMode>(
                icon: Icons.brightness_6_outlined,
                title: 'Theme',
                description:
                    'System follows your device\'s light or dark mode '
                    'setting.',
                value: settings.themeMode,
                choices: const {
                  ThemeMode.system: 'System',
                  ThemeMode.light: 'Light',
                  ThemeMode.dark: 'Dark',
                },
                onChanged: (themeMode) =>
                    controller.update(settings.copyWith(themeMode: themeMode)),
              ),
            ],
          ),
          SettingsCard(
            children: [
              SettingsDropdownRow<CalendarPeriod>(
                icon: Icons.calendar_month_outlined,
                title: 'Calendar view',
                description:
                    'What the calendar shows when the app opens. The '
                    'Overview\'s Completed and Spent cards also count this '
                    'week, month or year.',
                value: settings.calendarPeriod,
                choices: {
                  for (final period in CalendarPeriod.values)
                    period: period.label,
                },
                onChanged: (period) => controller.update(
                  settings.copyWith(calendarPeriod: period),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
