// Supplier detail dialog — opened by double-tapping a row in the suppliers
// grid or via the F2/Enter keyboard shortcut (the same paths as the items
// and customers grids). Fetches `GET /suppliers/:id` (bare object) via
// [supplierDetailProvider]; the grid row's hidden `id` cell supplies the
// supplier id.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/supplier.dart' show Supplier;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/detail_error.dart';
import '../../widgets/detail_labels.dart';
import '../../widgets/status_badge.dart';
import 'supplier_form_dialog.dart';
import 'supplier_ledger_dialog.dart';
import 'supplier_providers.dart';

/// Opens the read-only detail dialog for [supplierId].
Future<void> showSupplierDetailDialog(
  BuildContext context, {
  required int supplierId,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _SupplierDetailDialog(supplierId: supplierId),
  );
}

class _SupplierDetailDialog extends ConsumerWidget {
  const _SupplierDetailDialog({required this.supplierId});

  final int supplierId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(supplierDetailProvider(supplierId));
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: switch (detail) {
          AsyncData(:final value) => _DetailBody(supplier: value),
          AsyncError(:final error) => DetailError(
            message: error is ApiError ? error.message : '$error',
            onRetry: () => ref.invalidate(supplierDetailProvider(supplierId)),
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
  const _DetailBody({required this.supplier});

  final Supplier supplier;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

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
                    detailSectionLabel(context, l10n.suppliersSupplierdetails),
                    const SizedBox(height: 2),
                    Text(
                      supplier.supplierName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      supplier.supplierCode,
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
                status: supplier.isActive
                    ? l10n.statusActive
                    : l10n.statusInactive,
                color: supplier.isActive ? Colors.green : Colors.blueGrey,
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
                if (supplier.address?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 14),
                  detailSectionLabel(context, l10n.suppliersAddress),
                  const SizedBox(height: 4),
                  Text(supplier.address!),
                ],
                if (supplier.notes?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 14),
                  detailSectionLabel(context, l10n.suppliersNotes),
                  const SizedBox(height: 4),
                  Text(supplier.notes!),
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
                onPressed: () => showSupplierLedgerDialog(
                  context,
                  supplierId: supplier.id,
                  supplierName: supplier.supplierName,
                ),
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                label: Text(l10n.suppliersLedger),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: () =>
                    showSupplierFormDialog(context, supplier: supplier),
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
    final rows = <(String, String)>[
      (l10n.suppliersContactperson, detailDash(supplier.contactPerson)),
      (l10n.suppliersPhone, detailDash(supplier.phone)),
      (l10n.suppliersEmail, detailDash(supplier.email)),
      (l10n.suppliersPaymentterms, detailDash(supplier.paymentTerms)),
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
        l10n.suppliersBalance,
        Formatters.currency(supplier.currentBalance ?? 0),
        true,
      ),
      (
        l10n.suppliersCreditutilization,
        supplier.creditUtilizationPercent == null
            ? '—'
            : '${Formatters.number(supplier.creditUtilizationPercent!)}%',
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
                            ? ((supplier.currentBalance ?? 0) < 0
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
}
