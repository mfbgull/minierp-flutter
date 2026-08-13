// Statement tab — web `CustomerStatement` parity (customer-module-spec.md
// §6.8): date-range filter (default last 30 days), customer info block,
// statement summary (Opening / Closing / Total Debits / Total Credits)
// and the transaction table with an opening-balance row, per-row running
// balances and a closing-balance row.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart' show isoDate;
import '../../core/utils/formatters.dart';
import '../../data/models/customer.dart' show Customer;
import '../../data/models/ledger_entry.dart' show LedgerEntry;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../data/repositories/customer_repository.dart'
    show CustomerStatement;
import '../../l10n/app_localizations.dart';
import '../../widgets/date_picker.dart' show pickDate;
import '../../widgets/detail_error.dart';
import 'customer_providers.dart';

class CustomerStatementTab extends ConsumerStatefulWidget {
  const CustomerStatementTab({super.key, required this.customerId});

  final int customerId;

  @override
  ConsumerState<CustomerStatementTab> createState() =>
      _CustomerStatementTabState();
}

class _CustomerStatementTabState extends ConsumerState<CustomerStatementTab> {
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
    final args = CustomerStatementArgs(
      customerId: widget.customerId,
      fromDate: isoDate(_from),
      toDate: isoDate(_to),
    );
    final statement = ref.watch(customerStatementProvider(args));
    final customer = ref.watch(customerDetailProvider(widget.customerId));

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
                    ref.invalidate(customerStatementProvider(args)),
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
    CustomerStatement statement,
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
              l10n.customersOpeningbalance,
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
                style: TextStyle(color: Colors.green.shade700),
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
