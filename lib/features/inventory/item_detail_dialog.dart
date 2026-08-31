// Item detail dialog — opened by double-tapping a row in the items grid
// (PORTING.md §6). Fetches `GET /inventory/items/:id` (bare object with
// the `stock_by_warehouse` breakdown) via [itemDetailProvider]; the grid
// row's hidden `id` cell supplies the item id.

import 'package:flutter/material.dart';
import 'package:minierp_app/core/theme/status_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/item.dart' show Item, SaleType;
import '../../data/models/stock_batch.dart' show BatchStatus, StockBatch;
import '../../data/repositories/api_result.dart' show ApiError, ApiFailure, ApiResult, ApiSuccess;
import '../../data/repositories/inventory_repository.dart'
    show ItemDetail, inventoryRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/detail_error.dart';
import '../../widgets/detail_labels.dart';
import '../../widgets/detail_rows.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_dialog.dart';
import 'inventory_providers.dart';
import 'item_form_dialog.dart';
import 'stock_ledger_dialog.dart';
import 'batch_management_screen.dart';
import 'package:minierp_app/core/theme/app_border_radius.dart';
import 'package:minierp_app/widgets/movable_dialog.dart';

/// Opens the read-only detail dialog for [itemId].
Future<void> showItemDetailDialog(BuildContext context, {required int itemId}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _ItemDetailDialog(itemId: itemId),
  );
}

class _ItemDetailDialog extends ConsumerWidget {
  const _ItemDetailDialog({required this.itemId});

