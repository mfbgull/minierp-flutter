// Customer detail dialog — opened by double-tapping a row in the customers
// grid or via the F2/Enter keyboard shortcut (the same paths as the items
// grid). Fetches `GET /customers/:id` (bare object) via
// [customerDetailProvider]; the grid row's hidden `id` cell supplies the
// customer id.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/customer.dart' show Customer;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/detail_error.dart';
import '../../widgets/detail_labels.dart';
import '../../widgets/status_badge.dart';
import 'customer_form_dialog.dart';
import 'customer_ledger_dialog.dart';
import 'customer_providers.dart';

/// Opens the read-only detail dialog for [customerId].
Future<void> showCustomerDetailDialog(
  BuildContext context, {
  required int customerId,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _CustomerDetailDialog(customerId: customerId),
  );
}

class _CustomerDetailDialog extends ConsumerWidget {
  const _CustomerDetailDialog({required this.customerId});

  final int customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(customerDetailProvider(customerId));
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: switch (detail) {
          AsyncData(:final value) => _DetailBody(customer: value),
          AsyncError(:final error) => DetailError(
            message: error is ApiError ? error.message : '$error',
            onRetry: () => ref.invalidate(customerDetailProvider(customerId)),
          ),
          _ => const SizedBox(
            width: 420,
            height: 240,
            child: Center(child: CircularProgressIndicator()),
          ),
        },
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Non-empty addresses only, in display order (billing then shipping).
    final addresses = [
      if (customer.billingAddress?.isNotEmpty ?? false)
        customer.billingAddress!,
      if (customer.shippingAddress?.isNotEmpty ?? false)
        customer.shippingAddress!,
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    detailSectionLabel(context, l10n.customersCustomerdetails),
                    const SizedBox(height: 2),
                    Text(
                      customer.customerName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      customer.customerCode,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              StatusBadge(
                status: customer.isActive
                    ? l10n.statusActive
                    : l10n.statusInactive,
                color: customer.isActive ? Colors.green : Colors.blueGrey,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _infoGrid(context, l10n),
                _balanceRow(context, l10n),
                if (addresses.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  detailSectionLabel(context, l10n.customersAddress),
                  const SizedBox(height: 4),
                  for (var i = 0; i < addresses.length; i++) ...[
                    if (i > 0) const SizedBox(height: 4),
                    Text(addresses[i]),
                  ],
                ],
                if (customer.createdAt != null ||
                    customer.updatedAt != null) ...[
                  const SizedBox(height: 14),
                  _metaRow(context, l10n, customer),
                ],
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => showCustomerLedgerDialog(
                  context,
                  customerId: customer.id,
                  customerName: customer.customerName,
                ),
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                label: Text(l10n.customersLedger),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: () =>
                    showCustomerFormDialog(context, customer: customer),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(l10n.commonEdit),
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.commonClose),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _infoGrid(BuildContext context, AppLocalizations l10n) {
    // Payment terms: prefer the free-text terms; fall back to the days
    // number (e.g. "Net 30" vs a bare "30").
    final terms = customer.paymentTerms?.isNotEmpty == true
        ? customer.paymentTerms!
        : customer.paymentTermsDays != null
        ? '${Formatters.number(customer.paymentTermsDays!)} days'
        : null;
    final rows = <(String, String)>[
      (l10n.customersContactperson, detailDash(customer.contactPerson)),
      (l10n.customersPhone, detailDash(customer.phone)),
      (l10n.customersEmail, detailDash(customer.email)),
      (l10n.customersPaymentterms, detailDash(terms)),
      (
        l10n.customersOpeningbalance,
        customer.openingBalance == null
            ? '—'
            : Formatters.currency(customer.openingBalance!),
      ),
    ];
    return Column(
      children: [
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(width: 150, child: detailSectionLabel(context, label)),
                Expanded(
                  child: Text(
                    value,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _balanceRow(BuildContext context, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final tiles = <(String, String, bool)>[
      (
        l10n.customersCurrentbalance,
        Formatters.currency(customer.currentBalance),
        true,
      ),
      (
        l10n.customersCreditlimit,
        customer.creditLimit == null
            ? '—'
            : Formatters.currency(customer.creditLimit!),
        false,
      ),
      (
        l10n.customersCreditutilization,
        customer.creditUtilizationPercent == null
            ? '—'
            : '${Formatters.number(customer.creditUtilizationPercent!)}%',
        false,
      ),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          for (final (label, value, emphasize) in tiles)
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: emphasize
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: emphasize
                            ? (customer.currentBalance < 0
                                  ? scheme.error
                                  : null)
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _metaRow(BuildContext context, AppLocalizations l10n, Customer c) {
    final rows = <(String, String)>[
      if (c.createdAt != null)
        (l10n.fieldsCreatedat, Formatters.date(c.createdAt!)),
      if (c.updatedAt != null)
        (l10n.fieldsUpdatedat, Formatters.date(c.updatedAt!)),
    ];
    return Column(
      children: [
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                SizedBox(width: 150, child: detailSectionLabel(context, label)),
                Expanded(
                  child: Text(
                    value,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
