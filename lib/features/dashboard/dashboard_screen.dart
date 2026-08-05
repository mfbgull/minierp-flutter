import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/dashboard_summary.dart'
    show DashboardSummary, DayTotal, LowStockItem;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import 'dashboard_providers.dart';

/// Landing screen behind the auth gate — renders the server-side
/// aggregated KPIs (GET /dashboard/summary, PORTING.md §10). The
/// dashboard *block* customization (16 block types + layout persistence)
/// builds on top of this later.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(dashboardSummaryProvider);
    return summary.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _DashboardError(
        message: error is ApiError ? error.message : error.toString(),
        onRetry: () => ref.invalidate(dashboardSummaryProvider),
      ),
      data: (data) => _DashboardBody(summary: data),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Horizontal stat strip — one fixed-height row so short windows
          // scroll sideways instead of stacking/overflowing.
          SizedBox(
            height: 108,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _KpiCard(
                  label: l10n.dashboardTotalitems,
                  value: Formatters.number(summary.totalItems),
                  icon: Icons.inventory_2_outlined,
                ),
                _KpiCard(
                  label: l10n.dashboardStockvalue,
                  value: Formatters.currency(summary.totalStockValue),
                  icon: Icons.paid_outlined,
                ),
                _KpiCard(
                  label: l10n.dashboardSalesrevenue,
                  value: Formatters.currency(summary.totalSalesRevenue),
                  icon: Icons.trending_up,
                ),
                _KpiCard(
                  label: l10n.navPurchases,
                  value: Formatters.currency(summary.totalPurchases),
                  icon: Icons.shopping_cart_outlined,
                ),
                _KpiCard(
                  label: l10n.dashboardWarehousestocks,
                  value: Formatters.number(summary.warehouseStockCount),
                  icon: Icons.warehouse_outlined,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: _SalesVsPurchasesPanel(
                    sales: summary.salesByDay,
                    purchases: summary.purchasesByDay,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: _LowStockPanel(items: summary.lowStockItems),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 232,
      height: 108,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              // Scale down instead of wrapping — stat values must never
              // overflow the fixed card height.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Simple bar chart: sales vs purchases totals per day over the last week.
class _SalesVsPurchasesPanel extends StatelessWidget {
  const _SalesVsPurchasesPanel({required this.sales, required this.purchases});

  final List<DayTotal> sales;
  final List<DayTotal> purchases;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final dates = {
      for (final d in [...sales, ...purchases]) d.date,
    }.toList()
      ..sort();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.dashboardSalesvspurchases,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: dates.isEmpty
                  ? Center(
                      child: Text(
                        l10n.commonNodata,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    )
                  : _DayBars(sales: sales, purchases: purchases, dates: dates),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _LegendDot(color: scheme.primary),
                const SizedBox(width: 6),
                Text(l10n.commonSales, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(width: 16),
                _LegendDot(color: scheme.secondary),
                const SizedBox(width: 6),
                Text(l10n.commonPurchases, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DayBars extends StatelessWidget {
  const _DayBars({
    required this.sales,
    required this.purchases,
    required this.dates,
  });

  final List<DayTotal> sales;
  final List<DayTotal> purchases;
  final List<String> dates;

  double _totalFor(List<DayTotal> series, String date) {
    for (final d in series) {
      if (d.date == date) return d.total.toDouble();
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final maxValue = [
      for (final date in dates) _totalFor(sales, date),
      for (final date in dates) _totalFor(purchases, date),
    ].fold<double>(0, (m, v) => math.max(m, v));
    final safeMax = maxValue <= 0 ? 1.0 : maxValue;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Leave room for the date labels; never negative on tiny windows.
        final barAreaHeight = math.max(0.0, constraints.maxHeight - 28);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final date in dates)
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(
                      height: barAreaHeight,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _Bar(
                            height: (_totalFor(sales, date) / safeMax) * barAreaHeight,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 3),
                          _Bar(
                            height: (_totalFor(purchases, date) / safeMax) * barAreaHeight,
                            color: scheme.secondary,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _shortDate(date),
                      style: textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  /// YYYY-MM-DD → "M/d".
  String _shortDate(String iso) {
    final parts = iso.split('-');
    if (parts.length != 3) return iso;
    return '${int.tryParse(parts[1]) ?? parts[1]}/${int.tryParse(parts[2]) ?? parts[2]}';
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.height, required this.color});

  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: math.max(height, 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.85),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _LowStockPanel extends StatelessWidget {
  const _LowStockPanel({required this.items});

  final List<LowStockItem> items;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.dashboardLowstockalerts,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_outline,
                              color: scheme.primary),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              l10n.dashboardWellstocked,
                              style:
                                  TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final ratio = item.reorderLevel > 0
                            ? (item.currentStock / item.reorderLevel)
                            : 0;
                        final urgent = ratio <= 0.5;
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.warning_amber_rounded,
                            color: urgent ? scheme.error : scheme.secondary,
                          ),
                          title: Text(
                            item.itemName,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          subtitle: Text(
                            '${item.itemCode} · ${item.category ?? ''}'.trim(),
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Text(
                            '${Formatters.number(item.currentStock)} / '
                            '${Formatters.number(item.reorderLevel)}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: urgent ? scheme.error : scheme.onSurfaceVariant,
                                  fontWeight: urgent ? FontWeight.w600 : null,
                                ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardError extends StatelessWidget {
  const _DashboardError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_outlined, size: 56, color: scheme.outline),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text(l10n.commonRefresh),
          ),
        ],
      ),
    );
  }
}
