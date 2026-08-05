// Sales (invoice) create/edit form — modal dialog over POST/PUT
// /invoices.
//
// Mirrors the server's createInvoice/updateInvoice DTOs: customer_id,
// invoice_date and items are required (400 "Customer, date, and items are
// required"); status defaults to Unpaid; the invoice number is generated
// client-side (the server stores it as-is and has no generator). Item
// amounts are recomputed server-side as qty × unit_price; the client
// sends the grand total (subtotal + tax − invoice-level discount, the
// web-client convention) so the server stores a consistent A/R figure.
//
// Delete lives here too (edit mode): destructive confirm → DELETE
// /invoices/:id → toast + grid refresh.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/invoice.dart'
    show Discount, DiscountType, Invoice, InvoiceItem;
import '../../data/models/customer.dart' show Customer;
import '../../data/models/item.dart' show Item, SaleType;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/invoice_repository.dart'
    show invoiceRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/form_field.dart';
import '../../widgets/searchable_select.dart';
import 'calculations/invoice_calculations.dart'
    show
        calculateDiscount,
        calculateItemTotal,
        calculateSubtotal,
        calculateTax,
        calculateTotal,
        generateInvoiceNo;
import 'invoice_providers.dart';
import 'models/sales_forms.dart'
    show
        CalculableLine,
        DiscountScope,
        EditedField,
        FillableLine,
        flatZeroDiscount;

/// Opens the create ([invoice] == null) or edit form dialog.
Future<void> showSalesFormDialog(BuildContext context, {Invoice? invoice}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => SalesFormDialog(invoice: invoice),
  );
}

/// Mutable form line implementing the calculation interfaces (the shared
/// invoice math only reads qty/rate/tax/discount — see sales_forms.dart).
class _Line implements CalculableLine, FillableLine {
  _Line({this.itemId = ''})
      : quantityController = TextEditingController(),
        rateController = TextEditingController(),
        taxController = TextEditingController();

  @override
  String itemId;

  @override
  String get description => '';

  @override
  num get quantity => double.tryParse(quantityController.text) ?? 0;

  @override
  num get rate => double.tryParse(rateController.text) ?? 0;

  @override
  num get tax => double.tryParse(taxController.text) ?? 0;

  @override
  Discount get discount => flatZeroDiscount;

  @override
  SaleType get saleType => SaleType.packed;

  @override
  num get amount => 0;

  @override
  EditedField? get lastEditedField => null;

  final TextEditingController quantityController;
  final TextEditingController rateController;
  final TextEditingController taxController;

  void dispose() {
    quantityController.dispose();
    rateController.dispose();
    taxController.dispose();
  }
}

class SalesFormDialog extends ConsumerStatefulWidget {
  const SalesFormDialog({super.key, this.invoice});

  /// Null → create; otherwise pre-fills and PUTs to `invoices/:id`.
  final Invoice? invoice;

  @override
  ConsumerState<SalesFormDialog> createState() => _SalesFormDialogState();
}

