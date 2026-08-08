// Purchase-summary row detail dialog — port of the web report's PO
// modal: every field of the selected purchase-order row (incl. the
// received/balance amounts and the localized status).

import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../core/utils/po_status.dart';
import '../../data/models/report.dart' show PurchaseSummaryRow;
import '../../l10n/app_localizations.dart';

Future<void> showPurchaseSummaryDetailDialog(
  BuildContext context, {
  required PurchaseSummaryRow row,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _PurchaseSummaryDetailDialog(row: row),
  );
}

class _PurchaseSummaryDetailDialog extends StatelessWidget {
  const _PurchaseSummaryDetailDialog({required this.row});

  final PurchaseSummaryRow row;

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
      title: Text(row.purchaseOrderNumber),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            field(l10n.fieldsSupplier, row.supplierName),
            field(
              l10n.fieldsDate,
              row.purchaseDate.isEmpty
                  ? '—'
                  : Formatters.date(row.purchaseDate),
            ),
            field(l10n.reportsTotalcost, Formatters.currency(row.totalCost)),
            field(l10n.reportsItems, Formatters.number(row.totalItems)),
            field(
              l10n.reportsReceived,
              Formatters.currency(row.receivedAmount),
            ),
            field(l10n.reportsBalance, Formatters.currency(row.balanceAmount)),
            field(l10n.fieldsStatus, poStatusLabel(l10n, row.status)),
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
