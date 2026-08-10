// Purchase order create/edit form — modal dialog over the purchase-orders
// API (PORTING.md §2 / the server `purchaseOrderController` DTOs).
//
// Create posts the header plus the `items` array in one call; the server
// generates the PO no and derives `total_amount` from the lines. Edit
// (Draft-only server-side) PUTs the header, then reconciles the line
// items through the item routes: POST /:id/items for new lines, PUT
// /:id/items/:itemId for changed quantity/price, DELETE for removed
// lines, and remove+add when the item itself changed (the PUT accepts
// quantity/unit_price only). The form pre-fills from the detail the
// detail dialog already fetched (no second request).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart' show isoDate;
import '../../core/utils/formatters.dart';
import '../../core/utils/print_utils.dart' show printPdfBytes;
import '../../data/models/item.dart' show Item;
import '../../data/models/purchase_order.dart' show PurchaseOrderDetail;
import '../../data/models/supplier.dart' show Supplier;
import '../../data/models/warehouse.dart' show Warehouse;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/purchase_order_repository.dart'
    show purchaseOrderRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/date_picker_helpers.dart' show pickDate;
import '../../widgets/confirm_dialog.dart';
import '../../widgets/form_field.dart';
import '../../widgets/form_helpers.dart' show numText;
import '../../widgets/searchable_select.dart';
import '../inventory/inventory_providers.dart' show warehousesProvider;
import 'purchase_order_pdf.dart' show buildA4PurchaseOrderPdf;
import 'purchase_order_providers.dart';

/// Opens the create ([detail] == null) or edit form dialog.
Future<void> showPurchaseOrderFormDialog(
  BuildContext context, {
  PurchaseOrderDetail? detail,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => PurchaseOrderFormDialog(detail: detail),
  );
}

/// Mutable form line — the item picker value plus qty/unit-price fields.
class _PoLine {
  _PoLine({this.itemLineId, this.itemId = ''})
    : quantityController = TextEditingController(),
      priceController = TextEditingController();

  /// The `purchase_order_items.id` when editing an existing line
  /// (null for lines being added).
  int? itemLineId;

  /// Selected item id as a string (the searchable select works on ints).
  String itemId;

  final TextEditingController quantityController;
  final TextEditingController priceController;

  num get quantity => double.tryParse(quantityController.text) ?? 0;
  num get unitPrice => double.tryParse(priceController.text) ?? 0;

  void dispose() {
    quantityController.dispose();
    priceController.dispose();
  }
}

class PurchaseOrderFormDialog extends ConsumerStatefulWidget {
  const PurchaseOrderFormDialog({super.key, this.detail});

  /// Null → create; otherwise pre-fills and edits (header + items).
  final PurchaseOrderDetail? detail;

  @override
  ConsumerState<PurchaseOrderFormDialog> createState() =>
      _PurchaseOrderFormDialogState();
}

