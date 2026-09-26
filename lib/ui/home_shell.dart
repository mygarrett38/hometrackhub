import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/notification_service.dart';
import '../state/settings_controller.dart';
import 'screens/equipment_list_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/upcoming_screen.dart';

/// The app's main layout with three tabs. Uses a bottom navigation bar on
/// phones and a side navigation rail on wider screens such as tablets and
/// desktops.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  /// Screens wider than this use the side navigation rail.
  static const wideLayoutBreakpoint = 640.0;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;

  static const _destinations = [
    (icon: Icons.event_available, label: 'Upcoming'),
    (icon: Icons.home_repair_service, label: 'Equipment'),
    (icon: Icons.settings, label: 'Settings'),
  ];

  static const _screens = [
    UpcomingScreen(),
    EquipmentListScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Ask for notification permission once the first screen is visible.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final settings = context.read<SettingsController>().settings;
      if (settings.notificationsEnabled) {
        context.read<NotificationService>().requestPermission();
      }
    });
  }

  void _select(int index) => setState(() => _selectedIndex = index);

  @override
  Widget build(BuildContext context) {
    final isWide =
        MediaQuery.sizeOf(context).width >= HomeShell.wideLayoutBreakpoint;
    // IndexedStack keeps each tab's scroll position when switching tabs.
    final body = IndexedStack(index: _selectedIndex, children: _screens);

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: _select,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final destination in _destinations)
                  NavigationRailDestination(
                    icon: Icon(destination.icon),
                    label: Text(destination.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _select,
        destinations: [
          for (final destination in _destinations)
            NavigationDestination(
              icon: Icon(destination.icon),
              label: destination.label,
            ),
        ],
      ),
    );
  }
}
