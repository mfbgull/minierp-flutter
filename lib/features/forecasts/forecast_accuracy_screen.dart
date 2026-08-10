// Forecast accuracy screen (PORTING.md §12) — mirrors
// `ForecastAccuracy.tsx`: four stat cards (avg MAPE / items tracked /
// best model / avg MAE), a searchable + sortable per-item accuracy table
// (clicking a row selects it for the trend chart), the "Compute Accuracy"
// action (`POST /forecasts/compute-accuracy`, backfills actuals and
// re-runs the accuracy provider) and a MAPE/MAE line chart for the
// selected item from `GET /forecasts/accuracy/:itemId`.

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/api_result.dart'
    show ApiError, ApiFailure, ApiSuccess;
import '../../l10n/app_localizations.dart';
import '../../widgets/screen_error_panel.dart';
import 'forecast_models.dart';
import 'forecast_providers.dart';
import 'forecast_repository.dart' show forecastRepositoryProvider;

class ForecastAccuracyScreen extends ConsumerStatefulWidget {
  const ForecastAccuracyScreen({super.key});

  @override
  ConsumerState<ForecastAccuracyScreen> createState() =>
      _ForecastAccuracyScreenState();
}

class _ForecastAccuracyScreenState
    extends ConsumerState<ForecastAccuracyScreen> {
  String _search = '';
  String _sortField = 'mape';
  bool _sortAsc = true;
  bool _computing = false;
  String? _successMessage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final accuracy = ref.watch(forecastAccuracyProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(l10n),
              // Reference compute-success banner (auto-hides after 5s).
              if (_successMessage != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        size: 18,
                        color: Color(0xFF16A34A),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _successMessage!,
                          style: const TextStyle(
                            color: Color(0xFF166534),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: accuracy.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => ScreenErrorPanel(
              message: error is ApiError ? error.message : l10n.forecastsLoaderror,
              onRetry: () => ref.invalidate(forecastAccuracyProvider),
            ),
            data: (rows) => _AccuracyBody(
              rows: rows,
              search: _search,
              sortField: _sortField,
              sortAsc: _sortAsc,
              selectedItemId: ref.watch(forecastAccuracyItemProvider),
              onSearch: (v) => setState(() => _search = v),
              onSort: _onSort,
              onSelectItem: (id) =>
                  ref.read(forecastAccuracyItemProvider.notifier).state = id,
            ),
          ),
        ),
      ],
    );
  }

  Widget _header(AppLocalizations l10n) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.forecastsAccuracytitle,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                l10n.forecastsAccuracysubtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        FilledButton.icon(
          onPressed: _computing ? null : _computeAccuracy,
          icon: _computing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.calculate_outlined, size: 18),
          label: Text(
            _computing ? l10n.forecastsComputing : l10n.forecastsComputeaccuracy,
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: l10n.commonRefresh,
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.invalidate(forecastAccuracyProvider),
        ),
      ],
    );
  }

  /// POST /forecasts/compute-accuracy; on success invalidate the accuracy
  /// provider and surface the server's message (reference shows it as an
  /// inline success banner for 5s).
  Future<void> _computeAccuracy() async {
    setState(() {
      _computing = true;
      _successMessage = null;
    });
    final result = await ref
        .read(forecastRepositoryProvider)
        .computeAccuracy();
    if (!mounted) return;
    setState(() {
      _computing = false;
      _successMessage = switch (result) {
        // Localized success banner (the Urdu locale gets its own string
        // instead of the server's English-only `message`).
        ApiSuccess(:final data) =>
          AppLocalizations.of(
            context,
          )!.forecastsAccuracycomputed(data.$2.computed),
        ApiFailure() => null,
      };
    });
    if (result case ApiSuccess()) {
      ref.invalidate(forecastAccuracyProvider);
    }
    if (result case ApiFailure()) {
      if (mounted) {
        final failureL10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(failureL10n.forecastsLoaderror)),
        );
      }
    }
    // Auto-hide the banner like the reference.
    await Future<void>.delayed(const Duration(seconds: 5));
    if (mounted && _successMessage != null) {
      setState(() => _successMessage = null);
    }
  }

  void _onSort(String field) {
    setState(() {
      if (_sortField == field) {
        _sortAsc = !_sortAsc;
      } else {
        _sortField = field;
        _sortAsc = true;
      }
    });
  }
}

