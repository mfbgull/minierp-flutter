// Forecast module shell (PORTING.md §12) — four tab views over the
// `/forecasts/*` endpoints, modeled on the inventory shell: Dashboard
// (summary + alerts), Demand (filtered forecast grid), Trends (charts +
// breakdown), Accuracy (per-item MAPE table + compute + trend chart).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../shell/module_refresh.dart' show moduleTabRefreshOnVisit;
import 'demand_forecast_screen.dart';
import 'forecast_accuracy_screen.dart';
import 'forecast_dashboard_screen.dart';
import 'forecast_providers.dart' show forecastShellTabProvider;
import 'forecast_trends_screen.dart';

class ForecastShell extends ConsumerStatefulWidget {
  const ForecastShell({super.key});

  @override
  ConsumerState<ForecastShell> createState() => _ForecastShellState();
}

class _ForecastShellState extends ConsumerState<ForecastShell> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final index = ref.watch(forecastShellTabProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (i) {
            ref.read(forecastShellTabProvider.notifier).state = i;
            // Refresh the clicked tab's data (the IndexedStack keeps
            // every tab alive, so its providers would stay cached).
            moduleTabRefreshOnVisit['/forecasts']?[i].call(ref);
          },
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.space_dashboard_outlined),
              selectedIcon: const Icon(Icons.space_dashboard),
              label: l10n.navForecastsdashboard,
            ),
            NavigationDestination(
              icon: const Icon(Icons.trending_up_outlined),
              selectedIcon: const Icon(Icons.trending_up),
              label: l10n.navDemand,
            ),
            NavigationDestination(
              icon: const Icon(Icons.show_chart_outlined),
              selectedIcon: const Icon(Icons.show_chart),
              label: l10n.navForecasttrends,
            ),
            NavigationDestination(
              icon: const Icon(Icons.verified_outlined),
              selectedIcon: const Icon(Icons.verified),
              label: l10n.navForecastaccuracy,
            ),
          ],
        ),
        Expanded(
          child: IndexedStack(
            index: index,
            children: const [
              ForecastDashboardScreen(),
              DemandForecastScreen(),
              ForecastTrendsScreen(),
              ForecastAccuracyScreen(),
            ],
          ),
        ),
      ],
    );
  }
}
