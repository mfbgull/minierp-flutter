// Low-stock item detail dialog — port of the web report's stock modal:
// every field of the selected row (including the derived stock_status
// and selling price, which the grid omits).

import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/report.dart' show LowStockReportRow;
import '../../l10n/app_localizations.dart';

Future<void> showLowStockDetailDialog(
  BuildContext context, {
  required LowStockReportRow item,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _LowStockDetailDialog(item: item),
  );
}

class _LowStockDetailDialog extends StatelessWidget {
  const _LowStockDetailDialog({required this.item});

  final LowStockReportRow item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;

    Widget row(String label, String value) => Padding(
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
      title: Text(item.itemName),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            row(l10n.inventoryItemcode, item.itemCode),
            row(
              l10n.fieldsCategory,
              item.itemCategory.isEmpty ? '—' : item.itemCategory,
            ),
            row(l10n.commonUom, item.unitOfMeasure),
            row(
              l10n.inventoryCurrentstock,
              '${Formatters.number(item.currentStock)} ${item.unitOfMeasure}',
            ),
            row(
              l10n.reportsMinimumstock,
              '${Formatters.number(item.minimumStock)} ${item.unitOfMeasure}',
            ),
            row(
              l10n.reportsShortage,
              '${Formatters.number(item.shortage)} ${item.unitOfMeasure}',
            ),
            row(
              l10n.inventoryReorderlevel,
              '${Formatters.number(item.reorderLevel)} ${item.unitOfMeasure}',
            ),
            row(l10n.reportsStockstatus, item.stockStatus),
            row(
              l10n.reportsSellingprice,
              Formatters.currency(item.standardSellingPrice),
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
