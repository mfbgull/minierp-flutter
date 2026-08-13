import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/dashboard_summary.dart'
    show
        ArSummaryResult,
        CashAccountPosition,
        DashboardSummary,
        DayTotal,
        LowStockItem,
        StockByCategory,
        TopCustomer;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/date_range_picker.dart' show DateRangeFilter;
import '../../widgets/screen_toolbar.dart' show ScreenToolbar;
import '../reports/report_providers.dart'
    show applyGlobalReportRange, globalReportFromDateProvider, globalReportToDateProvider;
import 'cash_opening_balance_dialog.dart' show showCashOpeningBalanceDialog;
import 'cash_position_detail_dialog.dart';
import 'dashboard_providers.dart';

/// Landing screen behind the auth gate — renders the server-side
/// aggregated KPIs (GET /dashboard/summary, PORTING.md §10). The
/// dashboard *block* customization (16 block types + layout persistence)
/// builds on top of this later.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final summary = ref.watch(dashboardSummaryProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Global date range: the dashboard's From/To picker is the
        // app-wide default for every report page (each page's own
        // picker can still override its range), plus a refresh that
        // reloads all dashboard blocks.
        ScreenToolbar(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          filters: [
            DateRangeFilter(
              fromProvider: globalReportFromDateProvider,
              toProvider: globalReportToDateProvider,
              showAllDates: false,
              onChanged: () {
                final from = ref.read(globalReportFromDateProvider);
                final to = ref.read(globalReportToDateProvider);
                if (from != null && to != null) {
                  applyGlobalReportRange(ref, from, to);
                }
              },
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                l10n.dashboardGlobalDateRangeHint,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          onRefresh: () {
            ref
              ..invalidate(dashboardSummaryProvider)
              ..invalidate(dashboardArSummaryProvider)
              ..invalidate(dashboardCashPositionProvider)
              ..invalidate(dashboardTopCustomersProvider(5));
          },
        ),
        Expanded(
          child: summary.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _DashboardError(
              message: error is ApiError ? error.message : error.toString(),
              onRetry: () => ref.invalidate(dashboardSummaryProvider),
            ),
            data: (data) => _DashboardBody(summary: data),
          ),
        ),
      ],
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Short windows (e.g. a 600px test surface or a small desktop
        // pane): fixed-height block rows inside a scroll view so blocks
        // are never squeezed below their content (which would overflow
        // the panels' internal Columns). Tall windows keep the
        // fill-the-screen Expanded rows.
        final compact = constraints.maxHeight < 560;
        final children = <Widget>[
          // Horizontal stat strip — one fixed-height row so short windows
          // scroll sideways instead of stacking/overflowing.
          SizedBox(
            height: 84,
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
                  label: l10n.dashboardProfit,
                  value: Formatters.currency(summary.totalProfit),
                  icon: Icons.monetization_on_outlined,
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
                _KpiCard(
                  label: l10n.dashboardRecentproductions,
                  value: Formatters.number(summary.recentProductions),
                  // NOT Icons.factory_outlined — that's the Production
                  // rail icon tests tap to navigate.
                  icon: Icons.precision_manufacturing_outlined,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Cash & bank position — closing balance per account (Cash,
          // Bank, Easypaisa, JazzCash, UPaisa), shared with the
          // end-of-day reconciliation report.
          const _CashPositionStrip(),
          const SizedBox(height: 16),
          // Row 1: sales vs purchases + AR aging buckets; row 2: stock
          // by category + top customers + low-stock alerts (all three
          // side by side).
          if (compact)
            SizedBox(height: 360, child: _salesPurchasesRow(summary))
          else
            Expanded(flex: 3, child: _salesPurchasesRow(summary)),
          const SizedBox(height: 16),
          if (compact)
            SizedBox(height: 360, child: _stockInsightsRow(summary))
          else
            Expanded(flex: 3, child: _stockInsightsRow(summary)),
        ];
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        );
        if (compact) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: content,
          );
        }
        return Padding(padding: const EdgeInsets.all(20), child: content);
      },
    );
  }

  Widget _salesPurchasesRow(DashboardSummary summary) => Row(
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
      Expanded(flex: 2, child: const _ArSummaryPanel()),
    ],
  );

  Widget _stockInsightsRow(DashboardSummary summary) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        flex: 2,
        child: _StockByCategoryPanel(
          categories: summary.stockByCategory,
        ),
      ),
      const SizedBox(width: 16),
      Expanded(flex: 3, child: const _TopCustomersPanel()),
      const SizedBox(width: 16),
      Expanded(
        flex: 2,
        child: _LowStockPanel(items: summary.lowStockItems),
      ),
    ],
  );
}

