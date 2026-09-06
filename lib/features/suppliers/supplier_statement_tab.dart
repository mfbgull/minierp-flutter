// Statement tab — web `SupplierStatement` parity (same treatment as the
// customer module): date-range filter (default last 30 days), supplier
// info block, statement summary (Opening / Closing / Total Debits / Total
// Credits) and the transaction table with an opening-balance row,
// per-row running balances and a closing-balance row.
//
// Under the unified detail-page range (unified-detail-date-picker-spec D1)
// the range comes from the page header pill via the session pair — this
// tab no longer owns its own filter. "All dates" (session range null)
// fetches the full-history statement (opening 0 — Phase-2 server fix) and
// the framing row labels read from the statement's own from/to.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/supplier.dart' show Supplier;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../data/repositories/supplier_repository.dart'
    show SupplierStatement;
import '../../l10n/app_localizations.dart';
import '../../widgets/detail_error.dart';
import '../../widgets/filtered_empty_state.dart';
import 'supplier_providers.dart';
import 'package:minierp_app/core/theme/app_border_radius.dart';

class SupplierStatementTab extends ConsumerWidget {
  const SupplierStatementTab({
    super.key,
    required this.supplierId,
    required this.sessionId,
  });

  final int supplierId;

  /// The detail-page instance's range-session id — this tab reads the
  /// header pill's pair through it (spec §3.1).
  final int sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final range = supplierDetailRangeIso(ref, sessionId);
    final args = SupplierStatementArgs(
      supplierId: supplierId,
      fromDate: range.from,
      toDate: range.to,
    );
    final statement = ref.watch(supplierStatementProvider(args));
    final supplier = ref.watch(supplierDetailProvider(supplierId));

