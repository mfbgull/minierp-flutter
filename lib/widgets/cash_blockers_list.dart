// ACCT-013 — the cash guard refuses a void or edit that would make a cash or
// bank day negative. The 409 carries the journal lines landing on the first
// deficit date, so the user can see what to reverse first. The server sends
// them under `details`; [ApiError.cashBlockers] parses them.
//
// A long list is truncated: the point is to identify the earliest blockers,
// and a wall of rows in a dialog helps nobody. The remainder is counted.

import 'package:flutter/material.dart';

import '../core/utils/formatters.dart';
import '../data/repositories/api_result.dart';
import '../l10n/app_localizations.dart';

/// How many blocker rows to show before collapsing into "and N more".
const int kCashBlockerPreviewCount = 5;

class CashBlockersList extends StatelessWidget {
  const CashBlockersList({
    super.key,
    required this.blockers,
    this.previewCount = kCashBlockerPreviewCount,
  });

  final List<CashBlocker> blockers;
  final int previewCount;

  @override
  Widget build(BuildContext context) {
    if (blockers.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final shown = blockers.take(previewCount).toList();
    final hidden = blockers.length - shown.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.refundBlockedTitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.refundBlockedHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        for (final blocker in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              l10n.refundBlockedRow(
                blocker.type,
                blocker.date,
                Formatters.currency(blocker.amount),
              ),
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (hidden > 0)
          Text(
            l10n.refundBlockedMore(hidden),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
