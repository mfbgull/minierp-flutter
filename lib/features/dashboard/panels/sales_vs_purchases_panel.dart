// Sales versus purchases panel — daily bar chart of the two series over the
// last seven days.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../data/models/dashboard_summary.dart' show DayTotal;
import '../../../l10n/app_localizations.dart';

/// Simple bar chart: sales vs purchases totals per day over the last week.
class SalesVsPurchasesPanel extends StatelessWidget {
  const SalesVsPurchasesPanel({
    super.key,
    required this.sales,
    required this.purchases,
  });

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
