import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/module_routes.dart';
import 'customer_detail_screen.dart';
import 'customers_screen.dart';

class CustomersRoutes extends ModuleRoutes {
  const CustomersRoutes();

  @override
  ShellDestination get destination => ShellDestination(
    path: '/customers',
    label: (l) => l.navCustomers,
    icon: Icons.people_outline,
  );

  @override
  List<GoRoute> get branchRoutes => [
    branchRoute(
      destination: destination,
      builder: (context) => const CustomersScreen(),
      subRoutes: [
        GoRoute(
          path: ':id',
          builder: (context, state) => CustomerDetailScreen(
            customerId:
                int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
          ),
        ),
      ],
    ),
  ];
}