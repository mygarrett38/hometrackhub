import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_settings.dart';
import '../services/notification_service.dart';
import '../state/home_item_controller.dart';
import '../state/settings_controller.dart';
import 'screens/assist/assist_screen.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/home_items/home_item_list_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/upcoming/maintenance_calendar_screen.dart';

/// The app's main layout with five tabs. Uses a bottom navigation bar on
/// phones and a side navigation rail on wider screens such as tablets.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  /// Screens wider than this use the side navigation rail.
  static const wideLayoutBreakpoint = 640.0;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  /// The Overview tab, in the middle, is shown first.
  static const _overviewIndex = 2;

  int _selectedIndex = _overviewIndex;

  /// The Overview tab is shown as the app's logo in a circle instead, so it
  /// has no icon here and its label is used just for tooltips and screen
  /// readers.
  static const _destinations = [
    (icon: Icons.source, label: 'My Home'),
    (icon: Icons.calendar_month, label: 'Calendar'),
    (icon: null, label: 'Overview'),
    (icon: Icons.forum, label: 'Assist'),
    (icon: Icons.settings, label: 'Settings'),
  ];

  @override
  void initState() {
    super.initState();
    // Ask for notification permission once the first screen is visible, if
    // any task reminder or the overview notification is turned on.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final settings = context.read<SettingsController>().settings;
      final anyTaskReminders = context.read<HomeItemController>().allTasks.any(
        (item) => item.task.reminder.enabled,
      );
      if (anyTaskReminders ||
          settings.overviewFrequency != OverviewFrequency.off) {
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
    final body = IndexedStack(
      index: _selectedIndex,
      children: [
        const HomeItemListScreen(),
        const MaintenanceCalendarScreen(),
        DashboardScreen(onAssistPressed: () => _select(3)),
        const AssistScreen(),
        const SettingsScreen(),
      ],
    );

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
                  if (destination.icon case final icon?)
                    NavigationRailDestination(
                      icon: Icon(icon),
                      label: Text(destination.label),
                    )
                  else
                    NavigationRailDestination(
                      icon: Tooltip(
                        message: destination.label,
                        child: const _Logo(size: 48),
                      ),
                      label: Semantics(
                        label: destination.label,
                        child: const SizedBox.shrink(),
                      ),
                    ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    // Hidden while typing, so it doesn't ride up on top of the keyboard.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: body,
      // The Overview tab is a round button over the middle of the bar. The
      // Scaffold places it, so the part above the bar can still be tapped.
      floatingActionButton: keyboardOpen
          ? null
          : _OverviewButton(
              label: _destinations[_overviewIndex].label,
              selected: _selectedIndex == _overviewIndex,
              onPressed: () => _select(_overviewIndex),
            ),
      floatingActionButtonLocation: const _RaisedCenterLocation(),
      // Icons only, so the bar can be shorter than usual. The labels are
      // still shown as tooltips and read by screen readers.
      bottomNavigationBar: NavigationBar(
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        // The bar's own highlight is a wide pill, so it's hidden and each
        // selected icon draws a circle behind itself instead. The tap ripple
        // is round to match.
        indicatorColor: Colors.transparent,
        indicatorShape: const CircleBorder(),
        selectedIndex: _selectedIndex,
        onDestinationSelected: _select,
        destinations: [
          for (final destination in _destinations)
            if (destination.icon case final icon?)
              NavigationDestination(
                icon: Icon(icon, size: 28),
                selectedIcon: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.secondaryContainer,
                  ),
                  child: Icon(icon, size: 28),
                ),
                label: destination.label,
              )
            else
              // Keeps a gap for the Overview button so the other tabs are
              // spaced evenly around it.
              const NavigationDestination(
                icon: SizedBox.shrink(),
                label: '',
                tooltip: '',
              ),
        ],
      ),
    );
  }
}

/// The app's logo cropped to a circle.
class _Logo extends StatelessWidget {
  const _Logo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Image.asset(
        'assets/images/app_icon.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}

/// The round Overview button in the middle of the bottom navigation bar.
/// A ring around it shows when it's the selected tab.
class _OverviewButton extends StatelessWidget {
  const _OverviewButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  static const size = 64.0;

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Semantics(
      selected: selected,
      button: true,
      child: SizedBox.square(
        dimension: size,
        child: FloatingActionButton(
          // Other tabs have their own floating buttons.
          heroTag: null,
          tooltip: label,
          onPressed: onPressed,
          shape: CircleBorder(
            side: BorderSide(
              color: selected ? colors.primary : colors.outlineVariant,
              width: selected ? 3 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          backgroundColor: colors.surfaceContainerLowest,
          child: const _Logo(size: size),
        ),
      ),
    );
  }
}

/// Centers the floating button on the bottom navigation bar with just its
/// top sticking out above the bar.
class _RaisedCenterLocation extends StandardFabLocation
    with FabCenterOffsetX, FabDockedOffsetY {
  const _RaisedCenterLocation();

  /// How far the button rises above the top of the bar. Low enough that it
  /// still covers the bar's highlight for the selected tab underneath it.
  static const _rise = 14.0;

  @override
  double getOffsetY(
    ScaffoldPrelayoutGeometry scaffoldGeometry,
    double adjustment,
  ) {
    // The docked position is half above the bar; lower it so less shows.
    final docked = super.getOffsetY(scaffoldGeometry, adjustment);
    return docked +
        scaffoldGeometry.floatingActionButtonSize.height / 2 -
        _rise;
  }
}
