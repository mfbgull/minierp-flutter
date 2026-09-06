import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/module_routes.dart';
import 'employees_screen.dart';

class EmployeesRoutes extends ModuleRoutes {
  const EmployeesRoutes();

  @override
  ShellDestination get destination => ShellDestination(
    path: '/hr',
    label: (l) => l.navEmployees,
    icon: Icons.badge_outlined,
  );

  @override
  List<GoRoute> get branchRoutes => [
    branchRoute(
      destination: destination,
      builder: (context) => const EmployeesScreen(),
    ),
  ];
}