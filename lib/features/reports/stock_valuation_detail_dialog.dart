// Stock-valuation item detail dialog — port of the web report's stock
// modal: every field of the selected row (incl. unit cost, total value
// and the valuation method).

import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/report.dart' show StockValuationRow;
import '../../l10n/app_localizations.dart';

Future<void> showStockValuationDetailDialog(
  BuildContext context, {
  required StockValuationRow item,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _StockValuationDetailDialog(item: item),
  );
}

class _StockValuationDetailDialog extends StatelessWidget {
  const _StockValuationDetailDialog({required this.item});

  final StockValuationRow item;

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
            row(l10n.reportsUnitcost, Formatters.currency(item.unitCost)),
            row(l10n.reportsTotalvalue, Formatters.currency(item.totalValue)),
            row(l10n.reportsValuationmethod, item.valuationMethod),
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
