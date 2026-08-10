// Forecast trends screen (PORTING.md §12) — mirrors `ForecastTrends.tsx`:
// an item searchable-select (finished goods only) feeding
// `GET /forecasts/trends?itemId=`, a monthly line chart (actual sales,
// 3-month moving average, forecast) and a horizontal volume bar chart of
// the top-10 items, plus the item-breakdown table with trend badges.
// Charts are fl_chart equivalents of the reference's Chart.js Line/Bar.

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/screen_error_panel.dart';
import '../../widgets/searchable_select.dart';
import '../inventory/inventory_providers.dart' show itemsProvider;
import 'forecast_models.dart';
import 'forecast_providers.dart';

class ForecastTrendsScreen extends ConsumerStatefulWidget {
  const ForecastTrendsScreen({super.key});

  @override
  ConsumerState<ForecastTrendsScreen> createState() =>
      _ForecastTrendsScreenState();
}

class _ForecastTrendsScreenState extends ConsumerState<ForecastTrendsScreen> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final trends = ref.watch(forecastTrendsProvider);
    final items = ref.watch(itemsProvider).valueOrNull ?? const [];
    final selectedItem = ref.watch(forecastTrendsItemProvider);

    // Finished goods only (reference: `is_finished_good === 1/true`).
    final finishedGoods = [
      for (final item in items)
        if (item.isFinishedGood) item,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.forecastsForecasttrends,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(
                width: 240,
                height: 40,
                child: SearchableSelect<int?>(
                  key: const ValueKey('forecast-trends-item-filter'),
                  items: [null, for (final item in finishedGoods) item.id],
                  selected: selectedItem,
                  hint: l10n.forecastsSelectitem,
                  labelBuilder: (id) {
                    if (id == null) return l10n.forecastsSelectitem;
                    for (final item in finishedGoods) {
                      if (item.id == id) return item.itemName;
                    }
                    return '$id';
                  },
                  isDense: true,
                  onChanged: (id) =>
                      ref.read(forecastTrendsItemProvider.notifier).state = id,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: l10n.commonRefresh,
                icon: const Icon(Icons.refresh),
                onPressed: () => ref.invalidate(forecastTrendsProvider),
              ),
            ],
          ),
        ),
        Expanded(
          child: trends.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => ScreenErrorPanel(
              message: error is ApiError ? error.message : l10n.forecastsLoaderror,
              onRetry: () => ref.invalidate(forecastTrendsProvider),
            ),
            data: (data) => _TrendsBody(data: data),
          ),
        ),
      ],
    );
  }
}

class _TrendsBody extends StatelessWidget {
  const _TrendsBody({required this.data});

