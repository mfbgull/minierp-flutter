// Statement tab — web `SupplierStatement` parity (same treatment as the
// customer module): date-range filter (default last 30 days), supplier
// info block, statement summary (Opening / Closing / Total Debits / Total
// Credits) and the transaction table with an opening-balance row,
// per-row running balances and a closing-balance row.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart' show isoDate;
import '../../core/utils/formatters.dart';
import '../../data/models/supplier.dart' show Supplier;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../data/repositories/supplier_repository.dart'
    show SupplierStatement;
import '../../l10n/app_localizations.dart';
import '../../widgets/date_picker_helpers.dart' show pickDate;
import '../../widgets/detail_error.dart';
import 'supplier_providers.dart';

class SupplierStatementTab extends ConsumerStatefulWidget {
  const SupplierStatementTab({super.key, required this.supplierId});

  final int supplierId;

  @override
  ConsumerState<SupplierStatementTab> createState() =>
      _SupplierStatementTabState();
}

class _SupplierStatementTabState extends ConsumerState<SupplierStatementTab> {
  late DateTime _from;
  late DateTime _to;
  late final TextEditingController _fromController;
  late final TextEditingController _toController;

  @override
  void initState() {
    super.initState();
    _to = DateTime.now();
    _from = DateTime(_to.year, _to.month - 1, _to.day);
    _fromController = TextEditingController(
      text: Formatters.date(isoDate(_from)),
    );
    _toController = TextEditingController(text: Formatters.date(isoDate(_to)));
  }

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    super.dispose();
  }

  void _syncDateFields() {
    _fromController.text = Formatters.date(isoDate(_from));
    _toController.text = Formatters.date(isoDate(_to));
  }

  Future<void> _pickFrom() async {
    final picked = await pickDate(context, initialDate: _from, lastDate: _to);
    if (picked != null) {
      setState(() {
        _from = picked;
        _syncDateFields();
      });
    }
  }

  Future<void> _pickTo() async {
    final picked = await pickDate(context, initialDate: _to);
    if (picked != null) {
      setState(() {
        _to = picked;
        _syncDateFields();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final args = SupplierStatementArgs(
      supplierId: widget.supplierId,
      fromDate: isoDate(_from),
      toDate: isoDate(_to),
    );
    final statement = ref.watch(supplierStatementProvider(args));
    final supplier = ref.watch(supplierDetailProvider(widget.supplierId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Date-range filter.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              _dateField(
                context,
                l10n.commonFrom,
                _fromController,
                _pickFrom,
              ),
              const SizedBox(width: 12),
              _dateField(context, l10n.commonTo, _toController, _pickTo),
              const Spacer(),
              TextButton.icon(
                onPressed: () =>
                    ref.invalidate(supplierStatementProvider(args)),
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(l10n.commonRefresh),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: switch (statement) {
            AsyncData(:final value) => _buildContent(
              context,
              l10n,
              value,
              supplier.valueOrNull,
            ),
            AsyncError(:final error) => DetailError(
              message: error is ApiError ? error.message : '$error',
              onRetry: () =>
                  ref.invalidate(supplierStatementProvider(args)),
            ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
      ],
    );
  }

  Widget _dateField(
    BuildContext context,
    String label,
    TextEditingController controller,
    VoidCallback onTap,
  ) {
    return SizedBox(
      width: 180,
      child: TextField(
        readOnly: true,
        onTap: onTap,
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.calendar_today, size: 16),
        ),
      ),
    );
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
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: scheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _buildTable(context, l10n, statement),
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
                      ? isoDate(_from)
                      : Formatters.date(statement.fromDate!),
                  style: const TextStyle(fontSize: 12),
                ),
                1 => const Text(
                  'Opening Balance',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
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
                      ? isoDate(_to)
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
        borderRadius: BorderRadius.circular(12),
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