  final int itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(itemDetailProvider(itemId));
    return MovableDialog(
      dialogId: 'item_detail',
      maxWidth: 560,
      maxHeight: 640,
      child: switch (detail) {
          AsyncData(:final value) => _DetailBody(detail: value),
          AsyncError(:final error) => DetailError(
            message: error is ApiError ? error.message : '$error',
            onRetry: () => ref.invalidate(itemDetailProvider(itemId)),
          ),
          _ => const SizedBox(
            width: 420,
            height: 240,
            child: Center(child: CircularProgressIndicator()),
          ),
        },
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.detail});

  final ItemDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final item = detail.item;

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
                    detailSectionLabel(context, l10n.inventoryItemdetails),
                    const SizedBox(height: 2),
                    Text(
                      item.itemName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.itemCode,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  StatusBadge(
                    status: item.isActive
                        ? l10n.statusActive
                        : l10n.statusInactive,
                    color: StatusColors.of(context).active(item.isActive),
                  ),
                  if (item.isBelowReorder) ...[
                    const SizedBox(height: 6),
                    StatusBadge(
                      status: l10n.inventoryLowstock,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ],
                ],
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
                  labelWidth: 140,
                  rows: [
                    (l10n.inventoryCategory, item.category ?? '—'),
                    (l10n.inventoryUom, item.unitOfMeasure),
                    (l10n.inventoryRack, item.rackNo ?? '—'),
                    (
                      l10n.inventorySaletype,
                      _saleTypeLabel(l10n, item.saleType),
                    ),
                  ],
                ),
                if (item.description?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 12),
                  detailSectionLabel(context, l10n.commonDescription),
                  const SizedBox(height: 2),
                  Text(item.description!),
                ],
                DetailTiles(
                  tiles: [
                    DetailTile(
                      l10n.inventoryStandardcost,
                      Formatters.currency(item.standardCost ?? 0),
                    ),
                    DetailTile(
                      l10n.inventorySellingprice,
                      Formatters.currency(item.standardSellingPrice ?? 0),
                    ),
                    DetailTile(
                      l10n.inventoryPurchaseprice,
                      Formatters.currency(item.purchasePrice ?? 0),
                    ),
                  ],
                ),
                if (_hasFlags(item)) ...[
                  const SizedBox(height: 14),
                  detailSectionLabel(context, l10n.inventoryItemtype),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (item.isRawMaterial)
                        _flagChip(context, l10n.inventoryRawmaterials),
                      if (item.isFinishedGood)
                        _flagChip(context, l10n.inventoryFinishedgoods),
                      if (item.isPurchased)
                        _flagChip(context, l10n.inventoryPurchased),
                      if (item.isManufactured)
                        _flagChip(context, l10n.inventoryManufacturedproducts),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                detailSectionLabel(context, l10n.inventoryTotalstock),
                const SizedBox(height: 4),
                Text(
                  '${Formatters.number(item.currentStock)} '
                  '${item.unitOfMeasure}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (item.reorderLevel != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${l10n.inventoryReorderlevel}: '
                    '${Formatters.number(item.reorderLevel!)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 12),
                detailSectionLabel(context, l10n.inventoryStockbywarehouse),
                const SizedBox(height: 6),
                _warehouseTable(context, l10n),
                if (item.hasExpiry) _BatchExpirySummary(item: item),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: () => _deleteItem(context, ref, detail.item),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: Text(l10n.commonDelete),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
              ),
              const Spacer(),
              Flexible(
                child: TextButton.icon(
                  onPressed: () => showStockLedgerDialog(
                    context,
                    itemId: detail.item.id,
                    itemLabel:
                        '${detail.item.itemCode} · ${detail.item.itemName}',
                  ),
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: Text(l10n.inventoryStockledger),
                ),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: () => showItemFormDialog(context, item: detail.item),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(l10n.inventoryEdit),
              ),
              if (detail.item.hasExpiry)
                TextButton.icon(
                  onPressed: () => showBatchManagementScreen(
                    context,
                    itemId: detail.item.id,
                  ),
                  icon: const Icon(Icons.layers_outlined, size: 18),
                  label: Text(l10n.manageBatches),
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

  static String _saleTypeLabel(AppLocalizations l10n, SaleType type) =>
      switch (type) {
        SaleType.packed => l10n.inventorySaletypePacked,
        SaleType.loose => l10n.inventorySaletypeLoose,
      };

  static bool _hasFlags(Item item) =>
      item.isRawMaterial ||
      item.isFinishedGood ||
      item.isPurchased ||
      item.isManufactured;

  static Future<void> _deleteItem(BuildContext context, WidgetRef ref, Item item) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.commonDelete,
      message: '${l10n.inventoryConfirmdelete} ${item.itemName}?',
      confirmLabel: l10n.commonDelete,
      cancelLabel: l10n.commonCancel,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;

    final result = await ref
        .read(inventoryRepositoryProvider)
        .delete(item.id);
    if (!context.mounted) return;
    result.fold(
      onSuccess: (_) {
        Navigator.of(context).pop();
        showAppToast(context, l10n.inventoryItemdeleted);
      },
      onFailure: (err) => showAppToast(context, err.message, isError: true),
    );
  }

  static Widget _flagChip(BuildContext context, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.10),
        borderRadius: AppBorderRadius.badge,
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: scheme.primary),
      ),
    );
  }

  Widget _warehouseTable(BuildContext context, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final rows = detail.stockByWarehouse;
    if (rows.isEmpty) {
      return Text(
        l10n.inventoryNoitemswarehouse,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      );
    }
    // The table's own total — the sum of the displayed rows, so it can
    // never contradict them even if the breakdown differs from
    // current_stock (unallocated stock, filtered rows).
    final tableTotal = rows.fold<num>(0, (sum, r) => sum + r.quantity);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: AppBorderRadius.smRadius,
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rows[i].warehouseName,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        Text(
                          rows[i].warehouseCode,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    Formatters.number(rows[i].quantity),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.inventoryTotalstock,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                Text(
                  Formatters.number(tableTotal),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Batch expiry summary for the item detail dialog — counts total /
/// near-expiry / expired batches and links to the batch manager.
class _BatchExpirySummary extends ConsumerWidget {
  const _BatchExpirySummary({required this.item});

  final Item item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return FutureBuilder<ApiResult<List<StockBatch>>>(
      future:
          ref.read(inventoryRepositoryProvider).getBatches(itemId: item.id),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final result = snap.data!;
        if (result case ApiFailure(:final error)) {
          return Text(
            error.message,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          );
        }
        final batches = (result as ApiSuccess<List<StockBatch>>).data;
        if (batches.isEmpty) return const SizedBox.shrink();
        final threshold = item.nearExpiryThresholdDays ?? 30;
        final total = batches.length;
        final near = batches
            .where(
              (b) =>
                  b.computeStatus(nearExpiryThresholdDays: threshold) ==
                  BatchStatus.nearExpiry,
            )
            .length;
        final expired = batches
            .where(
              (b) =>
                  b.computeStatus(nearExpiryThresholdDays: threshold) ==
                  BatchStatus.expired,
            )
            .length;
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.batchesSummary(expired, near, total),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: () =>
                    showBatchManagementScreen(context, itemId: item.id),
                icon: const Icon(Icons.layers_outlined, size: 16),
                label: Text(l10n.manageBatches),
              ),
            ],
          ),
        );
      },
    );
  }
}
