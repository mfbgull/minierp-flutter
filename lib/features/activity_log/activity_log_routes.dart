import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/module_routes.dart';
import 'activity_log_screen.dart';

class ActivityLogRoutes extends ModuleRoutes {
  const ActivityLogRoutes();

  @override
  ShellDestination get destination => ShellDestination(
    path: '/activity-log',
    label: (l) => l.navActivitylog,
    icon: Icons.history,
  );

  @override
  List<GoRoute> get branchRoutes => [
    branchRoute(
      destination: destination,
      builder: (context) => const ActivityLogScreen(),
    ),
  ];
}