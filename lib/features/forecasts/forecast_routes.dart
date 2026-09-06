import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/module_routes.dart';
import 'forecast_shell.dart';

class ForecastRoutes extends ModuleRoutes {
  const ForecastRoutes();

  @override
  ShellDestination get destination => ShellDestination(
    path: '/forecasts',
    label: (l) => l.navForecasts,
    icon: Icons.insights_outlined,
  );

  @override
  List<GoRoute> get branchRoutes => [
    branchRoute(
      destination: destination,
      builder: (context) => const ForecastShell(),
    ),
  ];
}