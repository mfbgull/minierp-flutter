// Purchase return detail dialog — opened by double-tapping a return row
// (or F2/Enter). Unlike the other module dialogs there is no per-row
// endpoint (`GET /purchases/returns` is the whole story), so the dialog
// renders from the in-memory [PurchaseReturn] the grid row was built
// from — no fetch, no loading/error states.

import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/purchase_return.dart' show PurchaseReturn;
import '../../l10n/app_localizations.dart';
import '../../widgets/detail_labels.dart';
import '../../widgets/detail_rows.dart';
import '../../widgets/status_badge.dart';
import 'purchase_return_type.dart';

/// Opens the read-only detail dialog for a return row.
Future<void> showPurchaseReturnDetailDialog(
  BuildContext context, {
  required PurchaseReturn purchaseReturn,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) =>
        _PurchaseReturnDetailDialog(purchaseReturn: purchaseReturn),
  );
}

class _PurchaseReturnDetailDialog extends StatelessWidget {
  const _PurchaseReturnDetailDialog({required this.purchaseReturn});

  final PurchaseReturn purchaseReturn;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final (color, darkColor) = returnTypeColors(
      purchaseReturn.referenceDocType,
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
                        detailSectionLabel(context, l10n.purchasesReturntitle),
                        const SizedBox(height: 2),
                        Text(
                          purchaseReturn.movementNo,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                  ),
                  StatusBadge(
                    status: returnTypeLabel(
                      l10n,
                      purchaseReturn.referenceDocType,
                    ),
                    color: color,
                    darkColor: darkColor,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DetailTiles(
                tiles: [
                  DetailTile(
                    l10n.fieldsQuantity,
                    Formatters.number(purchaseReturn.returnQty),
                    emphasize: true,
                  ),
                  DetailTile(l10n.fieldsUnit, purchaseReturn.unitOfMeasure),
                  DetailTile(
                    l10n.purchasesReturnvalue,
                    Formatters.currency(purchaseReturn.returnValue),
                    emphasize: true,
                  ),
                ],
              ),
              DetailInfoRows(
                rows: [
                  (
                    l10n.purchasesReturndate,
                    Formatters.date(purchaseReturn.returnDate),
                  ),
                  (l10n.fieldsItem, purchaseReturn.itemName),
                  (l10n.fieldsWarehouse, purchaseReturn.warehouseName),
                  (l10n.fieldsReference, purchaseReturn.referenceDocNo ?? '—'),
                  if (purchaseReturn.remarks != null &&
                      purchaseReturn.remarks!.isNotEmpty)
                    (l10n.fieldsNotes, purchaseReturn.remarks!),
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
