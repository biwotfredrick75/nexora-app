import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wakulima/core/theme/app_theme.dart';

class MainShell extends StatelessWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  static const _tabs = [
    _NavTab(label: 'Home',       icon: Icons.grid_view_rounded,     route: '/dashboard'),
    _NavTab(label: 'Collection', icon: Icons.water_drop_outlined,   route: '/collection'),
    _NavTab(label: 'Analytics',  icon: Icons.bar_chart_outlined,    route: '/analytics'),
    _NavTab(label: 'Settings',   icon: Icons.settings_outlined,     route: '/settings'),
  ];

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    for (var i = 0; i < _tabs.length; i++) {
      if (location.startsWith(_tabs[i].route)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final index = _currentIndex(context);
    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: WakulimaColors.border, width: 1)),
        ),
        child: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (i) => context.go(_tabs[i].route),
          backgroundColor: WakulimaColors.white,
          indicatorColor: WakulimaColors.primary50,
          surfaceTintColor: Colors.transparent,
          height: 64,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: _tabs
              .map((t) => NavigationDestination(
                    icon: Icon(t.icon, color: WakulimaColors.inkMuted),
                    selectedIcon: Icon(t.icon, color: WakulimaColors.primary700),
                    label: t.label,
                  ))
              .toList(),
        ),
      ),
    );
  }
}

class _NavTab {
  final String label;
  final IconData icon;
  final String route;
  const _NavTab({required this.label, required this.icon, required this.route});
}
