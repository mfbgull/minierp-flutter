// Shared ledger dialog — the customer AR ledger (`GET
// /customers/:id/ledger`) and the supplier AP ledger (`GET
// /suppliers/:id/ledger`) are the same thing: an enveloped array,
// newest-first by transaction_date, rendered as a compact accounting
// table (Date | Description | Debit | Credit | Balance) with a totals
// footer row. They differ only in the data provider and the l10n keys —
// parameterize those via [LedgerDialogConfig] so there is one
// implementation.
//
// The module facades (`features/customers/customer_ledger_dialog.dart`,
// `features/suppliers/supplier_ledger_dialog.dart`) keep their public
// dialog classes + openers and delegate here.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/formatters.dart';
import '../data/models/ledger_entry.dart' show LedgerEntry;
import '../data/repositories/api_result.dart' show ApiError;
import '../l10n/app_localizations.dart';
import 'detail_error.dart';
import 'detail_labels.dart';

/// What differs between the customer and supplier ledgers: the localized
/// strings and the `autoDispose` family provider that fetches the entries
/// for a given entity id.
class LedgerDialogConfig {
  const LedgerDialogConfig({
    required this.sectionLabel,
    required this.debitLabel,
    required this.creditLabel,
    required this.balanceLabel,
    required this.closingBalanceLabel,
    required this.noEntriesLabel,
    required this.entriesProvider,
  });

  /// Header label above the entity name (e.g. "Ledger").
  final String sectionLabel;

  final String debitLabel;
  final String creditLabel;

  /// The running-balance column header (e.g. "Balance").
  final String balanceLabel;

  /// The totals-row label (e.g. "Closing Balance").
  final String closingBalanceLabel;

  final String noEntriesLabel;

  /// The module's ledger provider — `customerLedgerProvider` /
  /// `supplierLedgerProvider`.
  final AutoDisposeFutureProviderFamily<List<LedgerEntry>, int>
      entriesProvider;
}

/// The ledger dialog body — watches [LedgerDialogConfig.entriesProvider]
/// for [entryId], then renders the table, totals, empty or error state.
class LedgerDialog extends ConsumerWidget {
  const LedgerDialog({
    super.key,
    required this.entryId,
    required this.entryName,
    required this.config,
  });

  final int entryId;
  final String entryName;
  final LedgerDialogConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledger = ref.watch(config.entriesProvider(entryId));
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
        child: switch (ledger) {
          AsyncData(:final value) => _LedgerBody(
            entryName: entryName,
            entries: value,
            config: config,
          ),
          AsyncError(:final error) => DetailError(
            message: error is ApiError ? error.message : '$error',
            onRetry: () => ref.invalidate(config.entriesProvider(entryId)),
          ),
          _ => const SizedBox(
            width: 420,
            height: 240,
            child: Center(child: CircularProgressIndicator()),
          ),
        },
      ),
    );
  }
}

class _LedgerBody extends StatelessWidget {
  const _LedgerBody({
    required this.entryName,
    required this.entries,
    required this.config,
  });

  final String entryName;
  final List<LedgerEntry> entries;
  final LedgerDialogConfig config;

  // Shared column widths keep the header, rows and totals aligned.
  static const _dateWidth = 110.0;
  static const _amountWidth = 92.0;
  static const _balanceWidth = 104.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              detailSectionLabel(context, config.sectionLabel),
              const SizedBox(height: 2),
              Text(entryName, style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: entries.isEmpty
              ? _EmptyState(config: config)
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: _LedgerTable(entries: entries, config: config),
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.commonClose),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LedgerTable extends StatelessWidget {
  const _LedgerTable({required this.entries, required this.config});

  final List<LedgerEntry> entries;
  final LedgerDialogConfig config;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final totalDebit = entries.fold<num>(0, (sum, e) => sum + e.debit);
    final totalCredit = entries.fold<num>(0, (sum, e) => sum + e.credit);
    // The server returns newest-first, so the first row carries the latest
    // running balance — the closing balance.
    final closingBalance = entries.isEmpty ? 0 : entries.first.balance;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _HeaderRow(config: config),
          for (final entry in entries) ...[
            const Divider(height: 1),
            _EntryRow(entry: entry),
          ],
          const Divider(height: 1),
          _TotalsRow(
            totalDebit: totalDebit,
            totalCredit: totalCredit,
            closingBalance: closingBalance,
            config: config,
          ),
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.config});

  final LedgerDialogConfig config;

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
            width: _LedgerBody._dateWidth,
            child: Text(l10n.commonDate, style: style),
          ),
          Expanded(child: Text(l10n.commonDescription, style: style)),
          SizedBox(
            width: _LedgerBody._amountWidth,
            child: Text(
              config.debitLabel,
              style: style,
              textAlign: TextAlign.end,
            ),
          ),
          SizedBox(
            width: _LedgerBody._amountWidth,
            child: Text(
              config.creditLabel,
              style: style,
              textAlign: TextAlign.end,
            ),
          ),
          SizedBox(
            width: _LedgerBody._balanceWidth,
            child: Text(
              config.balanceLabel,
              style: style,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});

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
            width: _LedgerBody._dateWidth,
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
            width: _LedgerBody._amountWidth,
            child: Text(
              entry.debit > 0 ? Formatters.currency(entry.debit) : '—',
              style: entry.debit > 0 ? amount : muted,
              textAlign: TextAlign.end,
            ),
          ),
          SizedBox(
            width: _LedgerBody._amountWidth,
            child: Text(
              entry.credit > 0 ? Formatters.currency(entry.credit) : '—',
              style: entry.credit > 0 ? amount : muted,
              textAlign: TextAlign.end,
            ),
          ),
          SizedBox(
            width: _LedgerBody._balanceWidth,
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

class _TotalsRow extends StatelessWidget {
  const _TotalsRow({
    required this.totalDebit,
    required this.totalCredit,
    required this.closingBalance,
    required this.config,
  });

  final num totalDebit;
  final num totalCredit;
  final num closingBalance;
  final LedgerDialogConfig config;

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
            width: _LedgerBody._dateWidth,
            child: Text(l10n.commonTotal, style: labelStyle),
          ),
          Expanded(
            child: Text(
              config.closingBalanceLabel,
              style: labelStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: _LedgerBody._amountWidth,
            child: Text(
              Formatters.currency(totalDebit),
              style: totalStyle,
              textAlign: TextAlign.end,
            ),
          ),
          SizedBox(
            width: _LedgerBody._amountWidth,
            child: Text(
              Formatters.currency(totalCredit),
              style: totalStyle,
              textAlign: TextAlign.end,
            ),
          ),
          SizedBox(
            width: _LedgerBody._balanceWidth,
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.config});

  final LedgerDialogConfig config;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_outlined, size: 36, color: scheme.outline),
          const SizedBox(height: 10),
          Text(
            config.noEntriesLabel,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