  final ForecastTrendData data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    if (data.historicalTrends.isEmpty && data.itemBreakdown.isEmpty) {
      return Center(
        child: Text(
          l10n.forecastsNotrenddata,
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Charts side by side on wide panes, stacked on narrow ones.
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              final chart = _ChartCard(
                title: l10n.forecastsMonthlytrend,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 260,
                      child: _MonthlyTrendChart(months: data.historicalTrends),
                    ),
                    const SizedBox(height: 8),
                    _ChartLegend(
                      entries: [
                        (l10n.forecastsActualsales, const Color(0xFF3B82F6), false),
                        (l10n.forecastsTrendline, const Color(0xFF8B5CF6), true),
                        (l10n.forecastsForecast, const Color(0xFF10B981), true),
                      ],
                    ),
                  ],
                ),
              );
              final bars = _ChartCard(
                title: l10n.forecastsTopitemsbyvolume,
                child: SizedBox(
                  height: 300,
                  child: _VolumeBarChart(
                    items: data.itemBreakdown.take(10).toList(),
                  ),
                ),
              );
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: chart),
                    const SizedBox(width: 12),
                    Expanded(child: bars),
                  ],
                );
              }
              return Column(
                children: [
                  chart,
                  const SizedBox(height: 12),
                  bars,
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          // ── Breakdown table ───────────────────────────────────────
          Text(
            l10n.forecastsItembreakdown,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStatePropertyAll(
                  scheme.surfaceContainerHighest,
                ),
                columns: [
                  DataColumn(label: Text(l10n.commonItem)),
                  DataColumn(
                    numeric: true,
                    label: Text(l10n.forecastsTotalsold12mo),
                  ),
                  DataColumn(label: Text(l10n.forecastsTrendlabel)),
                ],
                rows: [
                  for (final item in data.itemBreakdown)
                    DataRow(
                      cells: [
                        DataCell(
                          Text(item.itemName, style: const TextStyle(fontSize: 13)),
                        ),
                        DataCell(
                          Text(
                            Formatters.number(item.totalSold),
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
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
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
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

/// Dashed/solid 14×3 swatch for the chart legend.
class _LegendSwatchPainter extends CustomPainter {
  const _LegendSwatchPainter({required this.color, required this.dashed});

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    if (dashed) {
      const dash = 3.0;
      const gap = 2.0;
      var x = 0.0;
      while (x < size.width) {
        canvas.drawLine(
          Offset(x, size.height / 2),
          Offset((x + dash).clamp(0, size.width), size.height / 2),
          paint,
        );
        x += dash + gap;
      }
    } else {
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_LegendSwatchPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.dashed != dashed;
}

/// Compact legend row for the line chart (reference Chart.js legend).
class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.entries});

  final List<(String, Color, bool)> entries;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      children: [
        for (final (label, color, dashed) in entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Dashed series (moving average / forecast) get a dashed
              // swatch, mirroring the chart's line styles.
              CustomPaint(
                size: const Size(14, 3),
                painter: _LegendSwatchPainter(color: color, dashed: dashed),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// fl_chart line chart of actual / 3-month moving average / forecast
/// (reference `LineChartData` — dashed trend line, forecast dotted).
class _MonthlyTrendChart extends StatelessWidget {
  const _MonthlyTrendChart({required this.months});

  final List<TrendMonth> months;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const actualColor = Color(0xFF3B82F6);
    const movingColor = Color(0xFF8B5CF6);
    const forecastColor = Color(0xFF10B981);

    final actual = <double?>[];
    final moving = <double?>[];
    final forecast = <double?>[];
    for (final m in months) {
      actual.add(m.actual);
      moving.add(m.movingAvg);
      forecast.add(m.predicted);
    }
    // Y-range: min/max across all series, padded 10% (the reference
    // Chart.js autoscales the same way). A degenerate all-equal / all-null
    // series is floored to a 1-unit range so fl_chart never gets a
    // zero-height axis.
    final all = [...actual, ...moving, ...forecast].whereType<double>();
    var maxY = all.fold<double>(0, (a, b) => a > b ? a : b);
    var minY = all.fold<double>(0, (a, b) => a < b ? a : b);
    if (maxY - minY < 1) {
      maxY = maxY + 1;
      minY = math.max(0, minY - 1);
    }

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (months.length - 1).clamp(0, 1e9).toDouble(),
        minY: minY - (maxY - minY) * 0.1,
        maxY: maxY + (maxY - minY) * 0.1,
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final i = value.round();
                if (i < 0 || i >= months.length) return const SizedBox.shrink();
                final label = months[i].month;
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    label.length > 4 ? label.substring(0, 4) : label,
                    style: const TextStyle(fontSize: 10),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) => Text(
                Formatters.number(value),
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ),
        ),
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) => [
              for (final spot in touchedSpots)
                LineTooltipItem(
                  '${months[spot.x.round()].month}: '
                  '${Formatters.number(spot.y)}',
                  const TextStyle(color: Colors.white, fontSize: 12),
                ),
            ],
          ),
        ),
        lineBarsData: [
          // Actual (solid blue)
          LineChartBarData(
            spots: [
              for (var i = 0; i < months.length; i++)
                if (actual[i] != null) FlSpot(i.toDouble(), actual[i]!),
            ],
            color: actualColor,
            barWidth: 2,
            isCurved: false,
            dotData: const FlDotData(show: true),
          ),
          // 3-month moving average (dashed purple)
          LineChartBarData(
            spots: [
              for (var i = 0; i < months.length; i++)
                if (moving[i] != null) FlSpot(i.toDouble(), moving[i]!),
            ],
            color: movingColor,
            barWidth: 2,
            isCurved: false,
            dotData: const FlDotData(show: false),
            dashArray: [5, 4],
          ),
          // Forecast (dotted green)
          LineChartBarData(
            spots: [
              for (var i = 0; i < months.length; i++)
                if (forecast[i] != null) FlSpot(i.toDouble(), forecast[i]!),
            ],
            color: forecastColor,
            barWidth: 2,
            isCurved: false,
            dotData: const FlDotData(show: true),
            dashArray: [8, 4],
          ),
        ],
      ),
    );
  }
}

/// Horizontal bar chart of the top-10 items by volume (reference Bar
/// with `indexAxis: 'y'`).
class _VolumeBarChart extends StatelessWidget {
  const _VolumeBarChart({required this.items});

  final List<BreakdownItem> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const color = Color(0xFF3B82F6);

    // Floor to a 1-unit scale when empty/all-zero so fl_chart's bar axis
    // stays valid (the reference skips the chart when no breakdown rows).
    final maxVal = math.max(
      1.0,
      items.fold<double>(0, (a, b) => b.totalSold > a ? b.totalSold : a),
    );

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxVal * 1.1,
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (value, meta) => Text(
                Formatters.number(value),
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 110,
              getTitlesWidget: (value, meta) {
                final i = value.round();
                if (i < 0 || i >= items.length) return const SizedBox.shrink();
                final name = items[i].itemName;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      name.length > 14 ? '${name.substring(0, 13)}…' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                BarTooltipItem(
                  '${items[groupIndex].itemName}: '
                  '${Formatters.number(rod.toY)}',
                  const TextStyle(color: Colors.white, fontSize: 12),
                ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < items.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: items[i].totalSold,
                  color: color,
                  width: 14,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _TrendBadge extends StatelessWidget {
  const _TrendBadge({required this.trend});

  final String trend;

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
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
        ),
      ],
    );
  }
}
