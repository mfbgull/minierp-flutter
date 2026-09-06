import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/module_routes.dart';
import 'expenses_screen.dart';

class ExpensesRoutes extends ModuleRoutes {
  const ExpensesRoutes();

  @override
  ShellDestination get destination => ShellDestination(
    path: '/expenses',
    label: (l) => l.navExpenses,
    icon: Icons.receipt_long_outlined,
  );

  @override
  List<GoRoute> get branchRoutes => [
    branchRoute(
      destination: destination,
      builder: (context) => const ExpensesScreen(),
    ),
  ];
}