class _PurchaseOrderFormDialogState
    extends ConsumerState<PurchaseOrderFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _notesController;
  final List<_PoLine> _lines = [];

  int? _supplierId;
  int? _warehouseId;
  late DateTime _poDate;
  DateTime? _expectedDate;

  bool _submitting = false;
  bool _printing = false;
  String? _error;

  bool get _isEdit => widget.detail != null;

  @override
  void initState() {
    super.initState();
    final detail = widget.detail;
    _notesController = TextEditingController(text: detail?.notes ?? '');
    _supplierId = detail?.supplierId;
    _poDate = DateTime.tryParse(detail?.poDate ?? '') ?? DateTime.now();
    _expectedDate = DateTime.tryParse(detail?.expectedDeliveryDate ?? '');
    if (detail != null) {
      for (final item in detail.items) {
        _lines.add(
          _PoLine(itemLineId: item.id, itemId: item.itemId.toString())
            ..quantityController.text = numText(item.quantity)
            ..priceController.text = numText(item.unitPrice),
        );
      }
    }
    if (_lines.isEmpty) _lines.add(_PoLine());
  }

  @override
  void dispose() {
    _notesController.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  List<_PoLine> get _filledLines =>
      _lines.where((line) => line.itemId.isNotEmpty).toList();

  num get _total => _filledLines.fold<num>(
    0,
    (sum, line) => sum + line.quantity * line.unitPrice,
  );

  Future<void> _pickDate({required bool expected}) async {
    final picked = await pickDate(
      context,
      initialDate: expected ? (_expectedDate ?? _poDate) : _poDate,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (expected) {
        _expectedDate = picked;
      } else {
        _poDate = picked;
      }
    });
  }

  /// Header body shared by create (which also appends `items`) and edit
  /// (the server's update DTO has no items).
  Map<String, dynamic> _buildHeaderBody() {
    final notes = _notesController.text.trim();
    return {
      'supplier_id': _supplierId!,
      'po_date': isoDate(_poDate),
      if (!_isEdit) 'status': 'Draft',
      if (_expectedDate != null)
        'expected_delivery_date': isoDate(_expectedDate!),
      if (_warehouseId != null) 'warehouse_id': _warehouseId,
      if (notes.isNotEmpty) 'notes': notes,
    };
  }

  Map<String, dynamic> _lineBody(_PoLine line) => {
    if (line.itemLineId == null) 'item_id': int.parse(line.itemId),
    'quantity': line.quantity,
    'unit_price': line.unitPrice,
  };

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_supplierId == null) {
      setState(() => _error = l10n.purchaseordersErrorSupplierrequired);
      return;
    }
    if (_filledLines.isEmpty) {
      setState(() => _error = l10n.purchaseordersErrorItemsrequired);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });

    final repo = ref.read(purchaseOrderRepositoryProvider);
    if (!_isEdit) {
      final result = await repo.create({
        ..._buildHeaderBody(),
        'items': [for (final line in _filledLines) _lineBody(line)],
      });
      if (!mounted) return;
      switch (result) {
        case ApiSuccess():
          ref.invalidate(purchaseOrdersProvider);
          Navigator.of(context).pop();
          showAppToast(context, l10n.purchaseordersSaved);
        case ApiFailure(:final error):
          setState(() {
            _submitting = false;
            _error = error.message;
          });
      }
      return;
    }

    // Edit: PUT the header, then reconcile the lines through the item
    // routes. A failed header PUT aborts; item failures stop at the first
    // error with the dialog still open (the header may already be saved).
    final detail = widget.detail!;
    final headerResult = await repo.updateHeader(detail.id, _buildHeaderBody());
    if (headerResult case ApiFailure(:final error)) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error.message;
      });
      return;
    }

    final original = {
      for (final item in detail.items)
        if (item.id > 0) item.id: item,
    };
    final kept = <int>{};

    for (final line in _filledLines) {
      final lineId = line.itemLineId;
      final orig = lineId == null ? null : original[lineId];
      final selectedItemId = int.parse(line.itemId);

      if (lineId == null || orig == null) {
        // A brand-new line — or one whose server id no longer exists.
        final result = await repo.addItem(detail.id, _lineBody(line));
        if (result case ApiFailure(:final error)) {
          return _fail(error.message);
        }
        continue;
      }
      kept.add(lineId);
      if (orig.itemId != selectedItemId) {
        // The item itself changed — PUT can't re-target, so remove+add.
        // The add body must carry item_id explicitly: _lineBody omits it
        // for lines that still hold a server id.
        final removed = await repo.removeItem(detail.id, lineId);
        if (removed case ApiFailure(:final error)) {
          return _fail(error.message);
        }
        final added = await repo.addItem(detail.id, {
          'item_id': selectedItemId,
          'quantity': line.quantity,
          'unit_price': line.unitPrice,
        });
        if (added case ApiFailure(:final error)) {
          return _fail(error.message);
        }
      } else if (orig.quantity != line.quantity ||
          orig.unitPrice != line.unitPrice) {
        final result = await repo.updateItem(
          detail.id,
          lineId,
          _lineBody(line),
        );
        if (result case ApiFailure(:final error)) {
          return _fail(error.message);
        }
      }
    }

    for (final id in original.keys) {
      if (!kept.contains(id)) {
        final result = await repo.removeItem(detail.id, id);
        if (result case ApiFailure(:final error)) {
          return _fail(error.message);
        }
      }
    }

    if (!mounted) return;
    ref.invalidate(purchaseOrdersProvider);
    ref.invalidate(purchaseOrderDetailProvider(detail.id));
    Navigator.of(context).pop();
    showAppToast(context, l10n.purchaseordersSaved);
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = message;
    });
  }

  /// Delete the Draft PO (edit mode only) — confirms, DELETE /:id, then
  /// pops both the form and the detail dialog beneath it, returning to
  /// the grid (mirrors the sales form's delete flow).
  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.commonDelete,
      message: l10n.purchaseordersDeleteconfirm,
      confirmLabel: l10n.commonDelete,
      cancelLabel: l10n.commonCancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    final result = await ref
        .read(purchaseOrderRepositoryProvider)
        .deletePo(widget.detail!.id);
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        ref.invalidate(purchaseOrdersProvider);
        // Pop the form, then the detail dialog it was opened from.
        Navigator.of(context)
          ..pop()
          ..pop();
        showAppToast(context, l10n.purchaseordersDeleted);
      case ApiFailure(:final error):
        setState(() {
          _submitting = false;
          _error = error.message;
        });
    }
  }

  /// Builds the A4 purchase order PDF from the *saved* order (fresh
  /// `GET /purchase-orders/:id`, PORTING.md §12) and shows the native
  /// print dialog — same pattern as the invoice/quotation/SO forms.
  Future<void> _printPurchaseOrder() async {
    final l10n = AppLocalizations.of(context)!;
    final poId = widget.detail!.id;
    setState(() => _printing = true);
    try {
      final result = await ref
          .read(purchaseOrderRepositoryProvider)
          .detail(poId);
      if (!mounted) return;
      final purchaseOrder = switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => _printError(
          '${l10n.errorsFailed}: ${error.message}',
        ),
      };
      if (purchaseOrder == null) return;

      final bytes = await buildA4PurchaseOrderPdf(
        purchaseOrder: purchaseOrder,
      );
      if (!mounted) return;
      await printPdfBytes(bytes, '${purchaseOrder.poNo}.pdf', context);
    } catch (error) {
      if (mounted) _printError('${l10n.errorsFailed}: $error');
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  /// Shows the print error toast and signals the caller to abort.
  PurchaseOrderDetail? _printError(String message) {
    showAppToast(context, message, isError: true);
    return null;
  }

  InputDecoration _decoration() =>
      const InputDecoration(isDense: true, border: OutlineInputBorder());

  Widget _dateField(String label, DateTime value) {
    return SizedBox(
      height: 44,
      child: OutlinedButton.icon(
        onPressed: _submitting ? null : () => _pickDate(expected: false),
        icon: const Icon(Icons.calendar_today_outlined, size: 16),
        label: Text(Formatters.date(isoDate(value))),
      ),
    );
  }

  Widget _expectedDateField(AppLocalizations l10n) {
    final value = _expectedDate;
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 44,
            child: OutlinedButton.icon(
              onPressed: _submitting ? null : () => _pickDate(expected: true),
              icon: const Icon(Icons.calendar_today_outlined, size: 16),
              label: Text(
                value == null
                    ? l10n.purchaseordersExpecteddelivery
                    : Formatters.date(isoDate(value)),
                style: TextStyle(
                  color: value == null
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : null,
                ),
              ),
            ),
          ),
        ),
        if (value != null)
          IconButton(
            tooltip: l10n.commonRemove,
            icon: const Icon(Icons.close, size: 16),
            onPressed: _submitting
                ? null
                : () => setState(() => _expectedDate = null),
          ),
      ],
    );
  }

  Widget _lineRow(AppLocalizations l10n, int index) {
    final line = _lines[index];
    final items = ref.watch(poItemsProvider).valueOrNull ?? const <Item>[];
    final amount = line.quantity * line.unitPrice;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: FormFieldShell(
            label: l10n.fieldsItem,
            child: SearchableSelect<int>(
              items: [for (final i in items) i.id],
              selected: line.itemId.isEmpty ? null : int.tryParse(line.itemId),
              labelBuilder: (id) {
                final match = items.where((i) => i.id == id);
                final item = match.isEmpty ? null : match.first;
                return item == null
                    ? '$id'
                    : '${item.itemCode} — ${item.itemName}';
              },
              onChanged: (value) =>
                  setState(() => line.itemId = value?.toString() ?? ''),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 86,
          child: TextFormField(
            controller: line.quantityController,
            enabled: !_submitting,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _decoration(),
            validator: (value) => (double.tryParse(value ?? '') ?? -1) > 0
                ? null
                : l10n.commonRequired,
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 100,
          child: TextFormField(
            controller: line.priceController,
            enabled: !_submitting,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _decoration(),
            validator: (value) => (double.tryParse(value ?? '') ?? -1) > 0
                ? null
                : l10n.commonRequired,
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 100,
          child: FormFieldShell(
            label: l10n.fieldsAmount,
            child: Container(
              height: 44,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 6),
              child: Text(
                Formatters.currency(amount),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 34,
          child: IconButton(
            tooltip: l10n.commonRemove,
            icon: const Icon(Icons.remove_circle_outline, size: 18),
            onPressed: _submitting || _lines.length <= 1
                ? null
                : () => setState(() {
                    _lines.removeAt(index).dispose();
                  }),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final suppliers =
        ref.watch(poSupplierOptionsProvider).valueOrNull ?? const <Supplier>[];
    final warehouses =
        ref.watch(warehousesProvider).valueOrNull ?? const <Warehouse>[];
    final supplierIds = [for (final s in suppliers) s.id];
    final warehouseIds = [for (final w in warehouses) w.id];

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  _isEdit
                      ? l10n.purchaseordersEditpurchaseorder
                      : l10n.purchaseordersNewpurchaseorder,
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
                              label: l10n.fieldsSupplier,
                              required: true,
                              child: SearchableSelect<int>(
                                items: supplierIds,
                                selected: _supplierId,
                                labelBuilder: (id) {
                                  final match = suppliers.where(
                                    (s) => s.id == id,
                                  );
                                  final supplier = match.isEmpty
                                      ? null
                                      : match.first;
                                  return supplier == null
                                      ? '$id'
                                      : '${supplier.supplierCode} — '
                                            '${supplier.supplierName}';
                                },
                                onChanged: (value) =>
                                    setState(() => _supplierId = value),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.purchaseordersPodate,
                              required: true,
                              child: _dateField(
                                l10n.purchaseordersPodate,
                                _poDate,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.purchaseordersExpecteddelivery,
                              child: _expectedDateField(l10n),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.fieldsWarehouse,
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
                        ],
                      ),
                      const SizedBox(height: 12),
                      FormFieldShell(
                        label: l10n.fieldsNotes,
                        child: TextFormField(
                          controller: _notesController,
                          enabled: !_submitting,
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
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _submitting
                              ? null
                              : () => setState(() => _lines.add(_PoLine())),
                          icon: const Icon(Icons.add, size: 18),
                          label: Text(l10n.purchaseordersAdditem),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            l10n.commonTotal,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 120,
                            child: Text(
                              Formatters.currency(_total),
                              textAlign: TextAlign.end,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
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
                    if (_isEdit) ...[
                      TextButton.icon(
                        onPressed: _printing || _submitting
                            ? null
                            : _printPurchaseOrder,
                        icon: _printing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.print_outlined, size: 18),
                        label: Text(l10n.purchaseordersPrinta4),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _submitting ? null : _delete,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: Text(l10n.commonDelete),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      const Spacer(),
                    ],
                    TextButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: Text(l10n.commonCancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(l10n.commonSave),
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
}