class _SalesFormDialogState extends ConsumerState<SalesFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _notesController;
  late final TextEditingController _discountController;
  final List<_Line> _lines = [];

  int? _customerId;
  String? _status;
  late DateTime _invoiceDate;
  late DateTime _dueDate;

  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.invoice != null;

  @override
  void initState() {
    super.initState();
    final invoice = widget.invoice;
    _notesController = TextEditingController(text: invoice?.notes ?? '');
    _discountController = TextEditingController(
      text: invoice == null ? '0' : _numText(invoice.discountValue ?? 0),
    );
    _customerId = invoice?.customerId;
    _status = invoice?.status ?? 'Unpaid';
    _invoiceDate =
        DateTime.tryParse(invoice?.invoiceDate ?? '') ?? DateTime.now();
    _dueDate = DateTime.tryParse(invoice?.dueDate ?? '') ?? _invoiceDate;
    if (invoice != null) {
      // The list endpoint omits `items`; pull the full detail if needed.
      if (invoice.items == null || invoice.items!.isEmpty) {
        _loadInvoiceDetail(invoice.id);
      } else {
        _prefillLines(invoice.items!);
      }
    } else {
      _lines.add(_Line());
    }
  }

  void _prefillLines(List<InvoiceItem> items) {
    for (final item in items) {
      final line = _Line(itemId: item.itemId.toString())
        ..quantityController.text = _numText(item.quantity)
        ..rateController.text = _numText(item.unitPrice)
        ..taxController.text = _numText(item.taxRate);
      _lines.add(line);
    }
    if (_lines.isEmpty) _lines.add(_Line());
  }

  Future<void> _loadInvoiceDetail(int id) async {
    final result = await ref.read(invoiceRepositoryProvider).invoice(id);
    switch (result) {
      case ApiSuccess(:final data):
        if (!mounted) return;
        setState(() {
          _prefillLines(data.items ?? const <InvoiceItem>[]);
        });
      case ApiFailure(:final error):
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load invoice: ${error.message}')),
        );
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    _discountController.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  static String _numText(num value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();

  static String _isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  List<_Line> get _filledLines =>
      _lines.where((line) => line.itemId.isNotEmpty).toList();

  Future<void> _pickDate({required bool isDue}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isDue ? _dueDate : _invoiceDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isDue) {
        _dueDate = picked;
      } else {
        _invoiceDate = picked;
      }
    });
  }

  num get _invoiceDiscountValue =>
      double.tryParse(_discountController.text) ?? 0;

  Discount get _invoiceDiscount =>
      Discount(type: DiscountType.flat, value: _invoiceDiscountValue);

  Map<String, dynamic> _buildBody() {
    final notes = _notesController.text.trim();
    final filled = _filledLines;
    return {
      if (!_isEdit) 'invoice_no': generateInvoiceNo(),
      'customer_id': _customerId!,
      'invoice_date': _isoDate(_invoiceDate),
      'due_date': _isoDate(_dueDate),
      'status': _status!,
      'discount_scope': 'invoice',
      'discount_type': 'flat',
      'discount_value': _invoiceDiscountValue,
      'items': [
        for (final line in filled)
          {
            'item_id': int.parse(line.itemId),
            'quantity': line.quantity,
            'unit_price': line.rate,
            'tax_rate': line.tax,
            'discount_type': 'none',
            'discount_value': 0,
          },
      ],
      'total_amount': calculateTotal(
        filled,
        DiscountScope.invoice,
        _invoiceDiscount,
      ),
      if (notes.isNotEmpty) 'notes': notes,
    };
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_customerId == null) {
      setState(() => _error = l10n.salesErrorCustomerRequired);
      return;
    }
    if (_filledLines.isEmpty) {
      setState(() => _error = l10n.salesErrorItemsRequired);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final repo = ref.read(invoiceRepositoryProvider);
    final result = _isEdit
        ? await repo.update(widget.invoice!.id, _buildBody())
        : await repo.create(_buildBody());
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        ref.invalidate(invoicesProvider);
        Navigator.of(context).pop();
        showAppToast(context, l10n.salesInvoicesaved);
      case ApiFailure(:final error):
        setState(() {
          _submitting = false;
          _error = error.message;
        });
    }
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.commonDelete,
      message: l10n.salesConfirmdelete,
      confirmLabel: l10n.commonDelete,
      cancelLabel: l10n.commonCancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    final result =
        await ref.read(invoiceRepositoryProvider).delete(widget.invoice!.id);
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        ref.invalidate(invoicesProvider);
        Navigator.of(context).pop();
        showAppToast(context, l10n.salesInvoicedeleted);
      case ApiFailure(:final error):
        setState(() {
          _submitting = false;
          _error = error.message;
        });
    }
  }

  InputDecoration _decoration() => const InputDecoration(
        isDense: true,
        border: OutlineInputBorder(),
      );

  Widget _dateField(String label, DateTime value, {required bool isDue}) {
    return SizedBox(
      height: 44,
      child: OutlinedButton.icon(
        onPressed: _submitting ? null : () => _pickDate(isDue: isDue),
        icon: const Icon(Icons.calendar_today_outlined, size: 16),
        label: Text(Formatters.date(_isoDate(value))),
      ),
    );
  }

  Widget _lineRow(AppLocalizations l10n, int index) {
    final line = _lines[index];
    final items = ref.watch(invoiceItemsProvider).valueOrNull ??
        const <Item>[];
    final amount = calculateItemTotal(
      line,
      discountScope: DiscountScope.item,
    );
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
            controller: line.rateController,
            enabled: !_submitting,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _decoration(),
            validator: (value) => double.tryParse(value ?? '') == null
                ? l10n.commonRequired
                : null,
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 70,
          child: TextFormField(
            controller: line.taxController,
            enabled: !_submitting,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _decoration(),
            validator: (value) {
              final parsed = double.tryParse(value ?? '');
              if (parsed != null && parsed < 0) return l10n.commonRequired;
              return null;
            },
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
    final customers = ref.watch(invoiceCustomersProvider);
    final filled = _filledLines;
    final subtotal = calculateSubtotal(filled);
    final tax = calculateTax(filled, discountScope: DiscountScope.invoice);
    final discount = calculateDiscount(
      filled,
      DiscountScope.invoice,
      _invoiceDiscount,
    );
    final total = calculateTotal(filled, DiscountScope.invoice, _invoiceDiscount);

    final customerItems = [
      for (final c in customers.valueOrNull ?? const <Customer>[]) c.id,
    ];

    Widget totalsRow(String label, num value, {bool bold = false}) => Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 110,
              child: Text(
                Formatters.currency(value),
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                    ),
              ),
            ),
          ],
        );

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _isEdit
                            ? l10n.salesEditinvoice
                            : l10n.salesNewinvoice,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.commonClose,
                      icon: const Icon(Icons.close),
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).pop(),
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
                      // Customer + dates + status.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: FormFieldShell(
                              label: l10n.fieldsCustomer,
                              required: true,
                              child: SearchableSelect<int>(
                                items: customerItems,
                                selected: _customerId,
                                labelBuilder: (id) {
                                  final match = (customers.valueOrNull ??
                                          const <Customer>[])
                                      .where((c) => c.id == id);
                                  return match.isEmpty
                                      ? '$id'
                                      : match.first.customerName;
                                },
                                onChanged: (value) =>
                                    setState(() => _customerId = value),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: FormFieldShell(
                              label: l10n.fieldsDate,
                              required: true,
                              child: _dateField(
                                l10n.fieldsDate,
                                _invoiceDate,
                                isDue: false,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: FormFieldShell(
                              label: l10n.salesDuedate,
                              child: _dateField(
                                l10n.salesDuedate,
                                _dueDate,
                                isDue: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.fieldsStatus,
                              child: DropdownButtonFormField<String>(
                                initialValue: _status,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                  contentPadding:
                                      EdgeInsets.symmetric(horizontal: 10),
                                ),
                                items: [
                                  for (final s in _statusValues)
                                    DropdownMenuItem(
                                      value: s,
                                      child: Text(_statusLabel(l10n, s)),
                                    ),
                                ],
                                onChanged: _submitting
                                    ? null
                                    : (value) =>
                                        setState(() => _status = value),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        l10n.salesItems,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      // Items header row.
                      Row(
                        children: [
                          const Expanded(flex: 3, child: SizedBox()),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 86,
                            child: Text(
                              l10n.fieldsQuantity,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 100,
                            child: Text(
                              l10n.salesRate,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 70,
                            child: Text(
                              l10n.salesTax,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 100,
                            child: Text(
                              l10n.fieldsAmount,
                              textAlign: TextAlign.right,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                          const SizedBox(width: 38),
                        ],
                      ),
                      const SizedBox(height: 6),
                      for (var i = 0; i < _lines.length; i++) ...[
                        _lineRow(l10n, i),
                        const SizedBox(height: 8),
                      ],
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _submitting
                              ? null
                              : () => setState(() => _lines.add(_Line())),
                          icon: const Icon(Icons.add, size: 16),
                          label: Text(l10n.salesAdditem),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Totals panel.
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      TextFormField(
                                        controller: _discountController,
                                        enabled: !_submitting,
                                        keyboardType:
                                            const TextInputType
                                                .numberWithOptions(
                                              decimal: true,
                                            ),
                                        decoration: InputDecoration(
                                          isDense: true,
                                          border: OutlineInputBorder(),
                                          labelText: l10n.fieldsDiscount,
                                        ),
                                        onChanged: (_) => setState(() {}),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      totalsRow(l10n.salesSubtotal, subtotal),
                                      const SizedBox(height: 4),
                                      totalsRow(l10n.salesTax, tax),
                                      const SizedBox(height: 4),
                                      totalsRow(l10n.salesDiscount, discount),
                                      const Divider(height: 10),
                                      totalsRow(
                                        l10n.salesGrandtotal,
                                        total,
                                        bold: true,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      FormFieldShell(
                        label: l10n.fieldsNotes,
                        child: TextFormField(
                          controller: _notesController,
                          enabled: !_submitting,
                          maxLines: 2,
                          decoration: _decoration(),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .errorContainer
                                .withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                child: Row(
                  children: [
                    if (_isEdit)
                      OutlinedButton.icon(
                        onPressed: _submitting ? null : _delete,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: Text(l10n.commonDelete),
                        style: OutlinedButton.styleFrom(
                          foregroundColor:
                              Theme.of(context).colorScheme.error,
                        ),
                      ),
                    const Spacer(),
                    OutlinedButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: Text(l10n.commonCancel),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: _submitting ? null : _submit,
                      icon: _submitting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined, size: 18),
                      label: Text(l10n.commonSave),
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

/// All invoice statuses offered in the form dropdown (server vocabulary —
/// "Partially Paid"/"Partially Returned" are two-word values).
const List<String> _statusValues = [
  'Unpaid',
  'Paid',
  'Partially Paid',
  'Overdue',
  'Sent',
  'Draft',
  'Cancelled',
  'Returned',
  'Partially Returned',
];

String _statusLabel(AppLocalizations l10n, String status) =>
    switch (status) {
      'Draft' => l10n.statusDraft,
      'Sent' => l10n.statusSent,
      'Paid' => l10n.statusPaid,
      'Unpaid' => l10n.statusUnpaid,
      'Overdue' => l10n.statusOverdue,
      'Cancelled' => l10n.statusCancelled,
      'Partially Paid' => l10n.statusPartiallypaid,
      'Returned' => l10n.statusReturned,
      'Partially Returned' => l10n.statusPartiallyreturned,
      _ => status,
    };
