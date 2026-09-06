import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/module_routes.dart';
import 'owners_equity_shell.dart';

class OwnersEquityRoutes extends ModuleRoutes {
  const OwnersEquityRoutes();

  @override
  ShellDestination get destination => ShellDestination(
    path: '/owners-equity',
    label: (l) => l.navOwnersequity,
    icon: Icons.savings_outlined,
  );

  @override
  List<GoRoute> get branchRoutes => [
    branchRoute(
      destination: destination,
      builder: (context) => const OwnersEquityShell(),
    ),
  ];
}