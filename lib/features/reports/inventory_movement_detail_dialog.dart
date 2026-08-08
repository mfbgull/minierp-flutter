// Inventory-movement row detail dialog — port of the web report's stock
// modal: every field of the selected movement row (incl. the reference
// document and remarks).

import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../core/utils/movement_type_label.dart';
import '../../data/models/report.dart' show InventoryMovementRow;
import '../../l10n/app_localizations.dart';

Future<void> showInventoryMovementDetailDialog(
  BuildContext context, {
  required InventoryMovementRow row,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _InventoryMovementDetailDialog(row: row),
  );
}

class _InventoryMovementDetailDialog extends StatelessWidget {
  const _InventoryMovementDetailDialog({required this.row});

  final InventoryMovementRow row;

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
      title: Text(row.itemName),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              field(l10n.reportsMovementno, row.movementNo),
              field(l10n.inventoryItemcode, row.itemCode),
              field(l10n.fieldsWarehouse, row.warehouseName),
              field(
                l10n.reportsMovementtype,
                movementTypeLabel(l10n, row.movementType),
              ),
              field(
                l10n.fieldsDate,
                row.movementDate.isEmpty
                    ? '—'
                    : Formatters.date(row.movementDate),
              ),
              field(l10n.fieldsQuantity, Formatters.number(row.quantity)),
              field(l10n.reportsUnitcost, Formatters.currency(row.unitCost)),
              if (row.referenceDocno.isNotEmpty)
                field(
                  '${l10n.fieldsReference} (${row.referenceDoctype})',
                  row.referenceDocno,
                ),
              if (row.remarks.isNotEmpty)
                field(l10n.purchasesRemarks, row.remarks),
            ],
          ),
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
