// Forecast dashboard (PORTING.md §12) — mirrors `ForecastDashboard.tsx`:
// four stat cards (tracked items / need restock / avg confidence /
// critical alerts), an alerts list and the top-growing items list, all
// fed by `GET /forecasts/dashboard`. The alert badge color logic and the
// "view all → demand / trends" links carry over from the web client.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/api_result.dart' show ApiError;
import '../../widgets/screen_error_panel.dart';
import '../../l10n/app_localizations.dart';
import 'forecast_models.dart';
import 'forecast_providers.dart';
import 'forecast_repository.dart' show ForecastDemandFilters;

class ForecastDashboardScreen extends ConsumerWidget {
  const ForecastDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final dashboard = ref.watch(forecastDashboardProvider);

    return dashboard.when(
      loading: () => const _DashboardSkeleton(),
      error: (error, _) => ScreenErrorPanel(
        message: error is ApiError ? error.message : l10n.forecastsLoaderror,
        onRetry: () => ref.invalidate(forecastDashboardProvider),
      ),
      data: (data) => _DashboardBody(
        data: data,
        onRefresh: () => ref.invalidate(forecastDashboardProvider),
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({required this.data, required this.onRefresh});

  final ForecastDashboardData data;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.forecastsDashboard,
                  style: textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(l10n.forecastsRefresh),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // ── Stat cards ─────────────────────────────────────────────
          LayoutBuilder(
            builder: (context, constraints) {
              // Two per row on narrow panes, four on wide.
              final columns = constraints.maxWidth >= 720
                  ? 4
                  : constraints.maxWidth >= 400
                  ? 2
                  : 1;
              final cardWidth =
                  (constraints.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _StatCard(
                    width: cardWidth,
                    icon: Icons.inventory_2_outlined,
                    label: l10n.forecastsTrackeditems,
                    value: '${data.totalItems}',
                  ),
                  _StatCard(
                    width: cardWidth,
                    icon: Icons.warning_amber_outlined,
                    label: l10n.forecastsNeedrestock,
                    value: '${data.itemsNeedingRestock}',
                    alert: data.itemsNeedingRestock > 0,
                  ),
                  _StatCard(
                    width: cardWidth,
                    icon: Icons.insights_outlined,
                    label: l10n.forecastsAvgconfidence,
                    value: '${data.avgConfidence}%',
                  ),
                  _StatCard(
                    width: cardWidth,
                    icon: Icons.verified_outlined,
                    label: l10n.forecastsCriticalalerts,
                    value: '${data.criticalAlerts}',
                    alert: data.criticalAlerts > 0,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          // ── Alerts ────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.forecastsAlerts,
                  style: textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                // "View All" lands on the *full* demand list — clear any
                // filters left over from a previous visit first so the
                // jump isn't scoped to a stale category/trend/status.
                onPressed: () {
                  ref.read(forecastDemandFiltersProvider.notifier).state =
                      const ForecastDemandFilters();
                  ref.read(forecastShellTabProvider.notifier).state = 1;
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.forecastsViewall),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward, size: 16),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (data.alerts.isEmpty)
            _EmptyNote(text: l10n.forecastsNoalerts)
          else
            ...data.alerts.take(10).map((a) => _AlertCard(alert: a)),
          const SizedBox(height: 20),
          // ── Top growing ───────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.forecastsTopgrowing,
                  style: textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed: () =>
                    ref.read(forecastShellTabProvider.notifier).state = 2,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.forecastsViewtrends),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward, size: 16),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (data.topGrowing.isEmpty)
            _EmptyNote(text: l10n.forecastsNotrenddata)
          else
            ...data.topGrowing.take(6).map((f) => _TrendItem(forecast: f)),
          const SizedBox(height: 24),
        ],
      ),    );
  }
}

/// The reference AlertCard — level-tinted card with item name, stock vs
/// predicted and a badge (critical → warning → OK).
class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert});

  final ForecastAlert alert;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final (Color color, Color bg, String label) = switch (alert.alertLevel) {
      'critical' => (
        const Color(0xFFDC2626),
        const Color(0xFFFEE2E2),
        l10n.forecastsCritical,
      ),
      'warning' => (
        const Color(0xFFD97706),
        const Color(0xFFFEF3C7),
        l10n.forecastsWarning,
      ),
      _ => (
        const Color(0xFF16A34A),
        const Color(0xFFDCFCE7),
        l10n.forecastsOk,
      ),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert.itemName,
                  style: textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${l10n.commonStock}: ${_num(alert.currentStock)} | '
                  '${l10n.forecastsPredictedmonth}: ${_num(alert.predictedDemand)}',
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              style: textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendItem extends StatelessWidget {
  const _TrendItem({required this.forecast});

  final ForecastDemand forecast;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final growing = forecast.trend == 'growing';
    final color = growing
        ? const Color(0xFF16A34A)
        : const Color(0xFFDC2626);
    final icon = growing ? Icons.trending_up : Icons.trending_down;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              forecast.itemName,
              style: textTheme.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${forecast.trendPercentage.toStringAsFixed(0)}%',
              style: textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
    this.alert = false,
  });

  final double width;
  final IconData icon;
  final String label;
  final String value;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: alert ? scheme.error : scheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                value,
                maxLines: 1,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: alert ? scheme.error : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Text(
          text,
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 200,
            height: 24,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: List.generate(
              4,
              (i) => Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: i < 3 ? 12 : 0,
                  ),
                  child: Container(
                    height: 96,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          ...List.generate(
            4,
            (i) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _num(num v) => v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);
