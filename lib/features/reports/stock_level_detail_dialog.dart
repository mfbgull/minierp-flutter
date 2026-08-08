// Stock-level item detail dialog — port of the web report's stock modal:
// every field of the selected row (incl. selling price and the derived
// stock status).

import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../core/utils/stock_status.dart';
import '../../data/models/report.dart' show StockLevelRow;
import '../../l10n/app_localizations.dart';

Future<void> showStockLevelDetailDialog(
  BuildContext context, {
  required StockLevelRow item,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _StockLevelDetailDialog(item: item),
  );
}

class _StockLevelDetailDialog extends StatelessWidget {
  const _StockLevelDetailDialog({required this.item});

  final StockLevelRow item;

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
              l10n.inventoryReorderlevel,
              '${Formatters.number(item.reorderLevel)} ${item.unitOfMeasure}',
            ),
            row(
              l10n.reportsSellingprice,
              Formatters.currency(item.standardSellingPrice),
            ),
            row(
              l10n.reportsStockstatus,
              stockStatusLabel(l10n, item.stockStatus),
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
