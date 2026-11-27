import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/settings_controller.dart';
import 'ui/home_shell.dart';
import 'ui/screens/launch/launch_screen.dart';
import 'ui/theme/app_theme.dart';
import 'ui/typing_focus.dart';

/// The root widget. Applies the light or dark theme the user chose.
class HomeTrackHubApp extends StatelessWidget {
  const HomeTrackHubApp({super.key});

  /// The same one every build, since an observer belongs to one navigator.
  static final _typingFocus = TypingFocusObserver();

  @override
  Widget build(BuildContext context) {
    final themeMode = context.select<SettingsController, ThemeMode>(
      (controller) => controller.settings.themeMode,
    );

    return MaterialApp(
      title: 'HomeTrackHub',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // The keyboard doesn't come back when returning to a screen.
      navigatorObservers: [_typingFocus],
      home: const LaunchScreen(child: HomeShell()),
    );
  }
}
