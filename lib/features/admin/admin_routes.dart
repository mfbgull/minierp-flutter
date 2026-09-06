import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/module_routes.dart';
import 'admin_shell.dart';

class AdminRoutes extends ModuleRoutes {
  const AdminRoutes();

  @override
  ShellDestination get destination => ShellDestination(
    path: '/admin',
    label: (l) => l.navUsers,
    icon: Icons.admin_panel_settings_outlined,
    adminOnly: true,
  );

  @override
  List<GoRoute> get branchRoutes => [
    branchRoute(
      destination: destination,
      builder: (context) => const AdminShell(),
    ),
  ];
}