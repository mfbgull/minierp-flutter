// Purchase detail dialog — opened by double-tapping a purchase row or
// via the F2/Enter shortcut. Fetches `GET /purchases/:id` (bare object,
// the same joined shape as the list rows) via
// [purchaseDetailProvider]; the grid row's hidden `id` cell supplies
// the purchase id. Renders the header (purchase no + item) and an info
// grid with quantity/cost tiles. Returns are entered from the purchase
// row menu (or the purchase-returns tab), not from this dialog.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/purchase.dart' show Purchase;
import '../../data/models/supplier.dart' show Supplier;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/detail_error.dart';
import '../../widgets/detail_labels.dart';
import '../../widgets/detail_rows.dart';
import '../../widgets/payment_history_section.dart'
    show PaymentHistorySection;
import '../suppliers/supplier_payment_modal.dart' show showSupplierPaymentModal;
import 'purchase_providers.dart';

/// Opens the detail dialog for [purchaseId].
Future<void> showPurchaseDetailDialog(
  BuildContext context, {
  required int purchaseId,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _PurchaseDetailDialog(purchaseId: purchaseId),
  );
}

class _PurchaseDetailDialog extends ConsumerWidget {
  const _PurchaseDetailDialog({required this.purchaseId});

  final int purchaseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(purchaseDetailProvider(purchaseId));
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 620),
        child: switch (detail) {
          AsyncData(:final value) => _DetailBody(detail: value),
          AsyncError(:final error) => DetailError(
            message: error is ApiError ? error.message : '$error',
            onRetry: () => ref.invalidate(purchaseDetailProvider(purchaseId)),
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

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.detail});

  final Purchase detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              detailSectionLabel(context, l10n.purchasesDetailstitle),
              const SizedBox(height: 2),
              Text(
                detail.purchaseNo,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                detail.itemName,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
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
                DetailInfoRows(
                  rows: [
                    (
                      l10n.purchasesPurchasedate,
                      Formatters.date(detail.purchaseDate),
                    ),
                    (l10n.fieldsItem, detail.itemName),
                    (
                      l10n.purchasesSuppliercol,
                      detailDash(detail.supplierName),
                    ),
                    (
                      l10n.purchasesWarehousecol,
                      detailDash(detail.warehouseName),
                    ),
                    (l10n.purchasesInvoicenumber, detailDash(detail.invoiceNo)),
                    if (detail.remarks != null && detail.remarks!.isNotEmpty)
                      (l10n.purchasesRemarks, detail.remarks!),
                  ],
                ),
                DetailTiles(
                  tiles: [
                    DetailTile(
                      l10n.purchasesQuantitycol,
                      Formatters.number(detail.quantity),
                    ),
                    DetailTile(
                      l10n.purchasesReturnqty,
                      Formatters.number(detail.returnedQuantity),
                    ),
                    DetailTile(
                      l10n.purchasesUnitcost,
                      Formatters.currency(detail.unitCost),
                    ),
                    DetailTile(
                      l10n.purchasesTotalcol,
                      Formatters.currency(detail.totalCost),
                      emphasize: true,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                PaymentHistorySection(
                  payments: ref.watch(purchasePaymentsProvider(detail.id)),
                  onRetry: () =>
                      ref.invalidate(purchasePaymentsProvider(detail.id)),
                ),
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
              if (detail.supplierId != null && detail.balanceAmount > 0)
                FilledButton.icon(
                  onPressed: () {
                    final supplier = Supplier(
                      id: detail.supplierId!,
                      supplierCode: '',
                      supplierName: detail.supplierName ?? '',
                    );
                    showSupplierPaymentModal(
                      context,
                      supplier: supplier,
                      initialPurchase: detail,
                    ).then((_) {
                      ref.invalidate(purchasePaymentsProvider(detail.id));
                      ref.invalidate(purchaseDetailProvider(detail.id));
                    });
                  },
                  icon: const Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 18,
                  ),
                  label: Text(l10n.suppliersRecordpayment),
                ),
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
}
