// Shared table primitives for the ledger and statement dialogs — both
// render the same compact accounting table (Date | Description | Debit |
// Credit | Balance). Only the labels and the source data differ, so the
// column widths, header row, entry rows and totals row live here once.

import 'package:flutter/material.dart';

import '../core/utils/formatters.dart';
import '../data/models/ledger_entry.dart' show LedgerEntry;
import '../l10n/app_localizations.dart';

/// Shared column widths — keep the header, rows and totals aligned across
/// the ledger and statement tables.
const double ledgerDateWidth = 110.0;
const double ledgerAmountWidth = 92.0;
const double ledgerBalanceWidth = 104.0;

/// The Date | Description | Debit | Credit | Balance header row.
class LedgerHeaderRow extends StatelessWidget {
  const LedgerHeaderRow({
    super.key,
    required this.debitLabel,
    required this.creditLabel,
    required this.balanceLabel,
  });

  final String debitLabel;
  final String creditLabel;
  final String balanceLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
      letterSpacing: 0.3,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: ledgerDateWidth,
            child: Text(l10n.commonDate, style: style),
          ),
          Expanded(child: Text(l10n.commonDescription, style: style)),
          SizedBox(
            width: ledgerAmountWidth,
            child: Text(debitLabel, style: style, textAlign: TextAlign.end),
          ),
          SizedBox(
            width: ledgerAmountWidth,
            child: Text(creditLabel, style: style, textAlign: TextAlign.end),
          ),
          SizedBox(
            width: ledgerBalanceWidth,
            child: Text(balanceLabel, style: style, textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

/// One transaction row — date + type subtext, description + reference
/// subtext, debit/credit (dash when zero), and the running balance.
class LedgerEntryRow extends StatelessWidget {
  const LedgerEntryRow({super.key, required this.entry});

  final LedgerEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final amount = Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: ledgerDateWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Formatters.date(entry.transactionDate),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(entry.transactionType, style: muted),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.description.isEmpty ? '—' : entry.description,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (entry.referenceNo.isNotEmpty)
                  Text(entry.referenceNo, style: muted),
              ],
            ),
          ),
          SizedBox(
            width: ledgerAmountWidth,
            child: Text(
              entry.debit > 0 ? Formatters.currency(entry.debit) : '—',
              style: entry.debit > 0 ? amount : muted,
              textAlign: TextAlign.end,
            ),
          ),
          SizedBox(
            width: ledgerAmountWidth,
            child: Text(
              entry.credit > 0 ? Formatters.currency(entry.credit) : '—',
              style: entry.credit > 0 ? amount : muted,
              textAlign: TextAlign.end,
            ),
          ),
          SizedBox(
            width: ledgerBalanceWidth,
            child: Text(
              Formatters.currency(entry.balance),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

/// The totals footer row — Total Debit / Total Credit in the amount
/// columns and [closingBalance] in the balance column, labelled
/// [closingLabel] (e.g. "Closing Balance").
class LedgerTotalsRow extends StatelessWidget {
  const LedgerTotalsRow({
    super.key,
    required this.totalDebit,
    required this.totalCredit,
    required this.closingBalance,
    required this.closingLabel,
  });

  final num totalDebit;
  final num totalCredit;
  final num closingBalance;
  final String closingLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(
      context,
    ).textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant);
    final totalStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Container(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: ledgerDateWidth,
            child: Text(l10n.commonTotal, style: labelStyle),
          ),
          Expanded(
            child: Text(
              closingLabel,
              style: labelStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: ledgerAmountWidth,
            child: Text(
              Formatters.currency(totalDebit),
              style: totalStyle,
              textAlign: TextAlign.end,
            ),
          ),
          SizedBox(
            width: ledgerAmountWidth,
            child: Text(
              Formatters.currency(totalCredit),
              style: totalStyle,
              textAlign: TextAlign.end,
            ),
          ),
          SizedBox(
            width: ledgerBalanceWidth,
            child: Text(
              Formatters.currency(closingBalance),
              style: totalStyle,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
