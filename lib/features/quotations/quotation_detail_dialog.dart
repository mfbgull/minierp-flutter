// Quotation detail dialog — opened by double-tapping a row in the
// quotations grid or via the F2/Enter keyboard shortcut. Fetches
// `GET /quotations/:id` (bare object with the `items` array) via
// [quotationDetailProvider]; the grid row's hidden `id` cell supplies
// the quotation id. Renders the header (quotation no + status), an info
// grid, the total tile, and the line-items table. Draft quotations get
// Edit + Delete; Accepted quotations get the Convert-to-SO action.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/quotation.dart' show QuotationDetail, QuotationItem;
import '../../data/repositories/api_result.dart'
    show ApiError, ApiFailure, ApiSuccess;
import '../../data/repositories/quotation_repository.dart'
    show quotationRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/detail_error.dart';
import '../../widgets/detail_labels.dart';
import '../../widgets/detail_rows.dart';
import '../../widgets/status_badge.dart';
import 'quotation_form_dialog.dart';
import 'quotation_providers.dart';
import 'quotation_status.dart';

/// Opens the read-only detail dialog for [quotationId].
Future<void> showQuotationDetailDialog(
  BuildContext context, {
  required int quotationId,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) =>
        _QuotationDetailDialog(quotationId: quotationId),
  );
}

class _QuotationDetailDialog extends ConsumerWidget {
  const _QuotationDetailDialog({required this.quotationId});

  final int quotationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(quotationDetailProvider(quotationId));
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 680),
        child: switch (detail) {
          AsyncData(:final value) => _DetailBody(detail: value),
          AsyncError(:final error) => DetailError(
            message: error is ApiError ? error.message : '$error',
            onRetry: () => ref.invalidate(quotationDetailProvider(quotationId)),
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

  final QuotationDetail detail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final expiry = detail.expiryDate;
    final (color, darkColor) = quotationStatusColors(detail.status);

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
                    detailSectionLabel(context, l10n.quotationsDetailstitle),
                    const SizedBox(height: 2),
                    Text(
                      detail.quotationNo,
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
                status: quotationStatusLabel(l10n, detail.status),
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
                    (l10n.quotationsCustomer, detail.customerName),
                    (
                      l10n.quotationsQuotationdate,
                      Formatters.date(detail.quotationDate),
                    ),
                    (
                      l10n.quotationsExpirydate,
                      expiry == null || expiry.isEmpty
                          ? '—'
                          : Formatters.date(expiry),
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
                    l10n.quotationsNoquotations,
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
                if (detail.terms?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 14),
                  detailSectionLabel(context, l10n.quotationsTerms),
                  const SizedBox(height: 4),
                  Text(detail.terms!),
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
                TextButton.icon(
                  onPressed: () =>
                      showQuotationFormDialog(context, detail: detail),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(l10n.commonEdit),
                ),
                const SizedBox(width: 4),
                _DeleteQuotationButton(detail: detail),
              ],
              // Accepted quotations convert into a Confirmed sales order
              // (the server also blocks already-Converted/Expired).
              if (detail.status == 'Accepted')
                _ConvertQuotationButton(detail: detail),
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

  final List<QuotationItem> items;

  static const _qtyWidth = 64.0;
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
          Expanded(child: Text(l10n.quotationsItem, style: style)),
          SizedBox(
            width: _ItemsTable._qtyWidth,
            child: Text(
              l10n.quotationsQuantity,
              style: style,
              textAlign: TextAlign.end,
            ),
          ),
          SizedBox(
            width: _ItemsTable._amountWidth,
            child: Text(
              l10n.quotationsUnitprice,
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

  final QuotationItem item;

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

/// Delete action for Draft quotations — confirms, DELETE /:id, then
/// invalidates the list provider and pops the dialog.
class _DeleteQuotationButton extends ConsumerStatefulWidget {
  const _DeleteQuotationButton({required this.detail});

  final QuotationDetail detail;

  @override
  ConsumerState<_DeleteQuotationButton> createState() =>
      _DeleteQuotationButtonState();
}

class _DeleteQuotationButtonState
    extends ConsumerState<_DeleteQuotationButton> {
  bool _deleting = false;

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.commonDelete,
      message: l10n.quotationsConfirmdelete,
      confirmLabel: l10n.commonDelete,
      cancelLabel: l10n.commonCancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _deleting = true);
    final result = await ref
        .read(quotationRepositoryProvider)
        .delete(widget.detail.id);
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        ref.invalidate(quotationsProvider);
        Navigator.of(context).pop();
        showAppToast(context, l10n.quotationsDeleted);
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

/// Convert-to-sales-order action for Accepted quotations — confirms,
/// POSTs /:id/convert, then invalidates the detail + list providers so
/// the badge flips to Converted and this button (plus Edit/Delete)
/// disappear. The server creates a Confirmed sales order from the
/// quotation's header + items.
class _ConvertQuotationButton extends ConsumerStatefulWidget {
  const _ConvertQuotationButton({required this.detail});

  final QuotationDetail detail;

  @override
  ConsumerState<_ConvertQuotationButton> createState() =>
      _ConvertQuotationButtonState();
}

class _ConvertQuotationButtonState
    extends ConsumerState<_ConvertQuotationButton> {
  bool _converting = false;

  Future<void> _convert() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.quotationsConverttoso,
      message: l10n.quotationsConvertconfirm,
      confirmLabel: l10n.quotationsConverttoso,
      cancelLabel: l10n.commonCancel,
    );
    if (!confirmed || !mounted) return;

    setState(() => _converting = true);
    final result = await ref
        .read(quotationRepositoryProvider)
        .convert(widget.detail.id);
    if (!mounted) return;

    switch (result) {
      case ApiSuccess(:final data):
        setState(() => _converting = false);
        ref.invalidate(quotationDetailProvider(widget.detail.id));
        ref.invalidate(quotationsProvider);
        showAppToast(
          context,
          l10n.quotationsConvertedmsg(data.salesOrderNo ?? ''),
        );
      case ApiFailure(:final error):
        setState(() => _converting = false);
        showAppToast(context, error.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return TextButton.icon(
      onPressed: _converting ? null : _convert,
      icon: _converting
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.swap_horiz, size: 18),
      label: Text(l10n.quotationsConverttoso),
      style: TextButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}
