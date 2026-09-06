import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/module_routes.dart';
import 'purchasing_shell.dart';

class PurchasingRoutes extends ModuleRoutes {
  const PurchasingRoutes();

  @override
  ShellDestination get destination => ShellDestination(
    path: '/purchasing',
    label: (l) => l.navPurchases,
    icon: Icons.shopping_cart_outlined,
  );

  @override
  List<GoRoute> get branchRoutes => [
    branchRoute(
      destination: destination,
      builder: (context) => const PurchasingShell(),
    ),
  ];
}