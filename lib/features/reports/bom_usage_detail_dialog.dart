// BOM-usage detail dialog — port of the web report's BOM modal: parent
// item, usage count, last-used date, component count and status for the
// selected BOM.

import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/report.dart' show BomUsageRow;
import '../../l10n/app_localizations.dart';

Future<void> showBomUsageDetailDialog(
  BuildContext context, {
  required BomUsageRow row,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _BomUsageDetailDialog(row: row),
  );
}

class _BomUsageDetailDialog extends StatelessWidget {
  const _BomUsageDetailDialog({required this.row});

  final BomUsageRow row;

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

    return AlertDialog(
      title: Text(row.bomName),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            field(
              l10n.reportsParentitem,
              row.parentItemName.isEmpty ? '—' : row.parentItemName,
            ),
            field(l10n.reportsUsagecount, Formatters.number(row.usageCount)),
            field(
              l10n.reportsLastused,
              row.lastUsedDate == null || row.lastUsedDate!.isEmpty
                  ? '—'
                  : Formatters.date(row.lastUsedDate!),
            ),
            field(
              l10n.reportsTotalcomponents,
              Formatters.number(row.totalComponents),
            ),
            field(l10n.fieldsStatus, row.status.isEmpty ? '—' : row.status),
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
