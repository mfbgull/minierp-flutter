// Invoice return detail dialog — opened by double-tapping a return row
// (or F2/Enter). Unlike the other module dialogs there is no per-row
// endpoint (`GET /invoices/returns` is the whole story), so the dialog
// renders from the in-memory [SalesReturn] the grid row was built
// from — no fetch, no loading/error states.

import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/sales_return.dart' show SalesReturn;
import '../../l10n/app_localizations.dart';
import '../../widgets/detail_labels.dart';
import '../../widgets/detail_rows.dart';
import '../../widgets/status_badge.dart';
import 'invoice_return_type.dart';

/// Opens the read-only detail dialog for a return row.
Future<void> showInvoiceReturnDetailDialog(
  BuildContext context, {
  required SalesReturn salesReturn,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) =>
        _InvoiceReturnDetailDialog(salesReturn: salesReturn),
  );
}

class _InvoiceReturnDetailDialog extends StatelessWidget {
  const _InvoiceReturnDetailDialog({required this.salesReturn});

  final SalesReturn salesReturn;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final color = invoiceReturnTypeColors(Theme.of(context).colorScheme, 
      salesReturn.referenceDocType,
    );

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        detailSectionLabel(
                          context,
                          l10n.salesreturnsReturntitle,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          salesReturn.movementNo,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                  ),
                  StatusBadge(
                    status: invoiceReturnTypeLabel(
                      l10n,
                      salesReturn.referenceDocType,
                    ),
                    color: color,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DetailTiles(
                tiles: [
                  DetailTile(
                    l10n.fieldsQuantity,
                    Formatters.number(salesReturn.quantity),
                    emphasize: true,
                  ),
                  DetailTile(l10n.fieldsUnit, salesReturn.unitOfMeasure),
                  DetailTile(
                    l10n.salesreturnsReturnvalue,
                    Formatters.currency(salesReturn.returnValue),
                    emphasize: true,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DetailInfoRows(
                rows: [
                  (
                    l10n.salesreturnsReturndate,
                    Formatters.date(salesReturn.returnDate),
                  ),
                  (l10n.fieldsCustomer, salesReturn.customerName ?? '—'),
                  (l10n.fieldsItem, salesReturn.itemName),
                  (l10n.fieldsInvoice, salesReturn.invoiceNo ?? '—'),
                  (l10n.fieldsWarehouse, salesReturn.warehouseName),
                  if (salesReturn.remarks != null &&
                      salesReturn.remarks!.isNotEmpty)
                    (l10n.fieldsNotes, salesReturn.remarks!),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.commonClose),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
