// Demand forecast screen (PORTING.md §12) — mirrors `DemandForecast.tsx`:
// a filter bar (category / trend / recommendation — all searchable
// selects), then a PlutoGrid of `GET /forecasts/demand` rows on desktop
// and the reference's compact forecast cards under the 768px breakpoint.
// The demand endpoint recomputes forecasts per call, so each filter
// change refetches through the filter-watching provider.
//
// The grid reuses the shared [PlutoGridScreen] mixin: serial column, F2/
// Enter row shortcut, loading overlay and error panel come free; the
// trend/confidence/recommendation cells use per-cell renderers matching
// the web client's status colors.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/formatters.dart';
import '../../data/repositories/paged_request.dart' show PagedResponse;
import '../../l10n/app_localizations.dart';
import '../../widgets/pagination_bar.dart' show ServerPaginationBar;
import '../../widgets/pluto_grid_screen.dart';
import '../../widgets/searchable_select.dart';
import '../inventory/inventory_providers.dart' show allItemsProvider;
import '../inventory/item_detail_dialog.dart' show showItemDetailDialog;
import 'forecast_models.dart';
import 'forecast_providers.dart';
import 'forecast_repository.dart' show ForecastDemandFilters;

class DemandForecastScreen extends ConsumerStatefulWidget {
  const DemandForecastScreen({super.key});

  @override
  ConsumerState<DemandForecastScreen> createState() =>
      _DemandForecastScreenState();
}

