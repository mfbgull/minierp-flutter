import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/module_routes.dart';
import 'settings_screen.dart';

class SettingsRoutes extends ModuleRoutes {
  const SettingsRoutes();

  @override
  ShellDestination get destination => ShellDestination(
    path: '/settings',
    label: (l) => l.navSettings,
    icon: Icons.settings_outlined,
    // Reachable from the app bar user menu instead of the sidebar.
    hideInRail: true,
  );

  @override
  List<GoRoute> get branchRoutes => [
    branchRoute(
      destination: destination,
      builder: (context) => const SettingsScreen(),
    ),
  ];
}