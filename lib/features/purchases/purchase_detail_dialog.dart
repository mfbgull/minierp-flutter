// Purchase detail dialog — opened by double-tapping a purchase row or
// via the F2/Enter shortcut. Fetches `GET /purchases/:id` (bare object,
// the same joined shape as the list rows) via
// [purchaseDetailProvider]; the grid row's hidden `id` cell supplies
// the purchase id. Renders the header (purchase no + item), an info
// grid, quantity/cost tiles, and a Process Return action that opens the
// return-processing dialog (hidden when nothing is returnable).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/purchase.dart' show Purchase;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/detail_error.dart';
import '../../widgets/detail_labels.dart';
import '../../widgets/detail_rows.dart';
import 'process_return_dialog.dart';
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

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.detail});

  final Purchase detail;

  @override
  Widget build(BuildContext context) {
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
              if (detail.returnableQty > 0) ...[
                FilledButton.icon(
                  onPressed: () =>
                      showProcessReturnDialog(context, purchase: detail),
                  icon: const Icon(Icons.assignment_return_outlined, size: 18),
                  label: Text(l10n.purchasesProcessreturn),
                ),
                const SizedBox(width: 4),
              ],
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
