// Production-summary detail dialog — port of the web report's run modal:
// item, planned/completed/scrapped quantities, status and date for the
// selected production run.

import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/report.dart' show ProductionSummaryRow;
import '../../l10n/app_localizations.dart';

Future<void> showProductionSummaryDetailDialog(
  BuildContext context, {
  required ProductionSummaryRow row,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _ProductionSummaryDetailDialog(row: row),
  );
}

class _ProductionSummaryDetailDialog extends StatelessWidget {
  const _ProductionSummaryDetailDialog({required this.row});

  final ProductionSummaryRow row;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    Widget field(String label, String value) => Padding(
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

    final itemName = row.itemName.isEmpty ? row.outputItemName : row.itemName;

    return AlertDialog(
      title: Text(
        row.workOrderNumber.isEmpty
            ? l10n.reportsProductionorder
            : row.workOrderNumber,
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            field(l10n.fieldsItem, itemName.isEmpty ? '—' : itemName),
            field(
              l10n.reportsPlannedquantity,
              Formatters.number(row.plannedQuantity),
            ),
            field(
              l10n.reportsCompletedquantity,
              Formatters.number(row.completedQuantity),
            ),
            field(
              l10n.reportsScrappedquantity,
              Formatters.number(row.scrappedQuantity),
            ),
            field(l10n.fieldsStatus, row.status.isEmpty ? '—' : row.status),
            field(
              l10n.reportsProductiondate,
              row.productionDate.isEmpty
                  ? '—'
                  : Formatters.date(row.productionDate),
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
