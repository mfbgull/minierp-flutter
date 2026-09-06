// Statement tab — web `CustomerStatement` parity (customer-module-spec.md
// §6.8): date-range filter (default last 30 days), customer info block,
// statement summary (Opening / Closing / Total Debits / Total Credits)
// and the transaction table with an opening-balance row, per-row running
// balances and a closing-balance row.
//
// Under the unified detail-page range (unified-detail-date-picker-spec D1)
// the range comes from the page header pill via the session pair — this
// tab no longer owns its own filter. "All dates" (session range null)
// fetches the full-history statement (opening 0 — Phase-2 server fix) and
// the framing row labels read from the statement's own from/to.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/customer.dart' show Customer;
import '../../data/models/ledger_entry.dart' show LedgerEntry;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../data/repositories/customer_repository.dart'
    show CustomerStatement;
import '../../l10n/app_localizations.dart';
import '../../widgets/detail_error.dart';
import '../../widgets/filtered_empty_state.dart';
import 'customer_providers.dart';
import 'package:minierp_app/core/theme/app_border_radius.dart';

class CustomerStatementTab extends ConsumerWidget {
  const CustomerStatementTab({
    super.key,
    required this.customerId,
    required this.sessionId,
  });

  final int customerId;

  /// The detail-page instance's range-session id — this tab reads the
  /// header pill's pair through it (spec §3.1).
  final int sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final range = customerDetailRangeIso(ref, sessionId);
    final args = CustomerStatementArgs(
      customerId: customerId,
      fromDate: range.from,
      toDate: range.to,
    );
    final statement = ref.watch(customerStatementProvider(args));
    final customer = ref.watch(customerDetailProvider(customerId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: switch (statement) {
            AsyncData(:final value) => _buildContent(
              context,
              l10n,
              value,
              customer.valueOrNull,
            ),
            AsyncError(:final error) => DetailError(
              message: error is ApiError ? error.message : '$error',
              onRetry: () =>
                  ref.invalidate(customerStatementProvider(args)),
            ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
      ],
    );
  }

  Widget _buildContent(
    BuildContext context,
    AppLocalizations l10n,
    CustomerStatement statement,
    Customer? customer,
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

    // All-dates (full history) statements open at 0 — the Phase-2 server
    // fix — and the opening row carries no range label; ranged statements
    // label it with the range start (web parity).
    final openingLabel = statement.fromDate == null
        ? l10n.customersOpeningbalance
        : '${l10n.customersOpeningbalance} (${Formatters.date(statement.fromDate!)})';

    if (statement.transactions.isEmpty) {
      return const FilteredEmptyState();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Customer info + summary side by side.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _infoCard(
                  context,
                  l10n.customersCustomerdetails,
                  [
                    (l10n.customersCustomername, customer?.customerName ?? statement.customerName),
                    (l10n.customersCustomercode, customer?.customerCode ?? '—'),
                    (l10n.customersContactperson, customer?.contactPerson ?? '—'),
                    (l10n.fieldsEmail, customer?.email ?? '—'),
                    (l10n.fieldsPhone, customer?.phone ?? '—'),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _infoCard(
                  context,
                  l10n.customersStatementsummary,
                  [
                    (l10n.customersOpeningbalance, Formatters.currency(statement.openingBalance)),
                    (l10n.customersClosingbalance, Formatters.currency(statement.closingBalance)),
                    (l10n.customersTotaldebits, Formatters.currency(totalDebits)),
                    (l10n.customersTotalcredits, Formatters.currency(totalCredits)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            l10n.customersTransactiondetails,
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
    CustomerStatement statement,
    String openingLabel,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final headers = [
      l10n.commonDate,
      l10n.fieldsReference,
      l10n.commonDescription,
      l10n.customersLedgerDebit,
      l10n.customersLedgerCredit,
      l10n.customersBalance,
    ];

    TableRow headerRow() => TableRow(
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest),
      children: [
        for (final h in headers)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Text(
              h,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );

    Widget cell(String text, {bool amount = false, TextStyle? style}) =>
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            text,
            textAlign: amount ? TextAlign.end : TextAlign.start,
            style: style ?? const TextStyle(fontSize: 12.5),
          ),
        );

    // Running balance per transaction (web parity: each row shows the
    // balance after that row's debit/credit).
    final runningRows = <(LedgerEntry, num)>[];
    var running = statement.openingBalance;
    for (final t in statement.transactions) {
      running += t.debit - t.credit;
      runningRows.add((t, running));
    }

    return Table(
      columnWidths: const {
        0: FixedColumnWidth(110),
        1: FixedColumnWidth(130),
        2: FixedColumnWidth(220),
        3: FixedColumnWidth(120),
        4: FixedColumnWidth(120),
        5: FixedColumnWidth(120),
      },
      border: TableBorder(
        horizontalInside: BorderSide(color: scheme.outlineVariant, width: 0.5),
      ),
      children: [
        headerRow(),
        // Opening balance row.
        TableRow(
          children: [
            cell(statement.fromDate ?? ''),
            cell(
              openingLabel,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            cell(l10n.customersOpeningbalance),
            cell(''),
            cell(''),
            cell(
              Formatters.currency(statement.openingBalance),
              amount: true,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        for (final (t, balance) in runningRows)
          TableRow(
            children: [
              cell(Formatters.date(t.transactionDate)),
              cell(t.referenceNo),
              cell(t.description),
              cell(
                t.debit > 0 ? Formatters.currency(t.debit) : '',
                amount: true,
                style: TextStyle(color: scheme.error),
              ),
              cell(
                t.credit > 0 ? Formatters.currency(t.credit) : '',
                amount: true,
                style: TextStyle(color: scheme.primary),
              ),
              cell(Formatters.currency(balance), amount: true),
            ],
          ),
        // Closing balance row.
        TableRow(
          children: [
            cell(statement.toDate ?? ''),
            cell(
              l10n.customersClosingbalance,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            cell(l10n.customersClosingbalance),
            cell(''),
            cell(''),
            cell(
              Formatters.currency(statement.closingBalance),
              amount: true,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ],
    );
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
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 130,
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(value, style: const TextStyle(fontSize: 12)),
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