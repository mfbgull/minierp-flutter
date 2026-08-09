// Customer statement detail dialog — port of the web report's customer
// statement modal: read-only fields for the selected customer row.

import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/report.dart' show CustomerStatementRow;
import '../../l10n/app_localizations.dart';

Future<void> showCustomerStatementDetailDialog(
  BuildContext context, {
  required CustomerStatementRow row,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _CustomerStatementDetailDialog(row: row),
  );
}

class _CustomerStatementDetailDialog extends StatelessWidget {
  const _CustomerStatementDetailDialog({required this.row});

  final CustomerStatementRow row;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;

    Widget field(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    return AlertDialog(
      title: Text(row.customerName),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            field(l10n.fieldsCustomerCode, row.customerCode),
            field(
              l10n.reportsInvoicecount,
              Formatters.number(row.invoiceCount),
            ),
            field(
              l10n.reportsOpeningbalance,
              Formatters.currency(row.openingBalance),
            ),
            field(
              l10n.reportsTotaldebits,
              Formatters.currency(row.totalDebits),
            ),
            field(
              l10n.reportsTotalcredits,
              Formatters.currency(row.totalCredits),
            ),
            field(
              l10n.reportsClosingbalance,
              Formatters.currency(row.closingBalance),
            ),
            field(
              l10n.reportsTotalamount,
              Formatters.currency(row.totalAmount),
            ),
            field(
              l10n.reportsPaidamount,
              Formatters.currency(row.paidAmount),
            ),
            field(
              l10n.reportsBalance,
              Formatters.currency(row.balance),
            ),
            field(
              l10n.reportsLastinvoicedate,
              row.lastInvoiceDate == null
                  ? '-'
                  : Formatters.date(row.lastInvoiceDate!),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonClose),
        ),
      ],
    );
  }
}
