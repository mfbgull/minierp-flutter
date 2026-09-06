import 'package:flutter/material.dart';

import '../../core/theme/app_border_radius.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/expense.dart' show Expense;
import '../../l10n/app_localizations.dart';

/// Summary strip for the Expenses grid — total amount + row count over the
/// full filtered list (extracted from expenses_screen.dart, spec 1.3).
class ExpensesSummaryStrip extends StatelessWidget {
  const ExpensesSummaryStrip({super.key, required this.rows});

  final List<Expense> rows;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final total = rows.fold<num>(0, (sum, e) => sum + e.amount);
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
          const SizedBox(width: 8),
          Text(l10n.commonTotal, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(width: 6),
          Text(
            Formatters.currency(total),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 14),
          Text(
            '${rows.length} ${l10n.expensesCount}',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}