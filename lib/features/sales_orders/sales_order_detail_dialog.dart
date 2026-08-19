// Sales order detail dialog — opened by double-tapping a row in the sales
// orders grid or via the F2/Enter keyboard shortcut. Fetches
// `GET /sales-orders/:id` (bare object with the `items` array) via
// [salesOrderDetailProvider]; the grid row's hidden `id` cell supplies
// the SO id. Renders the header (SO no + status), an info grid, the
// total tile, and the line-items table. Draft SOs get Edit + Delete;
// every status gets Print A4.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../core/utils/print_utils.dart' show printPdfBytes;
import '../../core/utils/so_status.dart';
import '../../data/models/sales_order.dart'
    show SalesOrderDetail, SalesOrderItem;
import '../../data/repositories/api_result.dart'
    show ApiError, ApiFailure, ApiSuccess;
import '../../data/repositories/sales_order_repository.dart'
    show salesOrderRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/detail_error.dart';
import '../../widgets/detail_labels.dart';
import '../../widgets/detail_rows.dart';
import '../../widgets/status_badge.dart';
import 'sales_order_form_dialog.dart';
import 'sales_order_pdf.dart' show buildA4SalesOrderPdf;
import 'sales_order_providers.dart';
import 'package:minierp_app/core/theme/app_border_radius.dart';

/// Opens the read-only detail dialog for [soId].
Future<void> showSalesOrderDetailDialog(
  BuildContext context, {
  required int soId,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _SalesOrderDetailDialog(soId: soId),
  );
}

class _SalesOrderDetailDialog extends ConsumerWidget {
  const _SalesOrderDetailDialog({required this.soId});

