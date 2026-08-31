// Purchase return entry form (§8.3) — the multi-line return form opened
// after a source is chosen (the source picker, or directly from the
// purchases / PO row menus where the source is already known). Loads the
// source document's lines (one per direct purchase; one per received PO
// item) with their returnable quantities, collects per-line return
// quantities, a user-selectable return date, and posts
// `POST /purchase-returns`. The warehouse is **not** user-selectable: a
// return reduces stock from the source document's warehouse (where the
// goods were received), so it is fixed and shown read-only. The server
// re-validates the caps, posts the negative stock movements, the GL
// reversal and the supplier credit note — the entry flow stays
// server-authoritative.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart' show isoDate;
import '../../core/utils/formatters.dart';
import '../../data/models/purchase.dart' show Purchase;
import '../../data/models/purchase_order.dart' show PurchaseOrderDetail;
import '../../data/models/warehouse.dart' show Warehouse;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/purchase_repository.dart'
    show purchaseRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import 'package:minierp_app/widgets/movable_dialog.dart';
import '../../widgets/date_picker.dart' show pickDate;
import '../../widgets/form_field.dart' show FormFieldShell;
import '../../widgets/form_helpers.dart'
    show ErrorBanner, formInputDecoration, submitOnEnter;
import '../../widgets/searchable_select.dart' show SearchableSelect;
import '../inventory/inventory_providers.dart'
    show itemDetailProvider, warehousesProvider;
import '../purchase_orders/purchase_order_providers.dart'
    show purchaseOrderDetailProvider, purchaseOrdersProvider;
import 'purchase_providers.dart'
    show purchaseDetailProvider, purchasesProvider;
import 'purchase_return_providers.dart'
    show filteredPurchaseReturnsProvider, purchaseReturnsProvider;

/// The source-document kind a return is created from.
enum ReturnSourceType {
  purchase,
  purchaseOrder;

  /// The server's `source_type` wire value (`PurchaseReturnModel.create`).
  String get apiValue =>
      this == ReturnSourceType.purchase ? 'PURCHASE' : 'PURCHASE_ORDER';

  String label(AppLocalizations l10n) => switch (this) {
    ReturnSourceType.purchase => l10n.purchasesReturnsourcedirect,
    ReturnSourceType.purchaseOrder => l10n.purchasesReturnsourcepo,
  };
}

/// A source document selection — what the picker pops with and what the
/// form consumes. [warehouseId] carries the source document's warehouse
/// — the fixed warehouse a return reduces stock from (no picker).
class ReturnSource {
  const ReturnSource.purchase({
    required this.id,
    required this.no,
    this.warehouseId,
  }) : type = ReturnSourceType.purchase;

  const ReturnSource.purchaseOrder({
    required this.id,
    required this.no,
    this.warehouseId,
  }) : type = ReturnSourceType.purchaseOrder;

  final ReturnSourceType type;
  final int id;
  final String no;

  /// The source document's warehouse (nullable on PO list rows).
  final int? warehouseId;
}

/// Opens the return entry form for [source].
Future<void> showPurchaseReturnFormDialog(
  BuildContext context, {
  required ReturnSource source,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _PurchaseReturnFormDialog(source: source),
  );
}

/// One source line's return data, derived from the source detail.
class _ReturnLine {
  const _ReturnLine({
    required this.sourceItemId,
    required this.itemId,
    required this.itemName,
    required this.unitOfMeasure,
    required this.unitCost,
    required this.originalQty,
    required this.returnedQty,
    required this.returnableQty,
  });

  /// `purchases.id` (direct purchase) | `purchase_order_items.id` (PO).
  final int sourceItemId;
  final int itemId;
  final String itemName;
  final String unitOfMeasure;
  final num unitCost;
  final num originalQty;
  final num returnedQty;
  final num returnableQty;
}

class _PurchaseReturnFormDialog extends ConsumerStatefulWidget {
  const _PurchaseReturnFormDialog({required this.source});

  final ReturnSource source;

  @override
  ConsumerState<_PurchaseReturnFormDialog> createState() =>
      _PurchaseReturnFormDialogState();
}