/// Closing cash/bank balances per account (`GET /dashboard/cash-position`)
/// — a compact horizontal strip so the day's cash position is visible
/// on the dashboard without opening the reconciliation report.
class _CashPositionStrip extends ConsumerStatefulWidget {
  const _CashPositionStrip();

  @override
  ConsumerState<_CashPositionStrip> createState() =>
      _CashPositionStripState();
}

class _CashPositionStripState extends ConsumerState<_CashPositionStrip> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final position = ref.watch(dashboardCashPositionProvider);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  // Not account_balance_wallet_outlined — that's the
                  // Payments rail icon the tests tap to navigate.
                  Icons.savings_outlined,
                  size: 18,
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.dashboardCashbankposition,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: () =>
                      showCashOpeningBalanceDialog(context, ref),
                  icon: const Icon(Icons.playlist_add, size: 15),
                  label: Text(l10n.dashboardOpeningbalance),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    textStyle: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => context.go('/reports/cash-reconciliation'),
                  icon: const Icon(Icons.open_in_new, size: 15),
                  label: Text(l10n.dashboardCashrecon),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    textStyle: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                  ),
                  onPressed: () => setState(() => _expanded = !_expanded),
                  visualDensity: VisualDensity.compact,
                  tooltip: _expanded ? l10n.commonHide : l10n.commonShow,
                ),
              ],
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 200),
              crossFadeState: _expanded
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              firstChild: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: SizedBox(
                  height: 86,
                  child: position.when(
                    loading: () => const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    error: (error, _) => _PanelError(
                      message: error is ApiError
                          ? error.message
                          : error.toString(),
                      onRetry: () =>
                          ref.invalidate(dashboardCashPositionProvider),
                    ),
                    data: (data) => ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final account in data.accounts)
                          _CashPositionCard(account: account),
                        // Grand total as a highlighted trailing card.
                        _CashTotalCard(total: data.total),
                      ],
                    ),
                  ),
                ),
              ),
              secondChild: const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _CashPositionCard extends StatelessWidget {
  const _CashPositionCard({required this.account});

  final CashAccountPosition account;

  // Per-account accent (soft fill + icon tint), matching the wallet
  // colors used across the app's money screens.
  static const Map<String, Color> _accents = {
    'cash': Color(0xFF16A34A),
    'bank': Color(0xFF2563EB),
    'easypaisa': Color(0xFF0D9488),
    'jazzcash': Color(0xFFEA580C),
    'upaisa': Color(0xFF7C3AED),
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = _accents[account.key] ?? scheme.primary;
    final inColor = const Color(0xFF16A34A);
    return GestureDetector(
      onTap: () =>
          showCashPositionDetailDialog(context, account: account),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 190,
          margin: const EdgeInsets.only(right: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accent.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Icon(Icons.savings_outlined, size: 15, color: accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      account.name,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  Formatters.currency(account.balance),
                  maxLines: 1,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              // Compact money-in / money-out so the balance is traceable
              // at a glance: +inflow / −outflow. Tap opens the detail.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_upward, size: 11, color: inColor),
                    const SizedBox(width: 2),
                    Text(
                      Formatters.number(account.inflow),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: inColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.arrow_downward, size: 11, color: scheme.error),
                    const SizedBox(width: 2),
                    Text(
                      Formatters.number(account.outflow),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CashTotalCard extends StatelessWidget {
  const _CashTotalCard({required this.total});

  final num total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 190,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            AppLocalizations.of(context)!.commonTotal,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              Formatters.currency(total),
              maxLines: 1,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
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
      width: 188,
      height: 84,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: scheme.primary),
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
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
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
    }.toList()..sort();

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
                Text(
                  l10n.commonSales,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(width: 16),
                _LegendDot(color: scheme.secondary),
                const SizedBox(width: 6),
                Text(
                  l10n.commonPurchases,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
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
        // Leave a little room for the date labels (which are Flexible
        // and can shrink); never negative on tiny windows.
        final barAreaHeight = math.max(0.0, constraints.maxHeight - 20);
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
                            height:
                                (_totalFor(sales, date) / safeMax) *
                                barAreaHeight,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 3),
                          _Bar(
                            height:
                                (_totalFor(purchases, date) / safeMax) *
                                barAreaHeight,
                            color: scheme.secondary,
                          ),
                        ],
                      ),
                    ),
                    // Flexible so a very short chart panel (e.g. the
                    // dashboard's 3-row layout on a small window) clips
                    // the label instead of overflowing the Column.
                    Flexible(
                      child: Text(
                        _shortDate(date),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
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

/// Donut chart of stock value split by item category
/// (`GET /dashboard/summary` → `stockByCategory`; web visual spec:
/// `StockByCategoryBlock.tsx`).
class _StockByCategoryPanel extends StatelessWidget {
  const _StockByCategoryPanel({required this.categories});

  final List<StockByCategory> categories;

  // Matches the web block's palette (rgba 0.6 fills).
  static const List<Color> _palette = [
    Color(0xFF36A2EB),
    Color(0xFFFF6384),
    Color(0xFFFFCE56),
    Color(0xFF4BC0C0),
    Color(0xFF9966FF),
    Color(0xFFFF9F40),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final total = categories.fold<num>(0, (sum, c) => sum + c.totalStock);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.dashboardStockbycategory,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: categories.isEmpty
                  ? Center(
                      child: Text(
                        l10n.commonNodata,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        // Never overflow narrow windows: the donut scales
                        // with the panel (168 desktop, ~45% of the inner
                        // width down to a 40px floor — small enough that
                        // the 16px legend gap can't overflow).
                        final donutSize = math.min(
                          168.0,
                          math.max(40.0, constraints.maxWidth * 0.45),
                        );
                        return Row(
                          children: [
                            SizedBox(
                              width: donutSize,
                              height: donutSize,
                              child: PieChart(
                                PieChartData(
                                  sections: [
                                    for (var i = 0; i < categories.length; i++)
                                      PieChartSectionData(
                                        value: categories[i].totalStock
                                            .toDouble(),
                                        color: _palette[i % _palette.length],
                                        radius: donutSize * 0.27,
                                        showTitle: false,
                                      ),
                                  ],
                                  centerSpaceRadius: donutSize * 0.24,
                                  sectionsSpace: 2,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: ListView(
                                children: [
                                  for (var i = 0; i < categories.length; i++)
                                    _CategoryLegendRow(
                                      color: _palette[i % _palette.length],
                                      category: categories[i].category,
                                      total: categories[i].totalStock,
                                      pct: total > 0
                                          ? (categories[i].totalStock / total)
                                          : 0,
                                    ),
                                ],
                              ),
                            ),
                          ],
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

class _CategoryLegendRow extends StatelessWidget {
  const _CategoryLegendRow({
    required this.color,
    required this.category,
    required this.total,
    required this.pct,
  });

  final Color color;
  final String category;
  final num total;
  final double pct;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              category,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '${Formatters.number(total)}'
              ' (${(pct * 100).toStringAsFixed(0)}%)',
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact inline error + retry used inside a single dashboard panel
/// (the full-screen `_DashboardError` is only for the summary fetch).
class _PanelError extends StatelessWidget {
  const _PanelError({required this.message, required this.onRetry});

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
          Icon(Icons.cloud_off_outlined, size: 32, color: scheme.outline),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              message,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16),
            label: Text(l10n.commonRefresh),
          ),
        ],
      ),
    );
  }
}

/// Accounts-receivable aging buckets (`GET /dashboard/ar-summary`; web
/// visual spec: `ARSummaryBlock.tsx`).
class _ArSummaryPanel extends ConsumerWidget {
  const _ArSummaryPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final ar = ref.watch(dashboardArSummaryProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.dashboardArsummary,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ar.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => _PanelError(
                  message: error is ApiError ? error.message : error.toString(),
                  onRetry: () => ref.invalidate(dashboardArSummaryProvider),
                ),
                data: (data) => _ArSummaryBody(ar: data),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArSummaryBody extends StatelessWidget {
  const _ArSummaryBody({required this.ar});

  final ArSummaryResult ar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    // Matches the web block's bucket colors (green → dark red as the
    // age increases).
    final buckets = [
      (
        label: l10n.reportsCurrent,
        amount: ar.currentAmount,
        color: const Color(0xFF22C55E),
      ),
      (
        label: l10n.reportsDays1_30,
        amount: ar.amount130,
        color: const Color(0xFFEAB308),
      ),
      (
        label: l10n.reportsDays31_60,
        amount: ar.amount3160,
        color: const Color(0xFFF97316),
      ),
      (
        label: l10n.reportsDays61_90,
        amount: ar.amount6190,
        color: const Color(0xFFEF4444),
      ),
      (
        label: l10n.reportsDays90plus,
        amount: ar.amountOver90,
        color: const Color(0xFFDC2626),
      ),
    ];
    final maxAmount = buckets.fold<num>(
      0,
      (m, b) => b.amount > m ? b.amount : m,
    );
    final safeMax = maxAmount <= 0 ? 1.0 : maxAmount.toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  Formatters.currency(ar.totalAr),
                  maxLines: 1,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                '${Formatters.number(ar.customerCount)} ${l10n.dashboardCustomers}',
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            children: [
              for (final bucket in buckets)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          bucket.label,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: LinearProgressIndicator(
                            value: (bucket.amount / safeMax)
                                .clamp(0, 1)
                                .toDouble(),
                            minHeight: 10,
                            backgroundColor: scheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation(bucket.color),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          Formatters.currency(bucket.amount),
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Ranked list of top customers by revenue (`GET /dashboard/top-customers`,
/// default limit 5; web visual spec: `TopCustomersBlock.tsx`).
class _TopCustomersPanel extends ConsumerWidget {
  const _TopCustomersPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final customers = ref.watch(dashboardTopCustomersProvider(5));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.dashboardTopcustomers,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: customers.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => _PanelError(
                  message: error is ApiError ? error.message : error.toString(),
                  onRetry: () =>
                      ref.invalidate(dashboardTopCustomersProvider(5)),
                ),
                data: (data) => _TopCustomersBody(customers: data),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopCustomersBody extends StatelessWidget {
  const _TopCustomersBody({required this.customers});

  final List<TopCustomer> customers;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    if (customers.isEmpty) {
      return Center(
        child: Text(
          l10n.commonNodata,
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }
    final maxRevenue = customers.fold<num>(
      0,
      (m, c) => c.totalRevenue > m ? c.totalRevenue : m,
    );
    final safeMax = maxRevenue <= 0 ? 1.0 : maxRevenue.toDouble();

    return ListView.separated(
      itemCount: customers.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final customer = customers[index];
        final isTop = index == 0;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              // Rank badge — gold for #1, neutral otherwise (web spec).
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isTop
                      ? const Color(0xFFEAB308)
                      : scheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${index + 1}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: isTop ? Colors.white : scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.customerName,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: (customer.totalRevenue / safeMax)
                            .clamp(0, 1)
                            .toDouble(),
                        minHeight: 6,
                        backgroundColor: scheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation(scheme.primary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      Formatters.currency(customer.totalRevenue),
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${Formatters.number(customer.invoiceCount)} '
                      '${l10n.dashboardInvoices}',
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
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
                          Icon(
                            Icons.check_circle_outline,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              l10n.dashboardWellstocked,
                              style: TextStyle(color: scheme.onSurfaceVariant),
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
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: urgent
                                      ? scheme.error
                                      : scheme.onSurfaceVariant,
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
