import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/module_routes.dart';
import 'supplier_detail_screen.dart';
import 'suppliers_screen.dart';

class SuppliersRoutes extends ModuleRoutes {
  const SuppliersRoutes();

  @override
  ShellDestination get destination => ShellDestination(
    path: '/suppliers',
    label: (l) => l.navSuppliers,
    icon: Icons.local_shipping_outlined,
  );

  @override
  List<GoRoute> get branchRoutes => [
    branchRoute(
      destination: destination,
      builder: (context) => const SuppliersScreen(),
      subRoutes: [
        GoRoute(
          path: ':id',
          builder: (context, state) => SupplierDetailScreen(
            supplierId:
                int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
          ),
        ),
      ],
    ),
  ];
}