class _PurchaseReturnFormDialogState
    extends ConsumerState<_PurchaseReturnFormDialog> {
  final _reasonController = TextEditingController();

  /// Per-line return-qty controllers, keyed by source item id — created
  /// lazily once the source detail loads, disposed on close.
  final Map<int, TextEditingController> _qtyControllers = {};

  DateTime _returnDate = DateTime.now();
  int? _warehouseId;

  /// Whether the receipt warehouse no longer holds the returned stock
  /// (transferred out since receipt) — only then is the warehouse
  /// selectable. Decided per quantity entry from live item-detail stock.
  bool _warehouseNeedsPick = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reasonController.dispose();
    for (final controller in _qtyControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await pickDate(context, initialDate: _returnDate);
    if (picked != null) setState(() => _returnDate = picked);
  }

  List<_ReturnLine> _linesFor(Object detail) {
    switch (widget.source.type) {
      case ReturnSourceType.purchase:
        final purchase = detail as Purchase;
        return [
          _ReturnLine(
            sourceItemId: purchase.id,
            itemId: purchase.itemId,
            itemName: purchase.itemName,
            unitOfMeasure: purchase.unitOfMeasure,
            unitCost: purchase.unitCost,
            originalQty: purchase.quantity,
            returnedQty: purchase.returnedQuantity,
            returnableQty: purchase.returnableQty,
          ),
        ];
      case ReturnSourceType.purchaseOrder:
        final po = detail as PurchaseOrderDetail;
        return [
          for (final item in po.items)
            if ((item.receivedQuantity ?? 0) > (item.returnedQuantity ?? 0))
              _ReturnLine(
                sourceItemId: item.id,
                itemId: item.itemId,
                itemName: item.itemName,
                unitOfMeasure: item.unitOfMeasure,
                unitCost: item.unitPrice,
                originalQty: item.receivedQuantity ?? 0,
                returnedQty: item.returnedQuantity ?? 0,
                returnableQty:
                    (item.receivedQuantity ?? 0) - (item.returnedQuantity ?? 0),
              ),
        ];
    }
  }

  TextEditingController _controllerFor(int sourceItemId) =>
      _qtyControllers.putIfAbsent(
        sourceItemId,
        () => TextEditingController(),
      );

  num _lineQty(_ReturnLine line) =>
      num.tryParse(_controllerFor(line.sourceItemId).text.trim()) ?? 0;

  /// The true per-line cap — the source document's remaining returnable
  /// quantity clamped to the stock actually on hand in the effective
  /// warehouse (the receipt warehouse while locked; the picked warehouse
  /// once stock moved). Keeps the "Available" column and the qty
  /// validation honest: a return can't remove more stock than exists, so
  /// quantities the server would reject (e.g. units written off by a
  /// physical count since receipt) are flagged up front instead of
  /// failing on submit with an "Insufficient stock" error.
  num _effectiveCap(_ReturnLine line, Map<int, Map<int, num>> stock) {
    final returnable = line.returnableQty;
    final warehouseId = _warehouseId;
    if (warehouseId == null) return returnable;
    final onHand = stock[line.itemId]?[warehouseId] ?? 0;
    if (onHand <= 0) return 0;
    final cap = onHand < returnable ? onHand : returnable;
    return cap < 0 ? 0 : cap;
  }

  Future<void> _submit(Object detail) async {
    final l10n = AppLocalizations.of(context)!;
    if (_warehouseId == null) {
      setState(() => _error = l10n.commonRequired);
      return;
    }

    final lines = _linesFor(detail);
    final stock = _stockFor(lines);
    final items = <({int sourceItemId, num quantity})>[];
    for (final line in lines) {
      final text = _controllerFor(line.sourceItemId).text.trim();
      if (text.isEmpty) continue;
      final qty = num.tryParse(text);
      if (qty == null || qty <= 0) {
        setState(() => _error = l10n.purchasesReturnqtyinvalid);
        return;
      }
      final cap = _effectiveCap(line, stock);
      if (qty > cap + 0.0001) {
        setState(
          () => _error =
              '${l10n.purchasesReturnqtyexceeds} '
              '(${line.itemName}: ${Formatters.number(cap)} '
              '${l10n.purchasesAvailable})',
        );
        return;
      }
      items.add((sourceItemId: line.sourceItemId, quantity: qty));
    }
    if (items.isEmpty) {
      setState(() => _error = l10n.purchasesReturnqtyinvalid);
      return;
    }

    // The warehouse is the receipt warehouse unless stock moved — when a
    // pick was required, the chosen warehouse must actually hold the
    // returned quantities (the server re-validates too).
    if (_warehouseNeedsPick) {
      final missing = lines.any((line) {
        final qty = _lineQty(line);
        if (qty <= 0) return false;
        final rows = stock[line.itemId];
        final available = rows == null
            ? 0
            : rows[_warehouseId] ?? 0;
        return available < qty - 0.0001;
      });
      if (missing) {
        setState(() => _error = l10n.purchasesReturnwarehousenostock);
        return;
      }
    }

    final totalAmount = items.fold<num>(0, (sum, item) {
      final line = lines.firstWhere((l) => l.sourceItemId == item.sourceItemId);
      return sum + item.quantity * line.unitCost;
    });

    setState(() {
      _busy = true;
      _error = null;
    });

    final result = await ref.read(purchaseRepositoryProvider).createReturn(
      returnDate: isoDate(_returnDate),
      sourceType: widget.source.type.apiValue,
      sourceId: widget.source.id,
      warehouseId: _warehouseId!,
      reason: _reasonController.text,
      items: items,
    );
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        ref.invalidate(purchaseReturnsProvider);
        ref.invalidate(filteredPurchaseReturnsProvider);
        ref.invalidate(purchasesProvider);
        ref.invalidate(purchaseOrdersProvider);
        ref.invalidate(purchaseDetailProvider(widget.source.id));
        ref.invalidate(purchaseOrderDetailProvider(widget.source.id));
        showAppToast(
          context,
          '${l10n.purchasesReturnprocessed} — '
          '${Formatters.currency(totalAmount)}',
        );
        Navigator.of(context).pop();
      case ApiFailure(:final error):
        setState(() {
          _busy = false;
          _error = error.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = switch (widget.source.type) {
      ReturnSourceType.purchase =>
        ref.watch(purchaseDetailProvider(widget.source.id)),
      ReturnSourceType.purchaseOrder =>
        ref.watch(purchaseOrderDetailProvider(widget.source.id)),
    };

    return detail.when(
      loading: () => const Dialog(
        child: SizedBox(
          width: 380,
          height: 200,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (error, _) => Dialog(
        child: SizedBox(
          width: 380,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$error', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(AppLocalizations.of(context)!.commonClose),
                ),
              ],
            ),
          ),
        ),
      ),
      data: (detail) => _buildForm(context, detail),
    );
  }

  Widget _buildForm(BuildContext context, Object detail) {
    final l10n = AppLocalizations.of(context)!;
    final warehouses =
        ref.watch(warehousesProvider).valueOrNull ?? const [];
    final lines = _linesFor(detail);
    _warehouseId ??= widget.source.warehouseId ??
        (detail is Purchase
            ? detail.warehouseId
            : detail is PurchaseOrderDetail
                ? detail.warehouseId
                : null);
    // Live stock per line — decide whether the receipt warehouse still
    // holds the returned quantities (if not, the user picks the
    // warehouse the stock was transferred to). Watched below via
    // [_stockFor], which the picker decision reuses.
    final stock = _stockFor(lines);
    final sourceMissing = lines.any((line) {
      if (_lineQty(line) <= 0) return false;
      final rows = stock[line.itemId];
      final available = rows == null ? 0 : rows[_warehouseId] ?? 0;
      return available < _lineQty(line) - 0.0001;
    });
    if (sourceMissing) {
      // Receipt warehouse can't cover the entered quantities — the user
      // picks where the stock is now. Clear any stale receipt-warehouse
      // default that can't cover the lines.
      _warehouseNeedsPick = true;
      final stale = _warehouseId != null &&
          lines.any((line) {
            if (_lineQty(line) <= 0) return false;
            final rows = stock[line.itemId];
            final available = rows == null ? 0 : rows[_warehouseId] ?? 0;
            return available < _lineQty(line) - 0.0001;
          });
      if (stale) _warehouseId = null;
    } else {
      _warehouseNeedsPick = false;
      _warehouseId ??= widget.source.warehouseId ??
          (detail is Purchase
              ? detail.warehouseId
              : detail is PurchaseOrderDetail
                  ? detail.warehouseId
                  : null);
    }
    // A document with nothing left to return can't open the form flow.
    if (lines.isEmpty) {
      return Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.purchasesReturnempty),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.commonClose),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final totalAmount = lines.fold<num>(
      0,
      (sum, line) => sum + _lineQty(line) * line.unitCost,
    );

    return MovableDialog(
      dialogId: 'purchase_return_form',
      maxWidth: 780,
      maxHeight: 640,
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.purchasesReturntitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${widget.source.type.label(l10n)} — ${widget.source.no}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    ErrorBanner(message: _error!),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FormFieldShell(
                          label: l10n.purchasesReturndate,
                          required: true,
                          child: InkWell(
                            onTap: _busy ? null : _pickDate,
                            child: InputDecorator(
                              decoration: formInputDecoration(),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(isoDate(_returnDate)),
                                  const Icon(Icons.calendar_today, size: 18),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildWarehouseField(
                      context,
                      l10n,
                      warehouses,
                      lines,
                      stock,
                    ),
                  ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 20),
            // Lines table
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.purchasesReturnitems,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    _lineHeader(l10n),
                    const SizedBox(height: 4),
                    for (final line in lines) _lineRow(context, line, stock),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FormFieldShell(
                    label: l10n.purchasesReturnreason,
                    child: TextField(
                      controller: _reasonController,
                      enabled: !_busy,
                      onSubmitted: submitOnEnter(() => _submit(detail)),
                      decoration: formInputDecoration(
                        hintText: l10n.purchasesReturnreasonplaceholder,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${l10n.purchasesReturnvalue}: '
                          '${Formatters.currency(totalAmount)}',
                          style: Theme.of(context).textTheme.titleSmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: Text(l10n.commonCancel),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _busy ? null : () => _submit(detail),
                        icon: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(
                                Icons.assignment_return_outlined,
                                size: 18,
                              ),
                        label: Text(l10n.purchasesReturn),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
      ),
    );
  }

  /// The warehouse field — a read-only lock while the receipt warehouse
  /// still holds the returned stock; a warning + picker when the stock
  /// was transferred out since receipt (the user returns from where the
  /// stock actually is now).
  Widget _buildWarehouseField(
    BuildContext context,
    AppLocalizations l10n,
    List<Warehouse> warehouses,
    List<_ReturnLine> lines,
    Map<int, Map<int, num>> stock,
  ) {
    final scheme = Theme.of(context).colorScheme;
    if (!_warehouseNeedsPick) {
      return FormFieldShell(
        label: l10n.fieldsWarehouse,
        required: true,
        child: InputDecorator(
          decoration: formInputDecoration(),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  _warehouseName(warehouses),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Fixed to the source document — a return leaves the
              // warehouse the goods were received into.
              Icon(
                Icons.lock_outline,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FormFieldShell(
          label: l10n.purchasesReturnwarehouse,
          required: true,
          child: SearchableSelect<int>(
            items: [for (final w in warehouses) w.id],
            selected: _warehouseId,
            hint: l10n.purchasesReturnpickhint,
            isDense: true,
            enabled: !_busy,
            labelBuilder: (id) {
              final match = warehouses.where((w) => w.id == id);
              return match.isEmpty
                  ? '$id'
                  : match.first.warehouseName ?? match.first.warehouseCode;
            },
            decoration: formInputDecoration(),
            onChanged: (id) => setState(() => _warehouseId = id),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.purchasesReturnstockmoved,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: scheme.error,
          ),
        ),
      ],
    );
  }

  /// The resolved source warehouse's display name (falls back to the id).
  String _warehouseName(List<Warehouse> warehouses) {
    final match = warehouses.where((w) => w.id == _warehouseId);
    if (match.isEmpty) return '$_warehouseId';
    return match.first.warehouseName ?? match.first.warehouseCode;
  }

  /// Live per-item warehouse stock (`GET /inventory/items/:id` →
  /// `stock_by_warehouse`), keyed `itemId → warehouseId → quantity`. The
  /// form watches each line's detail so a transfer since receipt is
  /// visible at entry time; the server is the final authority regardless.
  Map<int, Map<int, num>> _stockFor(List<_ReturnLine> lines) {
    final stock = <int, Map<int, num>>{};
    for (final line in lines) {
      final detail =
          ref.watch(itemDetailProvider(line.itemId)).valueOrNull;
      if (detail == null) continue;
      stock[line.itemId] = {
        for (final row in detail.stockByWarehouse) row.warehouseId: row.quantity,
      };
    }
    return stock;
  }

  Widget _cell(String text, double width, {TextAlign align = TextAlign.start}) =>
      SizedBox(
        width: width,
        child: Text(
          text,
          textAlign: align,
          style: const TextStyle(fontSize: 12),
          overflow: TextOverflow.ellipsis,
        ),
      );

  Widget _lineHeader(AppLocalizations l10n) => Row(
    children: [
      Expanded(child: _cell(l10n.fieldsItem, 0)),
      _cell(l10n.purchasesUnitcost, 90, align: TextAlign.end),
      _cell(l10n.purchasesOriginalqty, 80, align: TextAlign.end),
      _cell(l10n.purchasesAlreadyreturned, 80, align: TextAlign.end),
      _cell(l10n.purchasesAvailable, 90, align: TextAlign.end),
      const SizedBox(width: 8),
      _cell(l10n.purchasesReturnqty, 110, align: TextAlign.end),
    ],
  );

  Widget _lineRow(
    BuildContext context,
    _ReturnLine line,
    Map<int, Map<int, num>> stock,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final controller = _controllerFor(line.sourceItemId);
    final qty = _lineQty(line);
    final cap = _effectiveCap(line, stock);
    final invalid = controller.text.trim().isNotEmpty &&
        (qty <= 0 || qty > cap + 0.0001);

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.itemName,
                  style: Theme.of(context).textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
                if (line.unitOfMeasure.isNotEmpty)
                  Text(
                    line.unitOfMeasure,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          _cell(Formatters.currency(line.unitCost), 90, align: TextAlign.end),
          _cell(Formatters.number(line.originalQty), 80, align: TextAlign.end),
          _cell(Formatters.number(line.returnedQty), 80, align: TextAlign.end),
          _cell(
            Formatters.number(cap),
            90,
            align: TextAlign.end,
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 110,
            child: TextField(
              controller: controller,
              enabled: !_busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: formInputDecoration(hintText: '0').copyWith(
                errorText: invalid ? l10n.purchasesReturnqtyinvalid : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }
}
