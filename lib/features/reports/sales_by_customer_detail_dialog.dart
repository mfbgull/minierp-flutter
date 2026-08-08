// Sales-by-customer detail dialog — port of the web report's customer
// modal: contact info + sales stats for the selected customer.

import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/report.dart' show SalesByCustomerRow;
import '../../l10n/app_localizations.dart';

Future<void> showSalesByCustomerDetailDialog(
  BuildContext context, {
  required SalesByCustomerRow customer,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) =>
        _SalesByCustomerDetailDialog(customer: customer),
  );
}

class _SalesByCustomerDetailDialog extends StatelessWidget {
  const _SalesByCustomerDetailDialog({required this.customer});

  final SalesByCustomerRow customer;

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
      title: Text(customer.customerName),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            row(l10n.fieldsCustomerCode, customer.customerCode),
            row(
              l10n.fieldsEmail,
              customer.email.isEmpty ? '—' : customer.email,
            ),
            row(
              l10n.fieldsPhone,
              customer.phone.isEmpty ? '—' : customer.phone,
            ),
            row(
              l10n.reportsTotalinvoices,
              Formatters.number(customer.totalInvoices),
            ),
            row(l10n.reportsItems, Formatters.number(customer.totalItems)),
            row(
              l10n.reportsAvgordervalue,
              Formatters.currency(customer.averageOrderValue),
            ),
            row(
              l10n.reportsLastpurchase,
              customer.lastPurchaseDate.isEmpty
                  ? '—'
                  : Formatters.date(customer.lastPurchaseDate),
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
                    Formatters.currency(customer.totalSales),
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
