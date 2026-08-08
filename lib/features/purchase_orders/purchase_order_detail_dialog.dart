// Purchase order detail dialog — opened by double-tapping a row in the
// purchase orders grid or via the F2/Enter keyboard shortcut. Fetches
// `GET /purchase-orders/:id` (bare object with the `items` array) via
// [purchaseOrderDetailProvider]; the grid row's hidden `id` cell supplies
// the PO id. Renders the header (PO no + status), an info grid, total /
// balance tiles, and the line-items table.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../core/utils/po_status.dart';
import '../../data/models/purchase_order.dart'
    show PurchaseOrderDetail, PurchaseOrderItem;
import '../../data/repositories/api_result.dart'
    show ApiError, ApiFailure, ApiSuccess;
import '../../data/repositories/purchase_order_repository.dart'
    show purchaseOrderRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/detail_error.dart';
import '../../widgets/detail_labels.dart';
import '../../widgets/detail_rows.dart';
import '../../widgets/status_badge.dart';
import 'purchase_order_form_dialog.dart';
import 'purchase_order_providers.dart';

/// Opens the read-only detail dialog for [poId].
Future<void> showPurchaseOrderDetailDialog(
  BuildContext context, {
  required int poId,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _PurchaseOrderDetailDialog(poId: poId),
  );
}

class _PurchaseOrderDetailDialog extends ConsumerWidget {
  const _PurchaseOrderDetailDialog({required this.poId});

  final int poId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(purchaseOrderDetailProvider(poId));
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 680),
        child: switch (detail) {
          AsyncData(:final value) => _DetailBody(detail: value),
          AsyncError(:final error) => DetailError(
            message: error is ApiError ? error.message : '$error',
            onRetry: () => ref.invalidate(purchaseOrderDetailProvider(poId)),
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

  final PurchaseOrderDetail detail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final expected = detail.expectedDeliveryDate;
    final (color, darkColor) = poStatusColors(detail.status);

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
                    detailSectionLabel(
                      context,
                      l10n.purchaseordersDetailstitle,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail.poNo,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      detail.supplierName,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              StatusBadge(
                status: poStatusLabel(l10n, detail.status),
                color: color,
                darkColor: darkColor,
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
                    (l10n.purchasesSuppliercol, detail.supplierName),
                    (l10n.commonDate, Formatters.date(detail.poDate)),
                    (
                      l10n.purchaseordersExpecteddelivery,
                      expected == null || expected.isEmpty
                          ? '—'
                          : Formatters.date(expected),
                    ),
                    (
                      l10n.purchasesWarehousecol,
                      detailDash(detail.warehouseName),
                    ),
                  ],
                ),
                DetailTiles(
                  tiles: [
                    DetailTile(
                      l10n.commonTotal,
                      Formatters.currency(detail.totalAmount),
                      emphasize: true,
                    ),
                    DetailTile(
                      l10n.purchaseordersBalance,
                      Formatters.currency(detail.balanceAmount),
                    ),
                  ],
                ),
                if (detail.items.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  detailSectionLabel(context, l10n.purchasesItemscard),
                  const SizedBox(height: 6),
                  _ItemsTable(items: detail.items),
                ] else ...[
                  const SizedBox(height: 14),
                  Text(
                    l10n.purchaseordersNoitems,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (detail.notes?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 14),
                  detailSectionLabel(context, l10n.purchasesRemarks),
                  const SizedBox(height: 4),
                  Text(detail.notes!),
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
              if (detail.status == 'Draft') ...[
                _SubmitPoButton(detail: detail),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: () =>
                      showPurchaseOrderFormDialog(context, detail: detail),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(l10n.commonEdit),
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

class _ItemsTable extends StatelessWidget {
  const _ItemsTable({required this.items});

  final List<PurchaseOrderItem> items;

  static const _qtyWidth = 64.0;
  static const _uomWidth = 56.0;
  static const _amountWidth = 96.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _HeaderRow(),
          for (final item in items) ...[
            const Divider(height: 1),
            _ItemRow(item: item),
          ],
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
      letterSpacing: 0.3,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(l10n.purchasesItemcol, style: style)),
          SizedBox(
            width: _ItemsTable._qtyWidth,
            child: Text(
              l10n.purchasesQuantitycol,
              style: style,
              textAlign: TextAlign.end,
            ),
          ),
          SizedBox(
            width: _ItemsTable._uomWidth,
            child: Text(
              l10n.fieldsUnit,
              style: style,
              textAlign: TextAlign.end,
            ),
          ),
          SizedBox(
            width: _ItemsTable._amountWidth,
            child: Text(
              l10n.purchasesUnitcost,
              style: style,
              textAlign: TextAlign.end,
            ),
          ),
          SizedBox(
            width: _ItemsTable._amountWidth,
            child: Text(
              l10n.commonTotal,
              style: style,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});

  final PurchaseOrderItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final amountStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final unitPrice = item.unitPrice;
    final quantity = item.quantity;
    final amount = item.amount ?? quantity * unitPrice;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.itemName, style: amountStyle),
                if (item.itemCode.isNotEmpty) Text(item.itemCode, style: muted),
              ],
            ),
          ),
          SizedBox(
            width: _ItemsTable._qtyWidth,
            child: Text(
              Formatters.number(quantity),
              style: amountStyle,
              textAlign: TextAlign.end,
            ),
          ),
          SizedBox(
            width: _ItemsTable._uomWidth,
            child: Text(
              item.unitOfMeasure,
              style: amountStyle,
              textAlign: TextAlign.end,
            ),
          ),
          SizedBox(
            width: _ItemsTable._amountWidth,
            child: Text(
              Formatters.currency(unitPrice),
              style: amountStyle,
              textAlign: TextAlign.end,
            ),
          ),
          SizedBox(
            width: _ItemsTable._amountWidth,
            child: Text(
              Formatters.currency(amount),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

/// Submit action for Draft POs — confirms, POSTs /:id/status, then
/// invalidates the detail + list providers (the dialog refetches, the
/// badge flips to Submitted and this button, plus Edit, disappear).
class _SubmitPoButton extends ConsumerStatefulWidget {
  const _SubmitPoButton({required this.detail});

  final PurchaseOrderDetail detail;

  @override
  ConsumerState<_SubmitPoButton> createState() => _SubmitPoButtonState();
}

class _SubmitPoButtonState extends ConsumerState<_SubmitPoButton> {
  bool _submitting = false;

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.commonSubmit,
      message: l10n.purchaseordersSubmitconfirm,
      confirmLabel: l10n.commonSubmit,
    );
    if (!confirmed || !mounted) return;

    setState(() => _submitting = true);
    final repo = ref.read(purchaseOrderRepositoryProvider);
    final result = await repo.updateStatus(widget.detail.id, 'Submitted');
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        setState(() => _submitting = false);
        ref.invalidate(purchaseOrderDetailProvider(widget.detail.id));
        ref.invalidate(purchaseOrdersProvider);
        showAppToast(context, l10n.purchaseordersSubmittedsuccess);
      case ApiFailure(:final error):
        setState(() => _submitting = false);
        showAppToast(context, error.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return FilledButton.icon(
      onPressed: _submitting ? null : _submit,
      icon: _submitting
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.send_outlined, size: 18),
      label: Text(l10n.commonSubmit),
    );
  }
}
