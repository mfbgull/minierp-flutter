import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/module_routes.dart';
import 'payments_screen.dart';

class PaymentsRoutes extends ModuleRoutes {
  const PaymentsRoutes();

  @override
  ShellDestination get destination => ShellDestination(
    path: '/payments',
    label: (l) => l.navPayments,
    icon: Icons.account_balance_wallet_outlined,
  );

  @override
  List<GoRoute> get branchRoutes => [
    branchRoute(
      destination: destination,
      builder: (context) => const PaymentsScreen(),
    ),
  ];
}