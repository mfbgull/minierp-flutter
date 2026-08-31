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
//
// Layout follows the purchase form: sectioned cards (Document / Items /
// Payment). Create mode records a payment right after the PO is created
// (`POST /payments` with `po_allocations`); edit mode records a payment
// against the existing PO immediately (the summary refreshes from the
// detail provider after each payment).

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
import '../../data/repositories/invoice_repository.dart'
    show invoiceRepositoryProvider;
import '../../data/repositories/purchase_order_repository.dart'
    show purchaseOrderRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/date_picker.dart' show pickDate;
import '../../widgets/confirm_dialog.dart';
import '../../widgets/form_field.dart';
import '../../widgets/form_helpers.dart' show formInputDecoration, numText;
import '../../widgets/form_section_card.dart' show FormSectionCard;
import '../../widgets/payment_success_screen.dart' show PaymentSuccessScreen;
import '../../widgets/searchable_select.dart';
import '../inventory/inventory_providers.dart' show warehousesProvider;
import '../payments/payments_providers.dart' show paymentsProvider;
import '../sales/payment_panel.dart' show kPaymentMethods;
import 'purchase_order_pdf.dart' show buildA4PurchaseOrderPdf;
import 'purchase_order_providers.dart';
import 'package:minierp_app/core/theme/app_border_radius.dart';
import 'package:minierp_app/widgets/movable_dialog.dart';

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

  /// Optional expiry date for expiry-tracked items (flows into the batch
  /// at goods receipt).
  DateTime? expiryDate;

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

  // Payment — create mode records on save; edit mode records immediately.
  bool _recordPayment = true;
  late DateTime _paymentDate;
  String _paymentMethod = kPaymentMethods.first;
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  final _paymentNotesController = TextEditingController();

  /// The PO total the amount field was last synced to — lets the amount
  /// track the total until the user types their own number.
  num _lastSyncedTotal = 0;

  /// Edit mode: whether the record-payment form is expanded.
  bool _editPaymentOpen = false;
  bool _recordingPayment = false;

  bool _submitting = false;
  bool _printing = false;
  String? _error;

  /// Set once a create-mode PO + its payment both saved — the dialog
  /// body switches to the success screen (print receipt / close).
  int? _lastPaymentId;

  bool get _isEdit => widget.detail != null;

  @override
  void initState() {
    super.initState();
    final detail = widget.detail;
    _notesController = TextEditingController(text: detail?.notes ?? '');
    _supplierId = detail?.supplierId;
    _poDate = DateTime.tryParse(detail?.poDate ?? '') ?? DateTime.now();
    _paymentDate = _poDate;
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
    _amountController.dispose();
    _referenceController.dispose();
    _paymentNotesController.dispose();
    super.dispose();
  }

  List<_PoLine> get _filledLines =>
      _lines.where((line) => line.itemId.isNotEmpty).toList();

  num get _total => _filledLines.fold<num>(
    0,
    (sum, line) => sum + line.quantity * line.unitPrice,
  );

  num get _paymentAmount => num.tryParse(_amountController.text.trim()) ?? 0;

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

  Future<void> _pickPaymentDate() async {
    final picked = await pickDate(context, initialDate: _paymentDate);
    if (picked != null && mounted) setState(() => _paymentDate = picked);
  }

  /// Keeps the payment amount in lock-step with the PO total until the
  /// user edits it themselves (the common flow is "pay the full amount").
  void _syncPaymentToTotal() {
    final total = _total;
    final current = num.tryParse(_amountController.text.trim()) ?? 0;
    final untouched = current == 0 || current == _lastSyncedTotal;
    if (_recordPayment && !_isEdit && total > 0 && untouched) {
      _amountController.text = numText(total);
      _lastSyncedTotal = total;
    }
    setState(() {});
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
    if (line.expiryDate != null) 'expiry_date': isoDate(line.expiryDate!),
  };

  Map<String, dynamic> _paymentBody({required int poId}) => {
    'supplier_id': _supplierId!,
    'payment_date': isoDate(_paymentDate),
    'amount': _paymentAmount,
    'payment_method': _paymentMethod,
    if (_referenceController.text.trim().isNotEmpty)
      'reference_no': _referenceController.text.trim(),
    if (_paymentNotesController.text.trim().isNotEmpty)
      'notes': _paymentNotesController.text.trim(),
    'po_allocations': [
      {'po_id': poId, 'amount': _paymentAmount},
    ],
  };

  /// Edit mode: record a payment against the existing PO immediately and
  /// refresh the payment summary.
  Future<void> _recordPaymentNow(num balance) async {
    final l10n = AppLocalizations.of(context)!;
    if (_paymentAmount <= 0) {
      showAppToast(context, l10n.paymentsErrorAmountGreaterThanZero);
      return;
    }
    if (_paymentAmount > balance) {
      showAppToast(
        context,
        l10n.paymentsErrorAmountExceedsBalance(Formatters.currency(balance)),
      );
      return;
    }
    setState(() => _recordingPayment = true);
    final result = await ref
        .read(invoiceRepositoryProvider)
        .createSupplierPayment(
          _paymentBody(poId: widget.detail!.id),
        );
    if (!mounted) return;
    setState(() {
      _recordingPayment = false;
      _editPaymentOpen = false;
    });
    switch (result) {
      case ApiSuccess(:final data):
        showAppToast(context, l10n.paymentsRecordedsuccess);
        ref.invalidate(paymentsProvider);
        ref.invalidate(purchaseOrderDetailProvider(widget.detail!.id));
        ref.invalidate(purchaseOrderPaymentsProvider(widget.detail!.id));
        if (mounted) {
          // Nested success dialog — the form below keeps its unsaved
          // edits intact; Close returns to it.
          showDialog<void>(
            context: context,
            builder: (_) => PaymentSuccessScreen(
              title: l10n.paymentsRecordedsuccess,
              subtitle: l10n.suppliersWhatnext,
              paymentId: data.id,
              entityName: widget.detail!.supplierName,
            ),
          );
        }
      case ApiFailure(:final error):
        showAppToast(context, error.message, isError: true);
    }
  }

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
    if (!_isEdit &&
        _recordPayment &&
        _paymentAmount > 0 &&
        _paymentAmount > _total) {
      setState(
        () => _error = l10n.paymentsErrorAmountExceedsBalance(
          Formatters.currency(_total),
        ),
      );
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
        case ApiSuccess(:final data):
          ref.invalidate(purchaseOrdersProvider);
          if (_recordPayment && _paymentAmount > 0) {
            final payResult = await ref
                .read(invoiceRepositoryProvider)
                .createSupplierPayment(_paymentBody(poId: data.id));
            if (!mounted) return;
            ref.invalidate(paymentsProvider);
            if (payResult case ApiSuccess(data: final payData)) {
              setState(() {
                _submitting = false;
                _lastPaymentId = payData.id;
              });
            } else if (payResult case ApiFailure(:final error)) {
              // The PO saved; only the payment failed.
              Navigator.of(context).pop();
              showAppToast(
                context,
                '${l10n.purchaseordersSaved} — '
                '${l10n.errorsFailed}: ${error.message}',
                isError: true,
              );
            }
            return;
          }
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
      height: 42,
      child: OutlinedButton.icon(
        onPressed: _submitting || _recordingPayment ? null : () => _pickDate(expected: false),
        icon: const Icon(Icons.calendar_today_outlined, size: 15),
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
            height: 42,
            child: OutlinedButton.icon(
              onPressed: _submitting
                  ? null
                  : () => _pickDate(expected: true),
              icon: const Icon(Icons.calendar_today_outlined, size: 15),
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

  // ── Sections ──────────────────────────────────────────────────

  Widget _documentSection(AppLocalizations l10n) {
    final suppliers =
        ref.watch(poSupplierOptionsProvider).valueOrNull ?? const <Supplier>[];
    final supplierIds = [for (final s in suppliers) s.id];
    final warehouses =
        ref.watch(warehousesProvider).valueOrNull ?? const <Warehouse>[];
    final warehouseIds = [for (final w in warehouses) w.id];

    return FormSectionCard(
      icon: Icons.receipt_long_outlined,
      title: l10n.purchasesDocument,
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
                      final match = suppliers.where((s) => s.id == id);
                      final supplier = match.isEmpty ? null : match.first;
                      return supplier == null
                          ? '$id'
                          : '${supplier.supplierCode} — '
                                '${supplier.supplierName}';
                    },
                    decoration: formInputDecoration(),
                    validator: (v) => v == null
                        ? l10n.purchaseordersErrorSupplierrequired
                        : null,
                    onChanged: (value) => setState(() => _supplierId = value),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FormFieldShell(
                  label: l10n.purchaseordersPodate,
                  required: true,
                  child: _dateField(l10n.purchaseordersPodate, _poDate),
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
              const SizedBox(width: 10),
              Expanded(
                child: FormFieldShell(
                  label: l10n.fieldsWarehouse,
                  child: SearchableSelect<int>(
                    items: warehouseIds,
                    selected: _warehouseId,
                    labelBuilder: (id) {
                      final match = warehouses.where((w) => w.id == id);
                      final warehouse = match.isEmpty ? null : match.first;
                      return warehouse == null
                          ? '$id'
                          : '${warehouse.warehouseCode} — '
                                '${warehouse.warehouseName ?? ''}';
                    },
                    decoration: formInputDecoration(),
                    onChanged: (value) => setState(() => _warehouseId = value),
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
        ],
      ),
    );
  }

  Future<void> _pickLineExpiryDate(int index) async {
    final line = _lines[index];
    final picked = await pickDate(
      context,
      initialDate: line.expiryDate ?? DateTime.now(),
      firstDate: DateTime.now(),
    );
    if (picked != null && mounted) {
      setState(() => line.expiryDate = picked);
    }
  }

  Widget _lineRow(AppLocalizations l10n, int index) {
    final line = _lines[index];
    final items = ref.watch(poItemsProvider).valueOrNull ?? const <Item>[];
    final scheme = Theme.of(context).colorScheme;
    final amount = line.quantity * line.unitPrice;
    final selectedItem = items
        .where((i) => i.id.toString() == line.itemId)
        .firstOrNull;
    final showExpiry = selectedItem?.hasExpiry == true;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
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
            decoration: formInputDecoration(),
            onChanged: (value) => setState(() {
              line.itemId = value?.toString() ?? '';
              _syncPaymentToTotal();
            }),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 92,
          child: TextFormField(
            controller: line.quantityController,
            enabled: !_submitting,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _decoration(),
            validator: (value) => (double.tryParse(value ?? '') ?? -1) > 0
                ? null
                : l10n.commonRequired,
            onChanged: (_) => _syncPaymentToTotal(),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 110,
          child: TextFormField(
            controller: line.priceController,
            enabled: !_submitting,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _decoration(),
            validator: (value) => (double.tryParse(value ?? '') ?? -1) > 0
                ? null
                : l10n.commonRequired,
            onChanged: (_) => _syncPaymentToTotal(),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 110,
          child: Container(
            height: 42,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: AppBorderRadius.smRadius,
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            ),
            child: Text(
              Formatters.currency(amount),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
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
                    _syncPaymentToTotal();
                  }),
          ),
        ),
      ],
      ),
      if (showExpiry) ...[
        const SizedBox(height: 6),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: SizedBox(
            height: 38,
            child: OutlinedButton.icon(
              onPressed: _submitting ? null : () => _pickLineExpiryDate(index),
              icon: const Icon(Icons.calendar_today_outlined, size: 15),
              label: Text(
                line.expiryDate != null
                    ? Formatters.date(isoDate(line.expiryDate!))
                    : l10n.expirySelectDateOptional,
              ),
            ),
          ),
        ),
      ],
    ]);
  }

  Widget _itemsSection(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final headerStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );
    return FormSectionCard(
      icon: Icons.inventory_2_outlined,
      title: l10n.purchasesItemscard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_lines.isNotEmpty) ...[
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(l10n.fieldsItem, style: headerStyle),
                ),
                const SizedBox(width: 8),
                SizedBox(width: 92, child: Text(l10n.fieldsQuantity, style: headerStyle)),
                const SizedBox(width: 8),
                SizedBox(width: 110, child: Text(l10n.purchasesUnitcost, style: headerStyle)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 110,
                  child: Text(
                    l10n.fieldsAmount,
                    textAlign: TextAlign.end,
                    style: headerStyle,
                  ),
                ),
                const SizedBox(width: 38),
              ],
            ),
            const SizedBox(height: 6),
          ],
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
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                l10n.commonTotal,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 140,
                child: Text(
                  Formatters.currency(_total),
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryLine(String label, num value, {bool bold = false, Color? color}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            Formatters.currency(value),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentFields(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: FormFieldShell(
                label: l10n.salesPaymentdate,
                required: true,
                child: SizedBox(
                  height: 42,
                  child: OutlinedButton.icon(
                    onPressed: _submitting || _recordingPayment
                        ? null
                        : _pickPaymentDate,
                    icon: const Icon(Icons.calendar_today_outlined, size: 15),
                    label: Text(Formatters.date(isoDate(_paymentDate))),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FormFieldShell(
                label: l10n.expensesPaymentmethod,
                child: SearchableSelect<String>(
                  items: kPaymentMethods,
                  selected: _paymentMethod,
                  labelBuilder: (m) => m,
                  decoration: formInputDecoration(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _paymentMethod = value);
                    }
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FormFieldShell(
          label: l10n.fieldsAmount,
          required: true,
          child: TextFormField(
            controller: _amountController,
            onChanged: (_) => setState(() {}),
            enabled: !_submitting && !_recordingPayment,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: formInputDecoration(),
            validator: (value) {
              final amount = num.tryParse(value?.trim() ?? '');
              if (amount == null || amount <= 0) {
                return l10n.paymentsErrorAmountGreaterThanZero;
              }
              return null;
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: FormFieldShell(
                label: l10n.fieldsReference,
                child: TextFormField(
                  controller: _referenceController,
                  enabled: !_submitting && !_recordingPayment,
                  decoration: formInputDecoration(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FormFieldShell(
                label: l10n.fieldsNotes,
                child: TextFormField(
                  controller: _paymentNotesController,
                  enabled: !_submitting && !_recordingPayment,
                  decoration: formInputDecoration(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Payment card — create mode offers pay-on-save; edit mode shows the
  /// paid/balance summary and records immediately.
  Widget _paymentSection(AppLocalizations l10n, PurchaseOrderDetail? liveDetail) {
    final scheme = Theme.of(context).colorScheme;
    if (_isEdit) {
      final total = liveDetail?.totalAmount ?? widget.detail!.totalAmount;
      final paid = liveDetail?.paidAmount ?? widget.detail!.paidAmount;
      final balance = liveDetail?.balanceAmount ?? widget.detail!.balanceAmount;
      return FormSectionCard(
        icon: Icons.payments_outlined,
        title: l10n.salesPayment,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _summaryLine(l10n.salesGrandtotal, total),
            _summaryLine(
              l10n.salesTotalpaid,
              paid,
              color: const Color(0xff16a34a),
            ),
            _summaryLine(
              l10n.salesBalance,
              balance,
              bold: true,
              color: balance > 0 ? scheme.error : const Color(0xff16a34a),
            ),
            if (balance > 0) ...[
              const SizedBox(height: 8),
              if (!_editPaymentOpen)
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    onPressed: _submitting || _recordingPayment
                        ? null
                        : () => setState(() {
                            if (_amountController.text.trim().isEmpty) {
                              _amountController.text = numText(balance);
                              _lastSyncedTotal = balance;
                            }
                            _editPaymentOpen = true;
                          }),
                    icon: const Icon(Icons.payments_outlined, size: 16),
                    label: Text(l10n.paymentsRecordpayment),
                  ),
                )
              else ...[
                _paymentFields(l10n),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _recordingPayment
                        ? null
                        : () => _recordPaymentNow(balance),
                    icon: _recordingPayment
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check, size: 16),
                    label: Text(l10n.paymentsRecordpayment),
                  ),
                ),
              ],
            ],
          ],
        ),
      );
    }

    return FormSectionCard(
      icon: Icons.payments_outlined,
      title: l10n.salesPayment,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.salesRecordpaymentnow,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              Switch(
                value: _recordPayment,
                onChanged: _submitting
                    ? null
                    : (v) => setState(() {
                        _recordPayment = v;
                        if (v) _syncPaymentToTotal();
                      }),
              ),
            ],
          ),
          if (_recordPayment) ...[
            const SizedBox(height: 4),
            _paymentFields(l10n),
            const Divider(height: 22),
            _summaryLine(l10n.salesGrandtotal, _total),
            _summaryLine(l10n.fieldsAmount, _paymentAmount),
            _summaryLine(
              l10n.salesBalance,
              _total - _paymentAmount,
              bold: true,
              color: _total - _paymentAmount > 0
                  ? scheme.error
                  : const Color(0xff16a34a),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final paymentId = _lastPaymentId;
    if (paymentId != null) {
      final suppliers =
          ref.watch(poSupplierOptionsProvider).valueOrNull ?? const <Supplier>[];
      final matches = suppliers.where((s) => s.id == _supplierId);
      final supplier = matches.isEmpty ? null : matches.first;
      return PaymentSuccessScreen(
        title: l10n.purchaseordersSaved,
        subtitle: l10n.suppliersWhatnext,
        paymentId: paymentId,
        entityName: supplier?.supplierName,
      );
    }

    // Edit mode watches the detail provider so the payment summary
    // refreshes after a recorded payment (falls back to the passed-in
    // detail while the refetch is in flight).
    PurchaseOrderDetail? liveDetail;
    if (_isEdit) {
      liveDetail = ref.watch(purchaseOrderDetailProvider(widget.detail!.id))
              .valueOrNull ??
          widget.detail;
    }

    return MovableDialog(
      dialogId: 'purchase_order_form',
      maxWidth: 760,
      maxHeight: 780,
      child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: AppBorderRadius.mdRadius,
                      ),
                      child: Icon(
                        Icons.assignment_outlined,
                        size: 20,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isEdit
                                ? l10n.purchaseordersEditpurchaseorder
                                : l10n.purchaseordersNewpurchaseorder,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            l10n.purchaseordersSubtitle,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _documentSection(l10n),
                      const SizedBox(height: 12),
                      _itemsSection(l10n),
                      const SizedBox(height: 12),
                      _paymentSection(l10n, liveDetail),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
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
    );
  }
}
