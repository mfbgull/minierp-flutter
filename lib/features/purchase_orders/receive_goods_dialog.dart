// Receive-goods dialog — records a goods receipt against a submitted PO
// via `POST /purchase-orders/:id/receipts` (PORTING.md §14 / the server
// `purchaseOrderController.createGoodsReceipt` DTO).
//
// The form carries the header fields (receipt date, warehouse, optional
// remarks) plus per-line `received_quantity` inputs pre-filled with each
// item's pending balance (ordered − already received). On save it posts
// `{receipt_date, warehouse_id, remarks?, items: [{po_item_id,
// received_quantity}]}`; the server validates each quantity against the
// pending balance inside its transaction, posts the PURCHASE stock
// movement, and flips the PO status (Partially Received / Completed)
// itself. The dialog then invalidates the detail + receipts + list
// providers so the detail dialog beneath it refetches.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart' show isoDate;
import '../../core/utils/formatters.dart';
import '../../data/models/purchase_order.dart'
    show PurchaseOrderDetail, PurchaseOrderItem;
import '../../data/models/warehouse.dart' show Warehouse;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/purchase_order_repository.dart'
    show purchaseOrderRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/date_picker_helpers.dart' show pickDate;
import '../../widgets/form_field.dart';
import '../../widgets/form_helpers.dart' show numText;
import '../../widgets/searchable_select.dart';
import '../inventory/inventory_providers.dart' show warehousesProvider;
import 'purchase_order_providers.dart';

/// Opens the receive-goods dialog for [detail] (a non-Draft, non-Cancelled
/// PO with at least one line still pending). Returns after the receipt is
/// recorded or the user cancels.
Future<void> showReceiveGoodsDialog(
  BuildContext context, {
  required PurchaseOrderDetail detail,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => ReceiveGoodsDialog(detail: detail),
  );
}

/// One receivable line — the PO item plus its received-qty controller.
class _ReceiveLine {
  _ReceiveLine({
    required this.item,
    required this.pendingQuantity,
    required this.controller,
  });

  final PurchaseOrderItem item;
  final num pendingQuantity;
  final TextEditingController controller;

  num get receivedQuantity => double.tryParse(controller.text) ?? 0;

  void dispose() => controller.dispose();
}

class ReceiveGoodsDialog extends ConsumerStatefulWidget {
  const ReceiveGoodsDialog({super.key, required this.detail});

  final PurchaseOrderDetail detail;

  @override
  ConsumerState<ReceiveGoodsDialog> createState() => _ReceiveGoodsDialogState();
}

class _ReceiveGoodsDialogState extends ConsumerState<ReceiveGoodsDialog> {
  final _formKey = GlobalKey<FormState>();
  final List<_ReceiveLine> _lines = [];

