import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/settings_controller.dart';

/// Labels for each [ThemeMode], shared with the settings category list.
const themeModeLabels = {
  ThemeMode.system: 'System default',
  ThemeMode.light: 'Light',
  ThemeMode.dark: 'Dark',
};

/// Lets the user choose light mode, dark mode, or follow the device.
class AppearanceSettingsScreen extends StatelessWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final settings = controller.settings;

    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.system,
                label: Text('System'),
                icon: Icon(Icons.brightness_auto),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                label: Text('Light'),
                icon: Icon(Icons.light_mode),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                label: Text('Dark'),
                icon: Icon(Icons.dark_mode),
              ),
            ],
            selected: {settings.themeMode},
            onSelectionChanged: (selection) => controller.update(
              settings.copyWith(themeMode: selection.single),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'System follows your device\'s light or dark mode setting.',
          ),
        ],
      ),
    );
  }
}
