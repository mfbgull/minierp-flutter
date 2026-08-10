// Supplier-analysis detail dialog — port of the web report's supplier
// modal: purchase stats for the selected supplier.

import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/report.dart' show SupplierAnalysisRow;
import '../../l10n/app_localizations.dart';

Future<void> showSupplierAnalysisDetailDialog(
  BuildContext context, {
  required SupplierAnalysisRow supplier,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) =>
        _SupplierAnalysisDetailDialog(supplier: supplier),
  );
}

class _SupplierAnalysisDetailDialog extends StatelessWidget {
  const _SupplierAnalysisDetailDialog({required this.supplier});

  final SupplierAnalysisRow supplier;

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
      title: Text(supplier.supplierName),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            row(
              l10n.suppliersSuppliercode,
              supplier.supplierCode.isEmpty ? '—' : supplier.supplierCode,
            ),
            row(
              l10n.reportsTotalorders,
              Formatters.number(supplier.totalOrders),
            ),
            row(
              l10n.reportsTotalpurchasevalue,
              Formatters.currency(supplier.totalPurchaseValue),
            ),
            row(
              l10n.reportsAvgordervalue,
              Formatters.currency(supplier.averageOrderValue),
            ),
            row(
              l10n.reportsTotalitems,
              Formatters.number(supplier.totalItems),
            ),
            row(
              l10n.reportsLastpurchase,
              supplier.lastPurchaseDate.isEmpty
                  ? '—'
                  : Formatters.date(supplier.lastPurchaseDate),
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
