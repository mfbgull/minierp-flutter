import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/module_routes.dart';
import 'integrations_screen.dart';

class IntegrationsRoutes extends ModuleRoutes {
  const IntegrationsRoutes();

  @override
  ShellDestination get destination => ShellDestination(
    path: '/integrations',
    label: (l) => l.navIntegrations,
    icon: Icons.extension_outlined,
    adminOnly: true,
  );

  @override
  List<GoRoute> get branchRoutes => [
    branchRoute(
      destination: destination,
      builder: (context) => const IntegrationsScreen(),
    ),
  ];
}