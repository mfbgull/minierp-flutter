// Sales-by-item detail dialog — port of the web report's item modal:
// item code/category + sales stats for the selected item, with the
// Total Sales figure highlighted.

import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/report.dart' show SalesByItemRow;
import '../../l10n/app_localizations.dart';

Future<void> showSalesByItemDetailDialog(
  BuildContext context, {
  required SalesByItemRow item,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _SalesByItemDetailDialog(item: item),
  );
}

class _SalesByItemDetailDialog extends StatelessWidget {
  const _SalesByItemDetailDialog({required this.item});

  final SalesByItemRow item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
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
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            row(l10n.inventoryItemcode, item.itemCode.isEmpty ? '—' : item.itemCode),
            row(
              l10n.fieldsCategory,
              item.itemCategory.isEmpty ? '—' : item.itemCategory,
            ),
            row(
              l10n.reportsQuantitysold,
              Formatters.number(item.totalQuantitySold),
            ),
            row(
              l10n.reportsAvgsellingprice,
              Formatters.currency(item.averageSellingPrice),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n.reportsTotalsales,
                    style: textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    Formatters.currency(item.totalSales),
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                    ),
                  ),
                ],
              ),
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