  int? _warehouseId;
  late DateTime _receiptDate;
  TextEditingController? _remarksController;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _warehouseId = widget.detail.warehouseId;
    _receiptDate = DateTime.now();
    _remarksController = TextEditingController();
    for (final item in widget.detail.items) {
      final received = item.receivedQuantity ?? 0;
      final pending = item.quantity - received;
      if (pending > 0) {
        _lines.add(
          _ReceiveLine(
            item: item,
            pendingQuantity: pending,
            // Pre-fill the full pending balance — receiving in full is
            // the common case; partial receipt is a simple edit.
            controller: TextEditingController(text: numText(pending)),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    for (final line in _lines) {
      line.dispose();
    }
    _remarksController?.dispose();
    super.dispose();
  }

  List<_ReceiveLine> get _filledLines =>
      _lines.where((line) => line.receivedQuantity > 0).toList();

  Future<void> _pickDate() async {
    final picked = await pickDate(context, initialDate: _receiptDate);
    if (picked == null || !mounted) return;
    setState(() => _receiptDate = picked);
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_warehouseId == null) {
      setState(() => _error = l10n.purchaseordersErrorWarehouserequired);
      return;
    }
    if (_filledLines.isEmpty) {
      setState(() => _error = l10n.purchaseordersErrorReceiveditemsrequired);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final remarks = _remarksController?.text.trim() ?? '';
    final result = await ref
        .read(purchaseOrderRepositoryProvider)
        .createReceipt(widget.detail.id, {
          'receipt_date': isoDate(_receiptDate),
          'warehouse_id': _warehouseId,
          if (remarks.isNotEmpty) 'remarks': remarks,
          'items': [
            for (final line in _filledLines)
              {
                'po_item_id': line.item.id,
                'received_quantity': line.receivedQuantity,
              },
          ],
        });
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        ref.invalidate(purchaseOrdersProvider);
        ref.invalidate(purchaseOrderDetailProvider(widget.detail.id));
        ref.invalidate(purchaseOrderReceiptsProvider(widget.detail.id));
        Navigator.of(context).pop();
        showAppToast(context, l10n.purchaseordersReceiptsaved);
      case ApiFailure(:final error):
        setState(() {
          _saving = false;
          _error = error.message;
        });
    }
  }

  InputDecoration _decoration() =>
      const InputDecoration(isDense: true, border: OutlineInputBorder());

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final warehouses =
        ref.watch(warehousesProvider).valueOrNull ?? const <Warehouse>[];
    final warehouseIds = [for (final w in warehouses) w.id];

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 680),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  l10n.purchaseordersReceivegoods,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.fieldsWarehouse,
                              required: true,
                              child: SearchableSelect<int>(
                                items: warehouseIds,
                                selected: _warehouseId,
                                labelBuilder: (id) {
                                  final match = warehouses.where(
                                    (w) => w.id == id,
                                  );
                                  final warehouse = match.isEmpty
                                      ? null
                                      : match.first;
                                  return warehouse == null
                                      ? '$id'
                                      : '${warehouse.warehouseCode} — '
                                            '${warehouse.warehouseName ?? ''}';
                                },
                                onChanged: (value) =>
                                    setState(() => _warehouseId = value),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.purchaseordersReceiptdate,
                              required: true,
                              child: SizedBox(
                                height: 44,
                                child: OutlinedButton.icon(
                                  onPressed: _saving ? null : _pickDate,
                                  icon: const Icon(
                                    Icons.calendar_today_outlined,
                                    size: 16,
                                  ),
                                  label: Text(
                                    Formatters.date(isoDate(_receiptDate)),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      FormFieldShell(
                        label: l10n.fieldsNotes,
                        child: TextFormField(
                          controller: _remarksController,
                          enabled: !_saving,
                          minLines: 2,
                          maxLines: 3,
                          decoration: _decoration(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l10n.purchasesItemscard,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 4),
                      for (var i = 0; i < _lines.length; i++) ...[
                        _lineRow(l10n, i),
                        if (i < _lines.length - 1) const SizedBox(height: 8),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
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
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: Text(l10n.commonCancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.inventory_2_outlined, size: 18),
                      label: Text(l10n.purchaseordersReceivegoods),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _lineRow(AppLocalizations l10n, int index) {
    final line = _lines[index];
    final scheme = Theme.of(context).colorScheme;
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                line.item.itemName,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (line.item.itemCode.isNotEmpty)
                Text(line.item.itemCode, style: muted),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 64,
          child: Text(
            '${l10n.purchaseordersOrdered}: ${Formatters.number(line.item.quantity)}',
            textAlign: TextAlign.end,
            style: muted,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 64,
          child: Text(
            '${l10n.purchaseordersPending}: '
            '${Formatters.number(line.pendingQuantity)}',
            textAlign: TextAlign.end,
            style: muted,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 96,
          child: TextFormField(
            controller: line.controller,
            enabled: !_saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _decoration(),
            validator: (value) {
              final qty = double.tryParse(value ?? '') ?? -1;
              if (qty <= 0) return l10n.commonRequired;
              if (qty > line.pendingQuantity) {
                return l10n.purchaseordersErrorQtyexceeds;
              }
              return null;
            },
            onChanged: (_) => setState(() {}),
          ),
        ),
      ],
    );
  }
}
