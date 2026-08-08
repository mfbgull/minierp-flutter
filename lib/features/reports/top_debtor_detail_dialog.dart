// Top-debtor row detail dialog — port of the web report's debtor modal:
// every field of the selected customer row (outstanding balance, total
// invoiced, invoice count).

import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/report.dart' show TopDebtorRow;
import '../../l10n/app_localizations.dart';

Future<void> showTopDebtorDetailDialog(
  BuildContext context, {
  required TopDebtorRow row,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _TopDebtorDetailDialog(row: row),
  );
}

class _TopDebtorDetailDialog extends StatelessWidget {
  const _TopDebtorDetailDialog({required this.row});

  final TopDebtorRow row;

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
              l10n.reportsTotaloutstanding,
              Formatters.currency(row.totalOutstanding),
            ),
            field(
              l10n.reportsTotalinvoiced,
              Formatters.currency(row.totalInvoiced),
            ),
            field(
              l10n.reportsInvoicecount,
              Formatters.number(row.invoiceCount),
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