class _AccuracyBody extends StatelessWidget {
  const _AccuracyBody({
    required this.rows,
    required this.search,
    required this.sortField,
    required this.sortAsc,
    required this.selectedItemId,
    required this.onSearch,
    required this.onSort,
    required this.onSelectItem,
  });

  final List<ItemAccuracy> rows;
  final String search;
  final String sortField;
  final bool sortAsc;
  final int? selectedItemId;
  final ValueChanged<String> onSearch;
  final ValueChanged<String> onSort;
  final ValueChanged<int> onSelectItem;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    // Summary stats (reference `summary` useMemo).
    final withData = rows.where((r) => r.mape != null).length;
    final avgMape = withData > 0
        ? rows.where((r) => r.mape != null).fold<double>(0, (s, r) => s + r.mape!) /
              withData
        : null;
    final withMae = rows.where((r) => r.mae != null).length;
    final avgMae = withMae > 0
        ? rows.where((r) => r.mae != null).fold<double>(0, (s, r) => s + r.mae!) /
              withMae
        : null;
    final modelCounts = <String, int>{};
    for (final r in rows) {
      final m = (r.modelType?.isNotEmpty ?? false) ? r.modelType! : 'unknown';
      modelCounts[m] = (modelCounts[m] ?? 0) + 1;
    }
    String? bestModel;
    var bestCount = 0;
    modelCounts.forEach((m, c) {
      if (c > bestCount) {
        bestCount = c;
        bestModel = m;
      }
    });

    // Filtered + sorted rows (reference `sortedItems` useMemo).
    final filtered = [
      for (final r in rows)
        if (search.isEmpty ||
            r.itemName.toLowerCase().contains(search.toLowerCase()) ||
            r.itemCode.toLowerCase().contains(search.toLowerCase()))
          r,
    ];
    // `mape` is the default sort (best first) — the reference's server
    // ordering. Nulls sort last regardless of direction.
    Object? fieldOf(ItemAccuracy r) => switch (sortField) {
      'itemName' => r.itemName,
      'mae' => r.mae,
      'smape' => r.smape,
      'sampleSize' => r.sampleSize,
      'trend' => r.trend,
      _ => r.mape,
    };
    filtered.sort((a, b) {
      final av = fieldOf(a);
      final bv = fieldOf(b);
      if (av == null && bv == null) return 0;
      if (av == null) return 1;
      if (bv == null) return -1;
      final cmp = av is String
          ? av.compareTo(bv as String)
          : (av as num).compareTo(bv as num);
      return sortAsc ? cmp : -cmp;
    });

