import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:cohyve/core/branding/branding.g.dart';
import 'package:cohyve/core/theme/app_theme.dart';

/// Root scaffold with bottom navigation. Hosts the Discover / Shortlist /
/// Settings branches via go_router's StatefulNavigationShell.
class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).navigationBarTheme.backgroundColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: (index) => navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          ),
          destinations: const [
            NavigationDestination(
              icon: Icon(LucideIcons.compass),
              selectedIcon: Icon(LucideIcons.compass, color: BrandingExtended.gradientStart),
              label: 'Discover',
            ),
            NavigationDestination(
              icon: Icon(LucideIcons.heart),
              selectedIcon: Icon(LucideIcons.heart, color: BrandingExtended.gradientStart),
              label: 'Shortlist',
            ),
            NavigationDestination(
              icon: Icon(LucideIcons.settings),
              selectedIcon: Icon(LucideIcons.settings, color: BrandingExtended.gradientStart),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