  final int soId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(salesOrderDetailProvider(soId));
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 680),
        child: switch (detail) {
          AsyncData(:final value) => _DetailBody(detail: value),
          AsyncError(:final error) => DetailError(
            message: error is ApiError ? error.message : '$error',
            onRetry: () => ref.invalidate(salesOrderDetailProvider(soId)),
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

  final SalesOrderDetail detail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final delivery = detail.deliveryDate;
    final color = soStatusColors(Theme.of(context).colorScheme, detail.status);

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
                    detailSectionLabel(context, l10n.salesordersDetailstitle),
                    const SizedBox(height: 2),
                    Text(
                      detail.soNo,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      detail.customerName,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              StatusBadge(
                status: soStatusLabel(l10n, detail.status),
                color: color,
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
                    (l10n.salesordersCustomer, detail.customerName),
                    (l10n.salesordersSodate, Formatters.date(detail.soDate)),
                    (
                      l10n.salesordersDeliverydate,
                      delivery == null || delivery.isEmpty
                          ? '—'
                          : Formatters.date(delivery),
                    ),
                    (l10n.fieldsWarehouse, detailDash(detail.warehouseName)),
                  ],
                ),
                DetailTiles(
                  tiles: [
                    DetailTile(
                      l10n.commonTotal,
                      Formatters.currency(detail.totalAmount),
                      emphasize: true,
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
                    l10n.salesordersNoitems,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (detail.notes?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 14),
                  detailSectionLabel(context, l10n.fieldsNotes),
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
          child: Wrap(
            // Draft packs Edit + Delete + Print A4 + Cancel + Close, which
            // overflows a fixed Row at this width — wrap so actions flow
            // to a second line instead of overflowing.
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            runSpacing: 4,
            children: [
              if (detail.status == 'Draft') ...[
                TextButton.icon(
                  onPressed: () =>
                      showSalesOrderFormDialog(context, detail: detail),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(l10n.commonEdit),
                ),
              ],
              if (detail.status == 'Draft') _DeleteSoButton(detail: detail),
              // Any order except Cancelled can be cancelled — the server
              // rejects an already-Cancelled order and reverses linked-
              // invoice stock for Invoiced/Completed.
              if (detail.status != 'Cancelled') _CancelSoButton(detail: detail),
              _PrintSalesOrderButton(detail: detail),
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

  final List<SalesOrderItem> items;

  static const _qtyWidth = 64.0;
  static const _amountWidth = 96.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: AppBorderRadius.smRadius,
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
          Expanded(child: Text(l10n.salesordersItem, style: style)),
          SizedBox(
            width: _ItemsTable._qtyWidth,
            child: Text(
              l10n.salesordersQuantity,
              style: style,
              textAlign: TextAlign.end,
            ),
          ),
          SizedBox(
            width: _ItemsTable._amountWidth,
            child: Text(
              l10n.salesordersUnitprice,
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

  final SalesOrderItem item;

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

/// Print A4 action — builds the PDF from the already-fetched detail (the
/// dialog IS the saved order, so unlike the edit form there is no
/// refetch) and opens the native print dialog, falling back to the
/// share/save-as-PDF sheet when the platform has no print backend (e.g.
/// some Linux setups). Available for every status.
class _PrintSalesOrderButton extends StatefulWidget {
  const _PrintSalesOrderButton({required this.detail});

  final SalesOrderDetail detail;

  @override
  State<_PrintSalesOrderButton> createState() => _PrintSalesOrderButtonState();
}

class _PrintSalesOrderButtonState extends State<_PrintSalesOrderButton> {
  bool _printing = false;

  Future<void> _print() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _printing = true);
    try {
      final bytes = await buildA4SalesOrderPdf(salesOrder: widget.detail);
      if (!mounted) return;
      await printPdfBytes(bytes, '${widget.detail.soNo}.pdf', context);
    } catch (error) {
      if (mounted) {
        showAppToast(context, '${l10n.errorsFailed}: $error', isError: true);
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return TextButton.icon(
      onPressed: _printing ? null : _print,
      icon: _printing
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.print_outlined, size: 18),
      label: Text(l10n.salesordersPrinta4),
    );
  }
}

/// Cancel action for non-Cancelled SOs — confirms, POSTs /:id/cancel,
/// then invalidates the list + detail providers so the badge flips to
/// Cancelled and this button (plus Edit/Delete) disappear.
class _CancelSoButton extends ConsumerStatefulWidget {
  const _CancelSoButton({required this.detail});

  final SalesOrderDetail detail;

  @override
  ConsumerState<_CancelSoButton> createState() => _CancelSoButtonState();
}

class _CancelSoButtonState extends ConsumerState<_CancelSoButton> {
  bool _cancelling = false;

  Future<void> _cancel() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.commonCancel,
      message: l10n.salesordersCancelconfirm,
      confirmLabel: l10n.commonCancel,
      cancelLabel: l10n.commonCancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _cancelling = true);
    final result = await ref
        .read(salesOrderRepositoryProvider)
        .cancel(widget.detail.id);
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        setState(() => _cancelling = false);
        ref.invalidate(salesOrderDetailProvider(widget.detail.id));
        ref.invalidate(salesOrdersProvider);
        showAppToast(context, l10n.salesordersCancelledmsg);
      case ApiFailure(:final error):
        setState(() => _cancelling = false);
        showAppToast(context, error.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return TextButton.icon(
      onPressed: _cancelling ? null : _cancel,
      icon: _cancelling
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.cancel_outlined, size: 18),
      label: Text(l10n.commonCancel),
      style: TextButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }
}

/// Delete action for Draft SOs — confirms, DELETE /:id, then invalidates
/// the list provider and pops the dialog.
class _DeleteSoButton extends ConsumerStatefulWidget {
  const _DeleteSoButton({required this.detail});

  final SalesOrderDetail detail;

  @override
  ConsumerState<_DeleteSoButton> createState() => _DeleteSoButtonState();
}

class _DeleteSoButtonState extends ConsumerState<_DeleteSoButton> {
  bool _deleting = false;

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.commonDelete,
      message: l10n.salesordersConfirmdelete,
      confirmLabel: l10n.commonDelete,
      cancelLabel: l10n.commonCancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _deleting = true);
    final result = await ref
        .read(salesOrderRepositoryProvider)
        .delete(widget.detail.id);
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        ref.invalidate(salesOrdersProvider);
        Navigator.of(context).pop();
        showAppToast(context, l10n.salesordersDeleted);
      case ApiFailure(:final error):
        setState(() => _deleting = false);
        showAppToast(context, error.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return TextButton.icon(
      onPressed: _deleting ? null : _delete,
      icon: _deleting
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.delete_outline, size: 18),
      label: Text(l10n.commonDelete),
      style: TextButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }
}
