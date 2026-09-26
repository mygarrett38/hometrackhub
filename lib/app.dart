import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/settings_controller.dart';
import 'ui/home_shell.dart';

/// The root widget. Applies the light or dark theme the user chose.
class HomeTrackHubApp extends StatelessWidget {
  const HomeTrackHubApp({super.key});

  // Placeholder colors until the app's visual design is decided.
  static const _seedColor = Colors.teal;

  @override
  Widget build(BuildContext context) {
    final themeMode = context.select<SettingsController, ThemeMode>(
      (controller) => controller.settings.themeMode,
    );

    return MaterialApp(
      title: 'HomeTrackHub',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _seedColor),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.dark,
        ),
      ),
      home: const HomeShell(),
    );
  }
}
