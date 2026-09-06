import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/module_routes.dart';
import 'dashboard_screen.dart';

class DashboardRoutes extends ModuleRoutes {
  const DashboardRoutes();

  @override
  ShellDestination get destination => ShellDestination(
    path: '/',
    label: (l) => l.navDashboard,
    icon: Icons.space_dashboard_outlined,
  );

  @override
  List<GoRoute> get branchRoutes => [
    branchRoute(destination: destination, builder: (context) {
      // Resolved lazily so the label function is available.
      return const DashboardScreen();
    }),
  ];
}