    return switch (statement) {
      AsyncData(:final value) => _buildContent(
        context,
        l10n,
        value,
        supplier.valueOrNull,
      ),
      AsyncError(:final error) => DetailError(
        message: error is ApiError ? error.message : '$error',
        onRetry: () => ref.invalidate(supplierStatementProvider(args)),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }

  Widget _buildContent(
    BuildContext context,
    AppLocalizations l10n,
    SupplierStatement statement,
    Supplier? supplier,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final totalDebits = statement.transactions.fold<num>(
      0,
      (sum, t) => sum + t.debit,
    );
    final totalCredits = statement.transactions.fold<num>(
      0,
      (sum, t) => sum + t.credit,
    );

    if (statement.transactions.isEmpty) {
      return const FilteredEmptyState();
    }

    // The opening framing row's reference cell carries the same label as
    // the summary tile (customer-mirror parity); ranged statements append
    // the range start. The description cell keeps the "Beginning balance"
    // wording, matching the pre-existing supplier layout.
    final openingLabel = statement.fromDate == null
        ? l10n.suppliersOpeningbalance
        : '${l10n.suppliersOpeningbalance} (${Formatters.date(statement.fromDate!)})';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Supplier info + summary side by side.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _infoCard(
                  context,
                  l10n.suppliersSupplierdetails,
                  [
                    (l10n.suppliersSuppliername, supplier?.supplierName ?? statement.supplierName),
                    (l10n.suppliersSuppliercode, supplier?.supplierCode ?? '—'),
                    (l10n.suppliersContactperson, supplier?.contactPerson ?? '—'),
                    (l10n.fieldsEmail, supplier?.email ?? '—'),
                    (l10n.fieldsPhone, supplier?.phone ?? '—'),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _infoCard(
                  context,
                  l10n.suppliersStatementsummary,
                  [
                    (l10n.suppliersOpeningbalance, Formatters.currency(statement.openingBalance)),
                    (l10n.suppliersClosingbalance, Formatters.currency(statement.closingBalance)),
                    (l10n.suppliersTotaldebits, Formatters.currency(totalDebits)),
                    (l10n.suppliersTotalcredits, Formatters.currency(totalCredits)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            l10n.suppliersTransactiondetails,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            elevation: 0,
            color: scheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: AppBorderRadius.mdRadius,
              side: BorderSide(color: scheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _buildTable(context, l10n, statement, openingLabel),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(
    BuildContext context,
    AppLocalizations l10n,
    SupplierStatement statement,
    String openingLabel,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final headers = [
      l10n.commonDate,
      l10n.fieldsReference,
      l10n.commonDescription,
      l10n.suppliersLedgerDebit,
      l10n.suppliersLedgerCredit,
      l10n.suppliersBalance,
    ];

    TableRow headerRow() => TableRow(
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest),
      children: [
        for (final h in headers)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              h,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ),
      ],
    );

    final rows = <TableRow>[
      // Opening balance row.
      TableRow(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
        ),
        children: [
          for (final (i, _) in headers.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: switch (i) {
                0 => Text(
                  statement.fromDate == null
                      ? ''
                      : Formatters.date(statement.fromDate!),
                  style: const TextStyle(fontSize: 12),
                ),
                1 => Text(
                  openingLabel,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                2 => Text(
                  l10n.suppliersBeginningbalance,
                  style: const TextStyle(fontSize: 12),
                ),
                5 => Text(
                  Formatters.currency(statement.openingBalance),
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                _ => const SizedBox.shrink(),
              },
            ),
        ],
      ),
      // Transaction rows with running balance.
      for (final (index, t) in statement.transactions.indexed)
        TableRow(
          children: [
            for (final (i, _) in headers.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: switch (i) {
                  0 => Text(
                    t.transactionDate.isEmpty
                        ? '—'
                        : Formatters.date(t.transactionDate),
                    style: const TextStyle(fontSize: 12),
                  ),
                  1 => Text(
                    t.referenceNo.isEmpty ? '—' : t.referenceNo,
                    style: const TextStyle(fontSize: 12),
                  ),
                  2 => Text(
                    t.description.isEmpty ? '—' : t.description,
                    style: const TextStyle(fontSize: 12),
                  ),
                  3 => t.debit > 0
                      ? Text(
                          Formatters.currency(t.debit),
                          textAlign: TextAlign.end,
                          style: const TextStyle(fontSize: 12),
                        )
                      : const SizedBox.shrink(),
                  4 => t.credit > 0
                      ? Text(
                          Formatters.currency(t.credit),
                          textAlign: TextAlign.end,
                          style: const TextStyle(fontSize: 12),
                        )
                      : const SizedBox.shrink(),
                  _ => Text(
                    Formatters.currency(
                      _runningBalance(statement, index),
                    ),
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                },
              ),
          ],
        ),
      // Closing balance row.
      TableRow(
        decoration: BoxDecoration(color: scheme.surfaceContainerLow),
        children: [
          for (final (i, _) in headers.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: switch (i) {
                0 => Text(
                  statement.toDate == null
                      ? ''
                      : Formatters.date(statement.toDate!),
                  style: const TextStyle(fontSize: 12),
                ),
                1 => const Text(
                  'Closing Balance',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                2 => Text(
                  l10n.suppliersEndingbalance,
                  style: const TextStyle(fontSize: 12),
                ),
                5 => Text(
                  Formatters.currency(statement.closingBalance),
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                _ => const SizedBox.shrink(),
              },
            ),
        ],
      ),
    ];

    return Table(
      border: TableBorder(
        horizontalInside: BorderSide(color: scheme.outlineVariant, width: 0.5),
        verticalInside: BorderSide(color: scheme.outlineVariant, width: 0.5),
      ),
      defaultColumnWidth: const IntrinsicColumnWidth(),
      children: [headerRow(), ...rows],
    );
  }

  num _runningBalance(SupplierStatement statement, int index) {
    var balance = statement.openingBalance;
    for (var i = 0; i <= index; i++) {
      final t = statement.transactions[i];
      balance += t.debit - t.credit;
    }
    return balance;
  }

  Widget _infoCard(
    BuildContext context,
    String title,
    List<(String, String)> rows,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: AppBorderRadius.mdRadius,
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 8),
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 140,
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        value,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}