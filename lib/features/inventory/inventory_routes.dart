import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/module_routes.dart';
import 'inventory_shell.dart';

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
    ),
  ];
}