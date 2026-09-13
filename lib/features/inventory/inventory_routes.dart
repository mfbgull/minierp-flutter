import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/module_routes.dart';
import 'batch_reconciliation_screen.dart';
import 'inventory_shell.dart';
import 'reservation_list_screen.dart';

class InventoryRoutes extends ModuleRoutes {
  const InventoryRoutes();

  @override
  ShellDestination get destination => ShellDestination(
    path: '/inventory',
    label: (l) => l.navInventory,
    icon: Icons.inventory_2_outlined,
  );

  @override
  List<GoRoute> get branchRoutes => [
    branchRoute(
      destination: destination,
      builder: (context) => const InventoryShell(),
      subRoutes: [
        // Batch-location feature screens — full-page views under
        // /inventory (the tab bar stays at 5 destinations; these are
        // opened from the batch management screen's actions).
        GoRoute(
          path: 'batch-reconciliation',
          builder: (context, state) => const BatchReconciliationScreen(),
        ),
        GoRoute(
          path: 'reservations',
          builder: (context, state) => const ReservationListScreen(),
        ),
      ],
    ),
  ];
}