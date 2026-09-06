import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/module_routes.dart';
import 'production_shell.dart';

class ProductionRoutes extends ModuleRoutes {
  const ProductionRoutes();

  @override
  ShellDestination get destination => ShellDestination(
    path: '/production',
    // The sidebar link reads "Manufacturing" (product naming) while the
    // module's internal tab keeps the feature name.
    label: (l) => l.navManufacturing,
    title: (l) => l.navProduction,
    icon: Icons.factory_outlined,
  );

  @override
  List<GoRoute> get branchRoutes => [
    branchRoute(
      destination: destination,
      builder: (context) => const ProductionShell(),
    ),
  ];
}