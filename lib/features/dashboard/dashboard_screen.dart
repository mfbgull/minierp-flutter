import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/dashboard_layout.dart'
    show DashboardBlock, DashboardBlockSize;
import '../../data/models/dashboard_summary.dart'
    show
        ArSummaryResult,
        CashAccountPosition,
        DashboardSummary,
        DayTotal,
        KpiResult,
        LowStockItem,
        StockByCategory,
        TopCustomer;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/date_range_picker.dart' show DateRangeFilter;
import '../../widgets/offline_cache_badge.dart';
import '../../widgets/screen_toolbar.dart' show ScreenToolbar;
import '../reports/report_providers.dart'
    show applyGlobalReportRange, globalReportFromDateProvider, globalReportToDateProvider;
import '../inventory/batch_management_screen.dart'
    show showBatchManagementScreen;
import '../reports/report_providers.dart' show expiryAlertsProvider;
import 'cash_opening_balance_dialog.dart' show showCashOpeningBalanceDialog;
import 'cash_position_detail_dialog.dart';
import 'dashboard_customizer_dialog.dart' show showDashboardCustomizerDialog;
import 'dashboard_kpi_catalog.dart'
    show KpiCardFormat, kpiCardById, kpiCardHint, kpiCardLabel;
import 'dashboard_layout_controller.dart'
    show
        kKpiCardHeight,
        kKpiCardWidthFor,
        panelFlexFor,
        dashboardLayoutControllerProvider;