class _DemandForecastScreenState extends ConsumerState<DemandForecastScreen>
    with PlutoGridScreen<ForecastDemand, DemandForecastScreen> {
  Timer? _debounce;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      ref.read(forecastDemandSearchProvider.notifier).state = value.trim();
      // A new search starts back at page 1.
      if (ref.read(forecastDemandPageProvider) != 1) {
        ref.read(forecastDemandPageProvider.notifier).state = 1;
      }
    });
  }

  /// The demand provider returns a `PagedResponse` envelope — unwrap the
  /// current page's items as the grid rows.
  @override
  Iterable<ForecastDemand> gridRowsFrom(Object? value) =>
      (value as PagedResponse<ForecastDemand>).items;

  @override
  void openRowDetail(int rowId) {
    if (!mounted) return;
    // The demand grid is read-only in the reference — drill into the
    // item's detail (the forecast row's `id` cell is the item id).
    showItemDetailDialog(context, itemId: rowId);
  }

  /// Opt into the per-row ⋮ actions menu (View item).
  @override
  bool get hasRowActions => true;

  @override
  List<GridRowAction>? gridRowActionsFor(PlutoRow row, BuildContext context) {
    final itemId = row.cells['id']?.value as int?;
    if (itemId == null || itemId <= 0) return null;
    final l10n = AppLocalizations.of(context)!;
    return [
      GridRowAction(
        icon: Icons.visibility_outlined,
        label: l10n.commonView,
        onTap: () => showItemDetailDialog(context, itemId: itemId),
      ),
    ];
  }

  @override
  PlutoRow gridRowFor(ForecastDemand f) => PlutoRow(
    cells: {
      'id': PlutoCell(value: f.itemId),
      'code': PlutoCell(value: f.itemCode),
      'name': PlutoCell(value: f.itemName),
      'category': PlutoCell(value: f.category),
      'stock': PlutoCell(value: f.currentStock),
      'week': PlutoCell(value: f.nextWeek),
      'month': PlutoCell(value: f.nextMonth),
      'quarter': PlutoCell(value: f.nextQuarter),
      'trend': PlutoCell(value: f.trend),
      'trendPct': PlutoCell(value: f.trendPercentage),
      'confidence': PlutoCell(value: f.confidence),
      'recommendation': PlutoCell(value: f.recommendation),
    },
  );

  @override
  List<PlutoColumn> buildGridColumns(AppLocalizations l10n) {
    PlutoColumn textColumn(String field, String title, double width) =>
        PlutoColumn(
          title: title,
          field: field,
          type: PlutoColumnType.text(),
          width: width,
          readOnly: true,
          enableContextMenu: false,
        );

    PlutoColumn numColumn(String field, String title, double width) =>
        PlutoColumn(
          title: title,
          field: field,
          type: PlutoColumnType.number(format: '#,###.##'),
          width: width,
          readOnly: true,
          textAlign: PlutoColumnTextAlign.end,
          titleTextAlign: PlutoColumnTextAlign.end,
          enableContextMenu: false,
        );

    return [
      PlutoColumn(
        title: '',
        field: 'id',
        type: PlutoColumnType.number(),
        width: 80,
        readOnly: true,
        renderer: (ctx) => const SizedBox.shrink(),
        enableContextMenu: false,
        enableFilterMenuItem: false,
        enableHideColumnMenuItem: false,
        enableSetColumnsMenuItem: false,
      ),
      textColumn('code', l10n.inventoryItemcode, 110),
      textColumn('name', l10n.inventoryItemname, 220),
      textColumn('category', l10n.forecastsCategory, 120),
      numColumn('stock', l10n.commonStock, 90),
      numColumn('week', l10n.forecastsPredictedweek, 120),
      numColumn('month', l10n.forecastsPredictedmonth, 130),
      numColumn('quarter', l10n.forecastsPredictedquarter, 130),
      PlutoColumn(
        title: l10n.forecastsTrendlabel,
        field: 'trend',
        type: PlutoColumnType.text(),
        width: 110,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) => Builder(
          builder: (cellContext) {
            final trend = ctx.cell.value as String? ?? '';
            final pct = (ctx.row.cells['trendPct']?.value as num?) ?? 0;
            final (color, icon) = switch (trend) {
              'growing' => (const Color(0xFF16A34A), Icons.trending_up),
              'declining' => (const Color(0xFFDC2626), Icons.trending_down),
              _ => (const Color(0xFF6B7280), Icons.remove),
            };
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 4),
                Text(
                  trend == 'stable' ? '0%' : '${pct.toStringAsFixed(0)}%',
                  style: TextStyle(color: color, fontWeight: FontWeight.w600),
                ),
              ],
            );
          },
        ),
      ),
      PlutoColumn(
        title: l10n.forecastsConfidence,
        field: 'confidence',
        type: PlutoColumnType.number(),
        width: 110,
        readOnly: true,
        textAlign: PlutoColumnTextAlign.end,
        titleTextAlign: PlutoColumnTextAlign.end,
        enableContextMenu: false,
        renderer: (ctx) => Builder(
          builder: (cellContext) {
            final scheme = Theme.of(cellContext).colorScheme;
            final value = (ctx.cell.value as num?) ?? 0;
            final color = value >= 80
                ? const Color(0xFF22C55E)
                : value >= 60
                ? const Color(0xFFEAB308)
                : const Color(0xFFEF4444);
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 44,
                  height: 6,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: (value / 100).clamp(0.0, 1.0),
                      backgroundColor: scheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                // Flexible so the cell text never overflows PlutoGrid's
                // narrow cell padding on tight columns.
                Flexible(
                  child: Text(
                    '${value.toStringAsFixed(0)}%',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: color, fontSize: 12),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      PlutoColumn(
        title: l10n.forecastsRecommendation,
        field: 'recommendation',
        type: PlutoColumnType.text(),
        width: 130,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) => Builder(
          builder: (cellContext) {
            final rec = ctx.cell.value as String? ?? '';
            final (color, label) = _recommendationOf(cellContext, rec);
            return Align(
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            );
          },
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final forecasts = ref.watch(forecastDemandProvider);
    final l10n = AppLocalizations.of(context)!;
    final filters = ref.watch(forecastDemandFiltersProvider);

    watchGridProvider(forecastDemandProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = constraints.maxWidth < 768;
        final page = forecasts.valueOrNull;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _filterBar(l10n, filters, mobile),
            ),
            Expanded(
              child: mobile
                  ? _mobileList(l10n)
                  : gridScreenBody(forecasts, provider: forecastDemandProvider),
            ),
            if (!mobile && page != null)
              ServerPaginationBar(
                page: page.currentPage,
                totalPages: page.totalPages,
                totalItems: page.totalItems,
                hasNext: page.hasNext,
                hasPrev: page.hasPrev,
                limit: ref.watch(forecastDemandLimitProvider),
                itemLabel: l10n.forecastsDemand,
                onPageChanged: (p) =>
                    ref.read(forecastDemandPageProvider.notifier).state = p,
                onLimitChanged: (limit) {
                  ref.read(forecastDemandLimitProvider.notifier).state = limit;
                  if (ref.read(forecastDemandPageProvider) != 1) {
                    ref.read(forecastDemandPageProvider.notifier).state = 1;
                  }
                },
              ),
            if (!mobile) const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  /// Category / trend / recommendation filter row + search. Category
  /// options come from the items list (the reference derives them the
  /// same way); all three are searchable selects with "All …" as the
  /// null option.
  Widget _filterBar(
    AppLocalizations l10n,
    ForecastDemandFilters filters,
    bool mobile,
  ) {
    final categories =
        ref.watch(allItemsProvider).valueOrNull
            ?.map((item) => item.category ?? '')
            .where((c) => c.isNotEmpty)
            .toSet()
            .toList()
            .cast<String?>() ??
        const <String?>[];

    // Stack the filters on narrow panes instead of overflowing — the
    // desktop Row is only built when it will actually be rendered.
    if (mobile) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          SizedBox(
            width: 180,
            height: 40,
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                isDense: true,
                hintText: l10n.commonSearch,
                prefixIcon: const Icon(Icons.search, size: 18),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          _categorySelect(l10n, filters, categories, width: 180),
          _trendSelect(l10n, filters, width: 150),
          _statusSelect(l10n, filters, width: 150),
          if (filters.hasFilters) _resetButton(l10n),
          IconButton(
            tooltip: l10n.commonRefresh,
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(forecastDemandProvider),
          ),
        ],
      );
    }

    return Row(
      children: [
        SizedBox(
          width: 180,
          height: 40,
          child: TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              isDense: true,
              hintText: l10n.commonSearch,
              prefixIcon: const Icon(Icons.search, size: 18),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _categorySelect(l10n, filters, categories),
        const SizedBox(width: 8),
        _trendSelect(l10n, filters),
        const SizedBox(width: 8),
        _statusSelect(l10n, filters),
        const SizedBox(width: 8),
        if (filters.hasFilters) _resetButton(l10n),
        const Spacer(),
        IconButton(
          tooltip: l10n.commonRefresh,
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.invalidate(forecastDemandProvider),
        ),
      ],
    );
  }

  /// "Reset" — clears all three demand filters back to "All …". Only
  /// rendered while a filter is active.
  Widget _resetButton(AppLocalizations l10n) {
    return IconButton(
      key: const ValueKey('forecast-reset-filters'),
      tooltip: l10n.commonReset,
      icon: const Icon(Icons.filter_alt_off_outlined),
      onPressed: () => _updateFilters(const ForecastDemandFilters()),
    );
  }

  Widget _categorySelect(
    AppLocalizations l10n,
    ForecastDemandFilters filters,
    List<String?> categories, {
    double width = 160,
  }) {
    return SizedBox(
      width: width,
      height: 40,
      child: SearchableSelect<String?>(
        key: const ValueKey('forecast-category-filter'),
        items: [null, ...categories],
        selected: filters.category,
        hint: l10n.forecastsAllcategories,
        labelBuilder: (v) => v ?? l10n.forecastsAllcategories,
        isDense: true,
        onChanged: (v) => _updateFilters(
          ForecastDemandFilters(category: v, trend: filters.trend, recommendation: filters.recommendation),
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  Widget _trendSelect(
    AppLocalizations l10n,
    ForecastDemandFilters filters, {
    double width = 160,
  }) {
    return SizedBox(
      width: width,
      height: 40,
      child: SearchableSelect<String?>(
        key: const ValueKey('forecast-trend-filter'),
        items: const [null, 'growing', 'stable', 'declining'],
        selected: filters.trend,
        hint: l10n.forecastsAlltrends,
        labelBuilder: (v) => switch (v) {
          'growing' => l10n.forecastsGrowing,
          'declining' => l10n.forecastsDeclining,
          'stable' => l10n.forecastsStable,
          _ => l10n.forecastsAlltrends,
        },
        isDense: true,
        onChanged: (v) => _updateFilters(
          ForecastDemandFilters(category: filters.category, trend: v, recommendation: filters.recommendation),
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  Widget _statusSelect(
    AppLocalizations l10n,
    ForecastDemandFilters filters, {
    double width = 160,
  }) {
    return SizedBox(
      width: width,
      height: 40,
      child: SearchableSelect<String?>(
        key: const ValueKey('forecast-status-filter'),
        items: const [null, 'order_now', 'order_soon', 'monitor', 'adequate'],
        selected: filters.recommendation,
        hint: l10n.forecastsAllstatus,
        labelBuilder: (v) => switch (v) {
          'order_now' => l10n.forecastsOrdernow,
          'order_soon' => l10n.forecastsOrdersoon,
          'monitor' => l10n.forecastsMonitor,
          'adequate' => l10n.forecastsAdequate,
          _ => l10n.forecastsAllstatus,
        },
        isDense: true,
        onChanged: (v) => _updateFilters(
          ForecastDemandFilters(category: filters.category, trend: filters.trend, recommendation: v),
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  void _updateFilters(ForecastDemandFilters next) {
    ref.read(forecastDemandFiltersProvider.notifier).state = next;
    // A filter change starts back at page 1.
    if (ref.read(forecastDemandPageProvider) != 1) {
      ref.read(forecastDemandPageProvider.notifier).state = 1;
    }
  }

  /// Compact cards under 768px (reference `CompactForecastCard`): name +
  /// code header, stock (tinted by stock/next-month ratio), predicted
  /// month, confidence, recommendation badge + category footer. Uses the
  /// full filtered list (the paged grid is desktop-only).
  Widget _mobileList(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final forecasts = ref.watch(filteredForecastDemandProvider);
    return forecasts.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Text(
          l10n.forecastsLoaderror,
          style: TextStyle(color: scheme.error),
        ),
      ),
      data: (rows) => rows.isEmpty
          ? Center(
              child: Text(
                l10n.forecastsNoforecasts,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) =>
                  _CompactForecastCard(item: rows[i], l10n: l10n),
            ),
    );
  }
}

class _CompactForecastCard extends StatelessWidget {
  const _CompactForecastCard({required this.item, required this.l10n});

  final ForecastDemand item;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final trend = item.trend;
    final trendColor = switch (trend) {
      'growing' => const Color(0xFF16A34A),
      'declining' => const Color(0xFFDC2626),
      _ => const Color(0xFF6B7280),
    };
    final trendIcon = switch (trend) {
      'growing' => Icons.trending_up,
      'declining' => Icons.trending_down,
      _ => Icons.remove,
    };

    final ratio = item.nextMonth > 0
        ? item.currentStock / item.nextMonth
        : 1.0;
    final stockColor = ratio < 0.3
        ? const Color(0xFFDC2626)
        : ratio < 0.5
        ? const Color(0xFFD97706)
        : const Color(0xFF16A34A);

    final (recColor, recLabel) = _recommendationOf(context, item.recommendation);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.itemName,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        item.itemCode,
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(trendIcon, size: 16, color: trendColor),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _cardStat(
                  context,
                  l10n.commonStock,
                  Formatters.number(item.currentStock),
                  stockColor,
                ),
                _cardStat(
                  context,
                  l10n.forecastsPredictedmonth,
                  Formatters.number(item.nextMonth),
                  null,
                ),
                _cardStat(
                  context,
                  l10n.forecastsConfidence,
                  '${item.confidence.toStringAsFixed(0)}%',
                  null,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: recColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    recLabel,
                    style: textTheme.labelSmall?.copyWith(
                      color: recColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  item.category,
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardStat(
    BuildContext context,
    String label,
    String value,
    Color? valueColor,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Recommendation → (color, label) shared by the grid cell, badge and
/// compact card (reference `RecommendationCellRenderer` + `compact-rec-badge`).
(Color, String) _recommendationOf(
  BuildContext context,
  String recommendation,
) {
  final l10n = AppLocalizations.of(context)!;
  return switch (recommendation) {
    'order_now' => (const Color(0xFFDC2626), l10n.forecastsOrdernow),
    'order_soon' => (const Color(0xFFD97706), l10n.forecastsOrdersoon),
    'adequate' => (const Color(0xFF16A34A), l10n.forecastsAdequate),
    _ => (const Color(0xFF6B7280), l10n.forecastsMonitor),
  };
}