    final selectedItemId = this.selectedItemId;
    final selectedLabel = () {
      if (selectedItemId == null) return null;
      for (final r in rows) {
        if (r.itemId == selectedItemId) {
          return '${r.itemName} (${r.itemCode})';
        }
      }
      return null;
    }();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Stat cards ───────────────────────────────────────────
          LayoutBuilder(
            builder: (context, constraints) {
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
                    icon: Icons.workspace_premium_outlined,
                    label: l10n.forecastsAvgmape,
                    value: avgMape != null ? '${avgMape.toStringAsFixed(1)}%' : '—',
                  ),
                  _StatCard(
                    width: cardWidth,
                    icon: Icons.bar_chart_outlined,
                    label: l10n.forecastsItemswithaccuracy,
                    value: '$withData / ${rows.length}',
                  ),
                  _StatCard(
                    width: cardWidth,
                    icon: Icons.smart_toy_outlined,
                    label: l10n.forecastsBestmodel,
                    value: bestModel != null
                        ? bestModel!.replaceAll('_', ' ')
                        : '—',
                  ),
                  _StatCard(
                    width: cardWidth,
                    icon: Icons.check_circle_outline,
                    label: l10n.forecastsAvgmae,
                    value: avgMae != null ? avgMae.toStringAsFixed(1) : '—',
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          // ── Accuracy table ───────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.forecastsForecasts,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              SizedBox(
                width: 220,
                height: 40,
                child: TextField(
                  onChanged: onSearch,
                  decoration: InputDecoration(
                    hintText: l10n.forecastsSearchitems,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  l10n.forecastsNoaccuracydata,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            )
          else
            Card(
              margin: EdgeInsets.zero,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStatePropertyAll(
                    scheme.surfaceContainerHighest,
                  ),
                  sortColumnIndex: _sortIndex(sortField),
                  sortAscending: sortAsc,
                  columns: [
                    _sortableColumn(
                      l10n.commonItem,
                      'itemName',
                      sortField,
                      sortAsc,
                      onSort,
                    ),
                    DataColumn(label: Text(l10n.inventoryItemcode)),
                    _sortableColumn(
                      l10n.forecastsMapelabel,
                      'mape',
                      sortField,
                      sortAsc,
                      onSort,
                    ),
                    _sortableColumn(
                      l10n.forecastsMaelabel,
                      'mae',
                      sortField,
                      sortAsc,
                      onSort,
                    ),
                    _sortableColumn(
                      l10n.forecastsSmapelabel,
                      'smape',
                      sortField,
                      sortAsc,
                      onSort,
                    ),
                    _sortableColumn(
                      l10n.forecastsSamples,
                      'sampleSize',
                      sortField,
                      sortAsc,
                      onSort,
                    ),
                    DataColumn(label: Text(l10n.forecastsModel)),
                    _sortableColumn(
                      l10n.forecastsTrendlabel,
                      'trend',
                      sortField,
                      sortAsc,
                      onSort,
                    ),
                  ],
                  rows: [
                    for (final item in filtered)
                      DataRow(
                        selected: selectedItemId == item.itemId,
                        onSelectChanged: (_) => onSelectItem(item.itemId),
                        cells: [
                          DataCell(
                            Text(
                              item.itemName,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              item.itemCode,
                              style: TextStyle(
                                fontSize: 13,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          DataCell(_MapeCell(value: item.mape)),
                          DataCell(
                            Text(
                              item.mae != null
                                  ? item.mae!.toStringAsFixed(1)
                                  : '—',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          DataCell(
                            Text(
                              item.smape != null
                                  ? '${item.smape!.toStringAsFixed(1)}%'
                                  : '—',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          DataCell(
                            Text(
                              '${item.sampleSize}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          DataCell(
                            Text(
                              item.modelType?.replaceAll('_', ' ') ?? '—',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          DataCell(_TrendBadge(trend: item.trend)),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 20),
          // ── Trend chart ──────────────────────────────────────────
          _AccuracyTrendChart(
            selectedItemId: selectedItemId,
            selectedLabel: selectedLabel,
          ),
        ],
      ),
    );
  }

  int? _sortIndex(String field) => switch (field) {
    'itemName' => 0,
    'mape' => 2,
    'mae' => 3,
    'smape' => 4,
    'sampleSize' => 5,
    'trend' => 7,
    _ => null,
  };

  DataColumn _sortableColumn(
    String label,
    String field,
    String sortField,
    bool sortAsc,
    ValueChanged<String> onSort,
  ) =>
      DataColumn(
        label: Text(label),
        onSort: (_, _) => onSort(field),
      );
}

class _MapeCell extends StatelessWidget {
  const _MapeCell({required this.value});

  final double? value;

  @override
  Widget build(BuildContext context) {
    if (value == null) {
      return const Text('—', style: TextStyle(fontSize: 13));
    }
    // Reference `getMapeClass`: <15 good, <30 fair, else poor.
    final color = value! < 15
        ? const Color(0xFF16A34A)
        : value! < 30
        ? const Color(0xFFD97706)
        : const Color(0xFFDC2626);
    return Text(
      '${value!.toStringAsFixed(1)}%',
      style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600),
    );
  }
}

class _TrendBadge extends StatelessWidget {
  const _TrendBadge({required this.trend});

  final String? trend;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final (color, icon, label) = switch (trend) {
      'growing' => (
        const Color(0xFF16A34A),
        Icons.trending_up,
        l10n.forecastsGrowing,
      ),
      'declining' => (
        const Color(0xFFDC2626),
        Icons.trending_down,
        l10n.forecastsDeclining,
      ),
      _ => (const Color(0xFF6B7280), Icons.remove, l10n.forecastsStable),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 11),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
  });

  final double width;
  final IconData icon;
  final String label;
  final String value;

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
                  Icon(icon, size: 18, color: scheme.primary),
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
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The per-item MAPE/MAE line chart (reference `AccuracyTrend`). When no
/// item is selected it shows the reference's placeholder prompt.
class _AccuracyTrendChart extends ConsumerWidget {
  const _AccuracyTrendChart({required this.selectedItemId, required this.selectedLabel});

  final int? selectedItemId;
  final String? selectedLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    final title = selectedItemId != null
        ? '${l10n.forecastsAccuracytrend}: $selectedLabel'
        : l10n.forecastsAccuracytrend;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              selectedItemId != null
                  ? l10n.forecastsAccuracytrenddesc
                  : l10n.forecastsSelectitemforchart,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (selectedItemId == null)
              SizedBox(
                height: 160,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.show_chart_outlined,
                        size: 36,
                        color: scheme.outline,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.forecastsSelectitemforchart,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              )
            else
              ref
                  .watch(forecastAccuracyDetailProvider(selectedItemId!))
                  .when(
                    loading: () => const SizedBox(
                      height: 200,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (error, _) => SizedBox(
                      height: 200,
                      child: Center(
                        child: Text(
                          l10n.forecastsLoaderror,
                          style: TextStyle(color: scheme.error),
                        ),
                      ),
                    ),
                    data: (points) => points.isEmpty
                        ? SizedBox(
                            height: 200,
                            child: Center(
                              child: Text(
                                l10n.forecastsNoaccuracydata,
                                style: TextStyle(color: scheme.onSurfaceVariant),
                              ),
                            ),
                          )
                        : SizedBox(
                            height: 260,
                            child: _AccuracyLineChart(points: points),
                          ),
                  ),
          ],
        ),
      ),
    );
  }
}

class _AccuracyLineChart extends StatelessWidget {
  const _AccuracyLineChart({required this.points});

  final List<AccuracyDataPoint> points;

  @override
  Widget build(BuildContext context) {
    const mapeColor = Color(0xFF3B82F6);
    const maeColor = Color(0xFF8B5CF6);

    final mapeSpots = <FlSpot>[
      for (var i = 0; i < points.length; i++)
        if (points[i].mape != null) FlSpot(i.toDouble(), points[i].mape!),
    ];
    final maeSpots = <FlSpot>[
      for (var i = 0; i < points.length; i++)
        if (points[i].mae != null) FlSpot(i.toDouble(), points[i].mae!),
    ];

    final all = [
      for (final p in points) ... [p.mape, p.mae],
    ].whereType<double>();
    // Floor the axis so an all-null series never yields a zero-height
    // fl_chart range.
    final maxY = math.max(1.0, all.fold<double>(0, (a, b) => a > b ? a : b));

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (points.length - 1).clamp(0, 1e9).toDouble(),
        minY: 0,
        maxY: maxY * 1.1,
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final i = value.round();
                if (i < 0 || i >= points.length) return const SizedBox.shrink();
                final p = points[i];
                final label = '${p.forecastDate} (${p.period.replaceAll('next_', '')})';
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    label.length > 12 ? label.substring(0, 11) : label,
                    style: const TextStyle(fontSize: 10),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (value, meta) => Text(
                '${value.toStringAsFixed(0)}%',
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ),
        ),
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) => [
              for (final spot in touchedSpots)
                LineTooltipItem(
                  '${points[spot.x.round()].forecastDate}: '
                  '${spot.y.toStringAsFixed(1)}',
                  const TextStyle(color: Colors.white, fontSize: 12),
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: mapeSpots,
            color: mapeColor,
            barWidth: 2,
            isCurved: true,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: const Color(0x1A3B82F6),
            ),
          ),
          LineChartBarData(
            spots: maeSpots,
            color: maeColor,
            barWidth: 2,
            isCurved: true,
            dotData: const FlDotData(show: true),
            dashArray: [4, 4],
          ),
        ],
      ),
    );
  }
}
