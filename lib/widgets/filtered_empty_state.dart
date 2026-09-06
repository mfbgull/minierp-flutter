// Filtered-empty state — shown by date-ranged tabs when an ACTIVE range
// yields zero rows, distinct from the per-module true-no-data messages
// (unified-detail-date-picker-spec §10.1 / D11). Rendered centered like
// the existing empty states it replaces under a range.
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

class FilteredEmptyState extends StatelessWidget {
  const FilteredEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.commonNoRecordsInPeriod,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.commonNoRecordsInPeriodHint,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}