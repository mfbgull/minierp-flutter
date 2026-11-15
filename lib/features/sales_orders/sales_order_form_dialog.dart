// Sales order create/edit form — modal dialog over the sales-orders API
// (PORTING.md §2 / the server `salesController` DTOs).
//
// Create posts the header plus the `items` array in one call; the server
// generates the SO no and derives `total_amount` from the lines. Edit
// PUTs the header plus the full `items` array — the server's
// `SalesOrderModel.update` replaces the lines wholesale (delete +
// reinsert) in one transaction, so no per-item reconciliation routes are
// needed (unlike POs). The form pre-fills from the detail the detail
// dialog already fetched (no second request).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart' show isoDate;
import '../../core/utils/formatters.dart';
import '../../core/utils/print_utils.dart' show printPdfBytes;
import '../../data/models/customer.dart' show Customer;
import '../../data/models/invoice.dart' show Discount, DiscountType;
import '../../data/models/item.dart' show Item;
import '../../data/models/sales_order.dart' show SalesOrderDetail;
import '../../data/models/warehouse.dart' show Warehouse;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/sales_order_repository.dart'
    show salesOrderRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../sales/calculations/sales_order_calculations.dart'
    show calculateItemTotal, calculateTotal;
import '../sales/models/sales_forms.dart' show SOFormItem, flatZeroDiscount;
import '../../widgets/app_toast.dart';
import '../../widgets/date_picker.dart' show pickDate;
import '../../widgets/form_field.dart';
import '../../widgets/form_helpers.dart' show numText;
import '../../widgets/searchable_select.dart';
import '../inventory/inventory_providers.dart' show warehousesProvider;
import 'sales_order_pdf.dart' show buildA4SalesOrderPdf;
import 'sales_order_providers.dart';
import 'package:minierp_app/widgets/movable_dialog.dart';

/// Opens the create ([detail] == null) or edit form dialog.
Future<void> showSalesOrderFormDialog(
  BuildContext context, {
  SalesOrderDetail? detail,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => SalesOrderFormDialog(detail: detail),
  );
}

/// Mutable form line — the item picker value plus qty/unit-price fields.
class _SoLine {
  _SoLine({this.itemId = ''})
    : quantityController = TextEditingController(),
      priceController = TextEditingController(),
      taxRateController = TextEditingController(),
      discountValueController = TextEditingController();

  /// Selected item id as a string (the searchable select works on ints).
  String itemId;

  final TextEditingController quantityController;
  final TextEditingController priceController;
  final TextEditingController taxRateController;
  final TextEditingController discountValueController;

  /// BUG-006: per-line discount kind. `none` sends nothing; the other
  /// two map to the server's `discount_type`.
  DiscountType? discountType;

  num get quantity => double.tryParse(quantityController.text) ?? 0;
  num get unitPrice => double.tryParse(priceController.text) ?? 0;
  num get taxRate => double.tryParse(taxRateController.text) ?? 0;
  num get discountValue =>
      double.tryParse(discountValueController.text) ?? 0;

  /// The shared calculation shape (mirrors `SOFormItem`) so this row and
  /// the server use one rounding rule.
  SOFormItem get formItem => SOFormItem(
    id: 0,
    itemId: itemId,
    quantity: quantity,
    unitPrice: unitPrice,
    taxRate: taxRate,
    discount: discountType == null
        ? flatZeroDiscount
        : Discount(type: discountType!, value: discountValue),
  );

  void dispose() {
    quantityController.dispose();
    priceController.dispose();
    taxRateController.dispose();
    discountValueController.dispose();
  }
}

class SalesOrderFormDialog extends ConsumerStatefulWidget {
  const SalesOrderFormDialog({super.key, this.detail});

  /// Null → create; otherwise pre-fills and edits (header + items).
  final SalesOrderDetail? detail;

  @override
  ConsumerState<SalesOrderFormDialog> createState() =>
      _SalesOrderFormDialogState();
}