import 'dashboard_panel_catalog.dart' show panelById;
import 'dashboard_providers.dart';
import 'panels/active_loans_panel.dart';
import 'package:minierp_app/core/theme/app_border_radius.dart';
import 'package:minierp_app/widgets/skeleton_loader.dart';

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
          actions: [const OfflineCacheBadge()],
          onRefresh: () {
            // The KPI strip cards fetch per-card `/dashboard/kpi`
            // values — they need their own invalidation or a new sale /
            // invoice stays stale until hot restart.
            invalidateDashboardKpiCards(ref);
            ref
              ..invalidate(dashboardSummaryProvider)
              ..invalidate(dashboardArSummaryProvider)
              ..invalidate(dashboardCashPositionProvider)
              ..invalidate(dashboardTopCustomersProvider(5));
          },
          // The "Customize" button (spec §6.1) — labeled, after the
          // refresh button, opens the KPI card customizer dialog.
          trailingActions: [
            TextButton.icon(
              onPressed: () => showDashboardCustomizerDialog(context),
              icon: const Icon(Icons.tune, size: 18),
              label: Text(l10n.dashboardcustomizationCustomize),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
        Expanded(
          child: summary.when(
            loading: () => const SingleChildScrollView(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  KpiStripSkeleton(),
                  SizedBox(height: 16),
                  SizedBox(height: 320, child: ChartPanelSkeleton()),
                  SizedBox(height: 16),
                  SizedBox(height: 320, child: ListPanelSkeleton()),
                ],
              ),
            ),
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

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(dashboardLayoutControllerProvider);
    final cashVisible = layout.blocks.any(
      (b) => b.id == 'cash_strip' && b.visible,
    );
    // Visible panels per row (empty rows collapse entirely, spec §6.5).
    final row1 = [
      for (final b in layout.blocks)
        if (b.visible && panelById[b.id]?.row == 1) b,
    ];
    final row2 = [
      for (final b in layout.blocks)
        if (b.visible && panelById[b.id]?.row == 2) b,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Short windows (e.g. a 600px test surface or a small desktop
        // pane): fixed-height block rows inside a scroll view so blocks
        // are never squeezed below their content (which would overflow
        // the panels' internal Columns). Tall windows keep the
        // fill-the-screen Expanded rows.
        final compact = constraints.maxHeight < 560;
        final children = <Widget>[
          // Horizontal stat strip — driven by the user's dashboard
          // layout (spec §6.3): only visible cards, in layout order,
          // each fetching its own `/dashboard/kpi` value. Reorderable
          // on the strip itself (hover drag handle / long-press).
          const _KpiStrip(),
          // Cash & bank strip — shown/hidden per the user's layout.
          if (cashVisible) ...[
            const SizedBox(height: 16),
            const _CashPositionStrip(),
          ],
          // Row 1: sales vs purchases + AR aging (visible panels only,
          // reorderable within the row).
          if (row1.isNotEmpty) ...[
            const SizedBox(height: 16),
            if (compact)
              SizedBox(height: 360, child: _PanelRow(row: 1, summary: summary))
            else
              Expanded(flex: 3, child: _PanelRow(row: 1, summary: summary)),
          ],
          // Row 2: stock by category + top customers + low stock.
          if (row2.isNotEmpty) ...[
            const SizedBox(height: 16),
            if (compact)
              SizedBox(height: 360, child: _PanelRow(row: 2, summary: summary))
            else
              Expanded(flex: 3, child: _PanelRow(row: 2, summary: summary)),
          ],
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
                    // Compact strip skeleton matching the real cards:
                    // 4 placeholder cards sized to the 86px strip.
                    loading: () => ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: 4,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (_, _) => Container(
                        width: 190,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(
                            alpha: 0.5,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SkeletonBar(height: 10, width: 80),
                            SizedBox(height: 6),
                            SkeletonBar(height: 16, width: 100),
                          ],
                        ),
                      ),
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
            borderRadius: AppBorderRadius.mdRadius,
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
        borderRadius: AppBorderRadius.mdRadius,
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

/// The horizontal KPI stat strip — reads the dashboard layout controller
/// and renders only the visible cards, in order, each fetching its own
/// metric via `dashboardKpiBatchProvider`. Reorderable (spec §6.3: reorder
/// on the strip itself, drag handle on hover / long-press on touch).
class _KpiStrip extends ConsumerWidget {
  const _KpiStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final layout = ref.watch(dashboardLayoutControllerProvider);
    // Only KPI cards belong in the strip — panels + the cash strip are
    // rendered by their own widgets from the same layout.
    final visible = [
      for (final block in layout.blocks)
        if (block.visible && kpiCardById.containsKey(block.id)) block,
    ];

    // Empty state (spec §8): all cards hidden — the toolbar Customize
    // button stays reachable to add them back.
    if (visible.isEmpty) {
      return SizedBox(
        height: kKpiCardHeight,
        child: Center(
          child: Text(
            l10n.dashboardcardsEmpty,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: kKpiCardHeight,
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: false,
        itemCount: visible.length,
        onReorderItem: (oldIndex, newIndex) =>
            ref.read(dashboardLayoutControllerProvider.notifier).reorder(
              oldIndex,
              newIndex,
            ),
        itemBuilder: (context, index) {
          final block = visible[index];
          return _KpiMetricCard(
            key: ValueKey(block.id),
            block: block,
            index: index,
          );
        },
      ),
    );
  }
}

/// One dashboard row of content panels — rendered from the user's
/// layout (spec §6.5): only visible panels of this row, in order, sized
/// by their flex ratios, reorderable within the row. An empty row (all
/// panels hidden) collapses entirely — `_DashboardBody` skips it.
class _PanelRow extends ConsumerWidget {
  const _PanelRow({required this.row, required this.summary});

  final int row;
  final DashboardSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(dashboardLayoutControllerProvider);
    final visible = [
      for (final block in layout.blocks)
        if (block.visible && panelById[block.id]?.row == row) block,
    ];
    int flexOf(DashboardBlock b) =>
        panelFlexFor(panelById[b.id]?.flex ?? 1, b.config.size);
    final totalFlex = visible.fold<int>(0, (sum, b) => sum + flexOf(b));

    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = 16.0;
        // Remaining width after the inter-panel gaps, split by flex.
        final available = math.max(
          0.0,
          constraints.maxWidth - gap * (visible.length - 1),
        );
        return ReorderableListView(
          scrollDirection: Axis.horizontal,
          buildDefaultDragHandles: false,
          onReorderItem: (oldIndex, newIndex) =>
              ref.read(dashboardLayoutControllerProvider.notifier)
                  .reorderPanels(row, oldIndex, newIndex),
          children: [
            for (var i = 0; i < visible.length; i++)
              Padding(
                key: ValueKey(visible[i].id),
                padding: EdgeInsets.only(
                  right: i == visible.length - 1 ? 0 : gap,
                ),
                child: SizedBox(
                  width: available * (flexOf(visible[i]) / totalFlex),
                  child: _PanelFrame(
                    block: visible[i],
                    index: i,
                    summary: summary,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Wraps one panel with a hover drag handle (desktop) / long-press drag
/// (touch) — the row reorder affordance (spec §12: panel header while
/// customizing). The handle sits in the panel's top-right corner.
class _PanelFrame extends ConsumerStatefulWidget {
  const _PanelFrame({
    required this.block,
    required this.index,
    required this.summary,
  });

  final DashboardBlock block;
  final int index;
  final DashboardSummary summary;

  @override
  ConsumerState<_PanelFrame> createState() => _PanelFrameState();
}

class _PanelFrameState extends ConsumerState<_PanelFrame> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final panel = switch (widget.block.id) {
      'panel_sales_purchases' => _SalesVsPurchasesPanel(
        sales: widget.summary.salesByDay,
        purchases: widget.summary.purchasesByDay,
      ),
      'panel_ar_aging' => const _ArSummaryPanel(),
      'panel_stock_by_category' => _StockByCategoryPanel(
        categories: widget.summary.stockByCategory,
      ),
      'panel_top_customers' => const _TopCustomersPanel(),
      'panel_low_stock' => _LowStockPanel(items: widget.summary.lowStockItems),
      'panel_expiry_alerts' => const _ExpiryAlertsPanel(),
      'panel_active_loans' => const ActiveLoansPanel(),
      _ => const SizedBox.shrink(),
    };

    final body = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Stack(
        children: [
          panel,
          if (_hovered)
            Positioned(
              top: 6,
              right: 6,
              child: ReorderableDragStartListener(
                index: widget.index,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: AppBorderRadius.xsRadius,
                    boxShadow: [
                      BoxShadow(
                        color: scheme.shadow.withValues(alpha: 0.15),
                        blurRadius: 2,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.drag_indicator,
                    size: 14,
                    color: scheme.outline,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    return ReorderableDelayedDragStartListener(
      index: widget.index,
      child: body,
    );
  }
}

/// One KPI card in the strip — fetches its metric value via
/// `/dashboard/kpi?metric=` and formats it per its catalog definition.
/// Draggable: a drag handle appears on hover (desktop); long-press
/// starts the drag on touch (ReorderableDelayedDragStartListener).
class _KpiMetricCard extends ConsumerStatefulWidget {
  const _KpiMetricCard({
    super.key,
    required this.block,
    required this.index,
  });

  final DashboardBlock block;

  /// Index into the *visible* strip (ReorderableListView indices) — the
  /// drag listeners must use this, not the block's grid `x`.
  final int index;

  @override
  ConsumerState<_KpiMetricCard> createState() => _KpiMetricCardState();
}

class _KpiMetricCardState extends ConsumerState<_KpiMetricCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final def = kpiCardById[widget.block.id];
    if (def == null) return const SizedBox.shrink();

    final label = kpiCardLabel(l10n, def.labelKey);
    final hint = kpiCardHint(l10n, def.hintKey);
    // All KPI values arrive in one batched fetch (spec 7.3) — read the
    // card's metric out of the shared map.
    final kpi = ref.watch(dashboardKpiBatchProvider);

    // Per-size styling (spec §6.3): Small = denser padding + smaller
    // value font; Large = extra padding + larger value font; Medium =
    // the current card.
    final size = widget.block.config.size ?? DashboardBlockSize.medium;
    final cardPadding = switch (size) {
      DashboardBlockSize.small => const EdgeInsets.all(8),
      DashboardBlockSize.large => const EdgeInsets.all(16),
      _ => const EdgeInsets.all(12),
    };
    final valueStyle = (Theme.of(context).textTheme.titleMedium ?? const TextStyle())
        .copyWith(fontWeight: FontWeight.w700);
    final compactValueStyle = valueStyle.copyWith(
      fontSize: valueStyle.fontSize == null
          ? null
          : valueStyle.fontSize! - (size == DashboardBlockSize.small ? 3 : 0),
    );
    final largeValueStyle = valueStyle.copyWith(
      fontSize: valueStyle.fontSize == null
          ? null
          : (valueStyle.fontSize ?? 0) +
                (size == DashboardBlockSize.large ? 4 : 0),
    );
    final valueTextStyle = switch (size) {
      DashboardBlockSize.small => compactValueStyle,
      DashboardBlockSize.large => largeValueStyle,
      _ => valueStyle,
    };

    final card = SizedBox(
      width: kKpiCardWidthFor(widget.block.config.size),
      height: kKpiCardHeight,
      child: Card(
        child: Padding(
          padding: cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(def.icon, size: 16, color: scheme.primary),
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
                  // Hover drag handle (desktop). MouseRegion on the card
                  // tracks hover; the handle starts the reorder drag.
                  if (_hovered)
                    ReorderableDragStartListener(
                      index: widget.index,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Icon(
                          Icons.drag_indicator,
                          size: 14,
                          color: scheme.outline,
                        ),
                      ),
                    ),
                ],
              ),
              // Scale down instead of wrapping — stat values must never
              // overflow the fixed card height.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: kpi.when(
                  loading: () => Text(
                    '—',
                    style: valueTextStyle.copyWith(color: scheme.outline),
                  ),
                  error: (error, _) => Text(
                    '—',
                    style: valueTextStyle.copyWith(color: scheme.error),
                  ),
                  data: (values) {
                    final kpi = values[def.metric];
                    if (kpi == null) {
                      return Text(
                        '—',
                        style: valueTextStyle.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      );
                    }
                    return Text(
                      _formatKpiValue(def.format, kpi),
                      maxLines: 1,
                      style: valueTextStyle,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final body = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: hint == null
          ? card
          : Tooltip(message: hint, child: card),
    );
    return ReorderableDelayedDragStartListener(
      index: widget.index,
      child: body,
    );
  }

  /// Formats a KPI result according to its catalog display format.
  String _formatKpiValue(KpiCardFormat format, KpiResult kpi) {
    switch (format) {
      case KpiCardFormat.currency:
        return Formatters.currency(kpi.value);
      case KpiCardFormat.number:
        return Formatters.number(kpi.value);
      case KpiCardFormat.percent:
        return '${Formatters.number(kpi.value)}%';
      case KpiCardFormat.ratio:
        return Formatters.number(kpi.value);
    }
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
                loading: () => const ListPanelSkeleton(),
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
                          borderRadius: AppBorderRadius.xsRadius,
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
                loading: () => const ListPanelSkeleton(),
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
                      borderRadius: AppBorderRadius.xsRadius,
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

class _ExpiryAlertsPanel extends ConsumerWidget {
  const _ExpiryAlertsPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final alerts = ref.watch(expiryAlertsProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.expiringSoon,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: switch (alerts) {
                AsyncError(:final error) => Center(
                    child: Text(
                      error is ApiError ? error.message : '$error',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),                AsyncLoading() => const ListPanelSkeleton(),
                AsyncData(:final value) => value.isEmpty
                    ? Center(
                        child: Text(
                          l10n.noExpiringBatches,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      )
                    : ListView.separated(
                        itemCount: value.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final a = value[index];
                          final expired = a.daysRemaining < 0;
                          final near = !expired && a.daysRemaining <= 30;
                          final color = expired
                              ? scheme.error
                              : near
                                  ? const Color(0xffd97706)
                                  : scheme.onSurfaceVariant;
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              expired
                                  ? Icons.event_busy_outlined
                                  : Icons.event_repeat_outlined,
                              color: color,
                            ),
                            title: Text(
                              a.itemName,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            subtitle: Text(
                              '${a.batchNo} · ${a.warehouseName}',
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Text(
                              expired
                                  ? l10n.daysExpired(a.daysRemaining.abs())
                                  : l10n.daysRemaining(a.daysRemaining),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: color,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            onTap: () => showBatchManagementScreen(
                              context,
                              itemId: a.itemId,
                            ),
                          );
                        },
                      ),
              _ => const SizedBox.shrink(),
              },
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
