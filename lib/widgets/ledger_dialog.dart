// Shared ledger dialog — the customer AR ledger (`GET
// /customers/:id/ledger`) and the supplier AP ledger (`GET
// /suppliers/:id/ledger`) are the same thing: an enveloped array,
// newest-first by transaction_date, rendered as a compact accounting
// table (Date | Description | Debit | Credit | Balance) with a totals
// footer row. They differ only in the data provider and the l10n keys —
// parameterize those via [LedgerDialogConfig] so there is one
// implementation. The table rows themselves are the shared
// [LedgerHeaderRow] / [LedgerEntryRow] / [LedgerTotalsRow] primitives.
//
// The module facades (`features/customers/customer_ledger_dialog.dart`,
// `features/suppliers/supplier_ledger_dialog.dart`) keep their public
// dialog classes + openers and delegate here.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/ledger_entry.dart' show LedgerEntry;
import '../data/repositories/api_result.dart' show ApiError;
import '../l10n/app_localizations.dart';
import 'detail_error.dart';
import 'detail_labels.dart';
import 'ledger_table.dart';
import 'package:minierp_app/core/theme/app_border_radius.dart';

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
  final AutoDisposeFutureProviderFamily<List<LedgerEntry>, int> entriesProvider;
}

/// The ledger dialog body — watches [LedgerDialogConfig.entriesProvider]
/// for [entryId], then renders the table, totals, empty or error state.
/// [footerAction] (if given) renders in the footer before the Close button
/// — e.g. the supplier's Statement opener.
class LedgerDialog extends ConsumerWidget {
  const LedgerDialog({
    super.key,
    required this.entryId,
    required this.entryName,
    required this.config,
    this.footerAction,
  });

  final int entryId;
  final String entryName;
  final LedgerDialogConfig config;
  final Widget? footerAction;

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
            footerAction: footerAction,
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
    required this.footerAction,
  });

  final String entryName;
  final List<LedgerEntry> entries;
  final LedgerDialogConfig config;
  final Widget? footerAction;

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
              if (footerAction != null) ...[
                footerAction!,
                const SizedBox(width: 4),
              ],
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
        borderRadius: AppBorderRadius.smRadius,
      ),
      child: Column(
        children: [
          LedgerHeaderRow(
            debitLabel: config.debitLabel,
            creditLabel: config.creditLabel,
            balanceLabel: config.balanceLabel,
          ),
          for (final entry in entries) ...[
            const Divider(height: 1),
            LedgerEntryRow(entry: entry),
          ],
          const Divider(height: 1),
          LedgerTotalsRow(
            totalDebit: totalDebit,
            totalCredit: totalCredit,
            closingBalance: closingBalance,
            closingLabel: config.closingBalanceLabel,
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
