import 'package:flutter/material.dart';

import '../../core/theme/app_border_radius.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/invoice.dart' show Invoice;
import '../../l10n/app_localizations.dart';

/// Summary strip for the Sales grid — Total Sales / Total Paid / Total Due
/// computed from the *filtered* rows (extracted from sales_screen.dart,
/// spec 1.3). Always matches the active filters because it runs over the
/// full filtered list, not the paged grid.
class SalesSummaryStrip extends StatelessWidget {
  const SalesSummaryStrip({super.key, required this.rows});

  final List<Invoice> rows;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final totalSales = rows.fold<num>(0, (sum, i) => sum + i.totalAmount);
    final totalPaid = rows.fold<num>(0, (sum, i) => sum + i.paidAmount);
    final totalDue = rows.fold<num>(0, (sum, i) => sum + i.balanceAmount);

    Widget stat(String label, num value, Color color) {
      return Expanded(
        child: Row(
          children: [
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                Formatters.currency(value),
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: AppBorderRadius.smRadius,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.receipt_long_outlined, size: 18, color: scheme.primary),
          const SizedBox(width: 14),
          stat(l10n.salesTotalsales, totalSales, scheme.primary),
          stat(l10n.salesTotalpaid, totalPaid, scheme.primary),
          stat(l10n.salesTotaldue, totalDue, scheme.error),
        ],
      ),
    );
  }
}