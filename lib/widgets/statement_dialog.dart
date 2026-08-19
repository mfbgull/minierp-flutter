// Shared statement dialog — the customer and supplier account statements
// (`GET /customers/:id/statement`, `GET /suppliers/:id/statement`) are
// the same enveloped shape: opening balance, closing balance, and the
// period's transactions (oldest-first). They differ only in the data
// provider and the l10n keys — parameterize those via
// [StatementDialogConfig] so there is one implementation.
//
// Renders the opening/closing balance tiles above the same accounting
// table as the ledger dialog (shared [LedgerHeaderRow] / [LedgerEntryRow]
// / [LedgerTotalsRow]), prefixed by an Opening Balance row.
//
// The module facades (`features/suppliers/supplier_statement_dialog.dart`)
// keep their public dialog class + opener and delegate here.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/formatters.dart';
import '../data/models/statement.dart' show StatementData;
import '../data/repositories/api_result.dart' show ApiError;
import '../l10n/app_localizations.dart';
import 'detail_error.dart';
import 'detail_labels.dart';
import 'detail_rows.dart';
import 'ledger_table.dart';
import 'package:minierp_app/core/theme/app_border_radius.dart';

/// What differs between the customer and supplier statements: the
/// localized strings and the `autoDispose` family provider that fetches
/// the statement for a given entity id.
class StatementDialogConfig {
  const StatementDialogConfig({
    required this.sectionLabel,
    required this.debitLabel,
    required this.creditLabel,
    required this.balanceLabel,
    required this.openingBalanceLabel,
    required this.closingBalanceLabel,
    required this.noEntriesLabel,
    required this.statementProvider,
  });

  /// Header label above the entity name (e.g. "Statement").
  final String sectionLabel;

  final String debitLabel;
  final String creditLabel;
  final String balanceLabel;
  final String openingBalanceLabel;
  final String closingBalanceLabel;
  final String noEntriesLabel;

  /// The module's statement provider — `supplierStatementProvider`.
  final AutoDisposeFutureProviderFamily<StatementData, int> statementProvider;
}

/// The statement dialog body — watches
/// [StatementDialogConfig.statementProvider] for [entryId], then renders
/// the balance tiles, the table (opening row + transactions + totals),
/// empty or error state.
class StatementDialog extends ConsumerWidget {
  const StatementDialog({
    super.key,
    required this.entryId,
    required this.entryName,
    required this.config,
  });

  final int entryId;
  final String entryName;
  final StatementDialogConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statement = ref.watch(config.statementProvider(entryId));
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 680),
        child: switch (statement) {
          AsyncData(:final value) => _StatementBody(
            entryName: entryName,
            statement: value,
            config: config,
          ),
          AsyncError(:final error) => DetailError(
            message: error is ApiError ? error.message : '$error',
            onRetry: () => ref.invalidate(config.statementProvider(entryId)),
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

class _StatementBody extends StatelessWidget {
  const _StatementBody({
    required this.entryName,
    required this.statement,
    required this.config,
  });

  final String entryName;
  final StatementData statement;
  final StatementDialogConfig config;

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
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DetailTiles(
                  tiles: [
                    DetailTile(
                      config.openingBalanceLabel,
                      Formatters.currency(statement.openingBalance),
                      emphasize: true,
                    ),
                    DetailTile(
                      config.closingBalanceLabel,
                      Formatters.currency(statement.closingBalance),
                      emphasize: true,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (statement.transactions.isEmpty)
                  Text(
                    config.noEntriesLabel,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  _StatementTable(statement: statement, config: config),
              ],
            ),
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

class _StatementTable extends StatelessWidget {
  const _StatementTable({required this.statement, required this.config});

  final StatementData statement;
  final StatementDialogConfig config;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entries = statement.transactions;

    final totalDebit = entries.fold<num>(0, (sum, e) => sum + e.debit);
    final totalCredit = entries.fold<num>(0, (sum, e) => sum + e.credit);

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
          const Divider(height: 1),
          _OpeningRow(
            openingLabel: config.openingBalanceLabel,
            openingBalance: statement.openingBalance,
          ),
          for (final entry in entries) ...[
            const Divider(height: 1),
            LedgerEntryRow(entry: entry),
          ],
          const Divider(height: 1),
          LedgerTotalsRow(
            totalDebit: totalDebit,
            totalCredit: totalCredit,
            closingBalance: statement.closingBalance,
            closingLabel: config.closingBalanceLabel,
          ),
        ],
      ),
    );
  }
}

/// The opening-balance row: label in the description column, amount in the
/// balance column (debit/credit stay empty).
class _OpeningRow extends StatelessWidget {
  const _OpeningRow({required this.openingLabel, required this.openingBalance});

  final String openingLabel;
  final num openingBalance;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(
      context,
    ).textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant);
    final amountStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const SizedBox(width: ledgerDateWidth),
          Expanded(child: Text(openingLabel, style: labelStyle)),
          const SizedBox(width: ledgerAmountWidth),
          const SizedBox(width: ledgerAmountWidth),
          SizedBox(
            width: ledgerBalanceWidth,
            child: Text(
              Formatters.currency(openingBalance),
              style: amountStyle,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