class _SalesOrderFormDialogState extends ConsumerState<SalesOrderFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _notesController;
  final List<_SoLine> _lines = [];

  int? _customerId;
  int? _warehouseId;
  late DateTime _soDate;
  DateTime? _deliveryDate;

  bool _submitting = false;
  bool _printing = false;
  String? _error;

  bool get _isEdit => widget.detail != null;

  @override
  void initState() {
    super.initState();
    final detail = widget.detail;
    _notesController = TextEditingController(text: detail?.notes ?? '');
    _customerId = detail?.customerId;
    _soDate = DateTime.tryParse(detail?.soDate ?? '') ?? DateTime.now();
    _deliveryDate = DateTime.tryParse(detail?.deliveryDate ?? '');
    if (detail != null) {
      for (final item in detail.items) {
        final line = _SoLine(itemId: item.itemId.toString())
          ..quantityController.text = numText(item.quantity)
          ..priceController.text = numText(item.unitPrice)
          ..taxRateController.text = numText(item.taxRate);
        // A zero discount is the stored default ('none') — show no kind.
        if (item.discountValue > 0) {
          line.discountType = item.discountType;
          line.discountValueController.text = numText(item.discountValue);
        }
        _lines.add(line);
      }
    }
    if (_lines.isEmpty) _lines.add(_SoLine());
  }

  @override
  void dispose() {
    _notesController.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  List<_SoLine> get _filledLines =>
      _lines.where((line) => line.itemId.isNotEmpty).toList();

  num get _total => calculateTotal([
    for (final line in _filledLines) line.formItem,
  ]);

  Future<void> _pickDate({required bool delivery}) async {
    final picked = await pickDate(
      context,
      initialDate: delivery ? (_deliveryDate ?? _soDate) : _soDate,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (delivery) {
        _deliveryDate = picked;
      } else {
        _soDate = picked;
      }
    });
  }

  Map<String, dynamic> _buildBody() {
    final notes = _notesController.text.trim();
    return {
      'customer_id': _customerId!,
      'so_date': isoDate(_soDate),
      if (!_isEdit) 'status': 'Draft',
      if (_deliveryDate != null) 'delivery_date': isoDate(_deliveryDate!),
      if (_warehouseId != null) 'warehouse_id': _warehouseId,
      if (notes.isNotEmpty) 'notes': notes,
      // The server replaces the line set wholesale on PUT and validates
      // item_id/quantity/unit_price on create; the ids are not sent.
      //
      // BUG-006: tax and discount ride on each line. The server recomputes
      // every amount from these, so the client never sends a total. A zero
      // rate / value is sent as 0 / 'none' to match the stored default.
      'items': [
        for (final line in _filledLines)
          {
            'item_id': int.parse(line.itemId),
            'quantity': line.quantity,
            'unit_price': line.unitPrice,
            'tax_rate': line.taxRate,
            if (line.discountType != null && line.discountValue > 0) ...{
              'discount_type': line.discountType!.value,
              'discount_value': line.discountValue,
            },
          },
      ],
    };
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_customerId == null) {
      setState(() => _error = l10n.salesordersErrorCustomerrequired);
      return;
    }
    if (_filledLines.isEmpty) {
      setState(() => _error = l10n.salesordersErrorItemsrequired);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });

    final repo = ref.read(salesOrderRepositoryProvider);
    final result = _isEdit
        ? await repo.update(widget.detail!.id, _buildBody())
        : await repo.create(_buildBody());
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        ref.invalidate(salesOrdersProvider);
        if (_isEdit) {
          ref.invalidate(salesOrderDetailProvider(widget.detail!.id));
        }
        Navigator.of(context).pop();
        showAppToast(context, l10n.salesordersSaved);
      case ApiFailure(:final error):
        setState(() {
          _submitting = false;
          _error = error.message;
        });
    }
  }

  /// Builds the A4 sales order PDF from the *saved* order (fresh
  /// `GET /sales-orders/:id`, PORTING.md §12) and shows the native print
  /// dialog. Falls back to the share/save-as-PDF sheet when the platform
  /// has no print backend (e.g. some Linux setups) — same pattern as the
  /// invoice/quotation forms' Print A4.
  Future<void> _printSalesOrder() async {
    final l10n = AppLocalizations.of(context)!;
    final soId = widget.detail!.id;
    setState(() => _printing = true);
    try {
      final result = await ref
          .read(salesOrderRepositoryProvider)
          .detail(soId);
      if (!mounted) return;
      final salesOrder = switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => _printError(
          '${l10n.errorsFailed}: ${error.message}',
        ),
      };
      if (salesOrder == null) return;

      final bytes = await buildA4SalesOrderPdf(salesOrder: salesOrder);
      if (!mounted) return;
      await printPdfBytes(bytes, '${salesOrder.soNo}.pdf', context);
    } catch (error) {
      if (mounted) _printError('${l10n.errorsFailed}: $error');
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  /// Shows the print error toast and signals the caller to abort.
  SalesOrderDetail? _printError(String message) {
    showAppToast(context, message, isError: true);
    return null;
  }

  InputDecoration _decoration() =>
      const InputDecoration(isDense: true, border: OutlineInputBorder());

  Widget _dateField(String label, DateTime value) {
    return SizedBox(
      height: 44,
      child: OutlinedButton.icon(
        onPressed: _submitting ? null : () => _pickDate(delivery: false),
        icon: const Icon(Icons.calendar_today_outlined, size: 16),
        label: Text(Formatters.date(isoDate(value))),
      ),
    );
  }

  Widget _deliveryDateField(AppLocalizations l10n) {
    final value = _deliveryDate;
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 44,
            child: OutlinedButton.icon(
              onPressed: _submitting ? null : () => _pickDate(delivery: true),
              icon: const Icon(Icons.calendar_today_outlined, size: 16),
              label: Text(
                value == null
                    ? l10n.salesordersDeliverydate
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
                : () => setState(() => _deliveryDate = null),
          ),
      ],
    );
  }

  Widget _lineRow(AppLocalizations l10n, int index) {
    final line = _lines[index];
    final items = ref.watch(soItemsProvider).valueOrNull ?? const <Item>[];
    // BUG-006: the shared line total (tax and discount included, rounded
    // like the server) — not a bare qty x price sum.
    final amount = calculateItemTotal(line.formItem);

    final itemField = FormFieldShell(
      label: l10n.fieldsItem,
      child: SearchableSelect<int>(
        items: [for (final i in items) i.id],
        selected: line.itemId.isEmpty ? null : int.tryParse(line.itemId),
        labelBuilder: (id) {
          final match = items.where((i) => i.id == id);
          final item = match.isEmpty ? null : match.first;
          return item == null ? '$id' : '${item.itemCode} — ${item.itemName}';
        },
        onChanged: (value) =>
            setState(() => line.itemId = value?.toString() ?? ''),
      ),
    );
    final quantityField = SizedBox(
      width: 86,
      child: TextFormField(
        key: const ValueKey('so-line-quantity'),
        controller: line.quantityController,
        enabled: !_submitting,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: _decoration(),
        validator: (value) => (double.tryParse(value ?? '') ?? -1) > 0
            ? null
            : l10n.commonRequired,
        onChanged: (_) => setState(() {}),
      ),
    );
    final priceField = SizedBox(
      width: 100,
      child: TextFormField(
        key: const ValueKey('so-line-price'),
        controller: line.priceController,
        enabled: !_submitting,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: _decoration(),
        validator: (value) => (double.tryParse(value ?? '') ?? -1) > 0
            ? null
            : l10n.commonRequired,
        onChanged: (_) => setState(() {}),
      ),
    );
    final taxField = SizedBox(
      width: 76,
      child: FormFieldShell(
        label: l10n.fieldsTax,
        child: TextFormField(
          key: const ValueKey('so-line-tax'),
          controller: line.taxRateController,
          enabled: !_submitting,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: _decoration(),
          validator: (value) {
            final rate = double.tryParse(value ?? '') ?? 0;
            return rate < 0 || rate > 100 ? l10n.commonInvalid : null;
          },
          onChanged: (_) => setState(() {}),
        ),
      ),
    );
    final discountTypeField = SizedBox(
      width: 124,
      child: FormFieldShell(
        label: l10n.fieldsDiscount,
        child: DropdownButtonFormField<DiscountType?>(
          initialValue: line.discountType,
          isDense: true,
          isExpanded: true,
          decoration: _decoration(),
          items: [
            DropdownMenuItem<DiscountType?>(
              value: null,
              child: Text(l10n.commonNone),
            ),
            DropdownMenuItem<DiscountType?>(
              value: DiscountType.flat,
              child: Text(l10n.commonAmount),
            ),
            DropdownMenuItem<DiscountType?>(
              value: DiscountType.percentage,
              child: Text(l10n.commonPercent),
            ),
          ],
          onChanged: _submitting
              ? null
              : (value) => setState(() => line.discountType = value),
        ),
      ),
    );
    final discountValueField = SizedBox(
      width: 86,
      child: FormFieldShell(
        label: l10n.fieldsAmount,
        child: TextFormField(
          key: const ValueKey('so-line-discount-value'),
          controller: line.discountValueController,
          enabled: !_submitting || line.discountType == null,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: _decoration(),
          validator: (value) {
            final amount = double.tryParse(value ?? '') ?? 0;
            if (line.discountType == DiscountType.percentage && amount >= 100) {
              return l10n.commonInvalid;
            }
            return null;
          },
          onChanged: (_) => setState(() {}),
        ),
      ),
    );
    final amountField = SizedBox(
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
    );
    final removeButton = SizedBox(
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
    );

    // The seven fields do not fit a narrow window side by side. Below the
    // width that fits them, wrap them so nothing overflows the dialog.
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 760) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: itemField),
              const SizedBox(width: 8),
              quantityField,
              const SizedBox(width: 8),
              priceField,
              const SizedBox(width: 8),
              taxField,
              const SizedBox(width: 8),
              discountTypeField,
              const SizedBox(width: 8),
              discountValueField,
              const SizedBox(width: 8),
              amountField,
              const SizedBox(width: 4),
              removeButton,
            ],
          );
        }
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            SizedBox(width: double.infinity, child: itemField),
            quantityField,
            priceField,
            taxField,
            discountTypeField,
            discountValueField,
            amountField,
            removeButton,
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final customers =
        ref.watch(salesOrderCustomerOptionsProvider).valueOrNull ??
        const <Customer>[];
    final warehouses =
        ref.watch(warehousesProvider).valueOrNull ?? const <Warehouse>[];
    final customerIds = [for (final c in customers) c.id];
    final warehouseIds = [for (final w in warehouses) w.id];

    return MovableDialog(
      dialogId: 'sales_order_form',
      maxWidth: 1320,
      maxHeight: 720,
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
                      ? l10n.salesordersEditsalesorder
                      : l10n.salesordersNewsalesorder,
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
                              label: l10n.salesordersCustomer,
                              required: true,
                              child: SearchableSelect<int>(
                                items: customerIds,
                                selected: _customerId,
                                labelBuilder: (id) {
                                  final match = customers.where(
                                    (c) => c.id == id,
                                  );
                                  final customer = match.isEmpty
                                      ? null
                                      : match.first;
                                  return customer == null
                                      ? '$id'
                                      : '${customer.customerCode} — '
                                            '${customer.customerName}';
                                },
                                validator: (value) => value == null
                                    ? l10n.salesordersErrorCustomerrequired
                                    : null,
                                onChanged: (value) =>
                                    setState(() => _customerId = value),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.salesordersSodate,
                              required: true,
                              child: _dateField(
                                l10n.salesordersSodate,
                                _soDate,
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
                              label: l10n.salesordersDeliverydate,
                              child: _deliveryDateField(l10n),
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
                              : () => setState(() => _lines.add(_SoLine())),
                          icon: const Icon(Icons.add, size: 18),
                          label: Text(l10n.salesordersAdditem),
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
                            : _printSalesOrder,
                        icon: _printing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.print_outlined, size: 18),
                        label: Text(l10n.salesordersPrinta4),
                      ),
                      const SizedBox(width: 8),
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
