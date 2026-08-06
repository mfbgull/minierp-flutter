// Sales (invoice) create/edit form — full routed page. Route: `/sales/form`
// — create when no `extra`, edit when the `Invoice` is passed via `extra`.
//
// Line items are a PlutoGrid with editing disabled; every cell is a custom
// renderer (SerialCell / DescriptionCell / LineCell / RemoveCell) that
// implements the AG-Grid-style interaction model from the web client —
// single-cell edit mode with arrow/Enter/Tab/Escape navigation, the
// client-side item search dropdown, per-scope discount column, loose-line
// amount editing, and the price-history hint on rate edits. All movement
// and commit semantics live in `GridNavController`.
//
// The payment panel (create: record checkbox + methods; edit: existing
// payments + immediate recording) sits beside the grid on desktop. Create
// mode posts payments right after the invoice is created; edit mode keeps
// deleted payment ids in `deleted_payments` and records new payments via
// `POST /payments`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/customer.dart' show Customer;
import '../../data/models/invoice.dart'
    show
        Discount,
        DiscountType,
        Invoice,
        InvoiceItem,
        InvoicePaymentRecord,
        PaymentMethod;
import '../../data/models/item.dart' show Item, SaleType;
import '../../data/models/price_history.dart' show ItemPriceHistory;
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
        calculateSubtotal,
        calculateTax,
        calculateTotal,
        generateInvoiceNo;
import 'calculations/invoice_rules.dart'
    show doesPaymentExceedBalance, isValidPaymentAmount;
import 'invoice_providers.dart';
import 'invoice_return_dialog.dart' show showInvoiceReturnDialog;
import 'line_cells.dart' show DescriptionCell, LineCell, RemoveCell, SerialCell;
import 'line_items_grid.dart' show GridNavController, LineColumn, LineRowData;
import 'models/sales_forms.dart' show DiscountScope;
import 'payment_panel.dart' show PaymentPanel, kPaymentMethods;
import 'price_history_hint.dart' show PriceHistoryHint;

/// Create ([invoice] == null) or edit page for an invoice.
class SalesInvoiceFormPage extends ConsumerStatefulWidget {
  const SalesInvoiceFormPage({super.key, this.invoice});

  /// Null → create; otherwise pre-fills and PUTs to `invoices/:id`.
  final Invoice? invoice;

  @override
  ConsumerState<SalesInvoiceFormPage> createState() =>
      _SalesInvoiceFormPageState();
}

class _SalesInvoiceFormPageState extends ConsumerState<SalesInvoiceFormPage> {
  static const double _gridHeight = 260;

  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _notesController;
  late final TextEditingController _discountController;
  final TextEditingController _paymentNotes = TextEditingController();

  /// Line-item grid rows — the single source of truth for line data. The
  /// grid's state manager wraps this exact list, so it is mutated in
  /// place (never reassigned after the grid exists).
  List<PlutoRow> _rows = [];

  PlutoGridStateManager? _gridStateManager;
  List<PlutoColumn>? _columns;
  PlutoColumn? _discountColumn;

  late final GridNavController _nav;

  int? _customerId;
  String? _status;
  late DateTime _invoiceDate;
  late DateTime _dueDate;

  /// Discount scope (Invoice/Item radio) — decides the discount column.
  DiscountScope _scope = DiscountScope.invoice;

  bool _submitting = false;
  String? _error;

  // Payment state. Matches the reference create page: new invoices start
  // with "Record payment now" checked and one default Cash method row so
  // the amount field is visible without clicking "Add method".
  bool _recordPayment = true;
  late DateTime _paymentDate;
  final List<PaymentMethod> _paymentMethods = [
    PaymentMethod(id: 0, method: kPaymentMethods.first, amount: 0),
  ];
  List<InvoicePaymentRecord> _existingPayments = const [];
  final Set<int> _deletedPayments = {};
  int _methodSeq = 1;
  bool _recordingPayment = false;

  // Price-history hint (rate cell).
  ItemPriceHistory? _priceHistory;
  PlutoRow? _hintRow;
  bool _hintFetching = false;

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
    _paymentDate = _invoiceDate;
    _scope = invoice?.discountScope == 'item'
        ? DiscountScope.item
        : DiscountScope.invoice;

    _nav = GridNavController(
      scopeOf: () => _scope,
      rowsOf: () => _rows,
      onGridChanged: () => _markGridDirty(),
      onMoveResolved: (_) => _markGridDirty(),
    )..onAppendRow = _addLine;

    if (invoice != null) {
      if (invoice.items == null || invoice.items!.isEmpty) {
        _rows.add(_emptyLineRow());
        _loadInvoiceDetail(invoice.id);
      } else {
        _setLines(invoice.items!);
      }
      _loadExistingPayments(invoice.id);
    } else {
      _rows.add(_emptyLineRow());
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    _discountController.dispose();
    _paymentNotes.dispose();
    _nav.dispose();
    super.dispose();
  }

  void _markGridDirty() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  // ── Rows ──────────────────────────────────────────────────────

  /// Every column + hidden data field. PlutoGrid requires one cell per
  /// column per row (`row.cells[field]!`), so the discount/amount cells
  /// are always present even when the column is hidden/read-only.
  Map<String, PlutoCell> _emptyCells() => {
        'serial': PlutoCell(value: ''),
        'description': PlutoCell(value: ''),
        'qty': PlutoCell(value: 1),
        'rate': PlutoCell(value: 0),
        'discount': PlutoCell(value: 0),
        'discount_type': PlutoCell(value: 'none'),
        'tax': PlutoCell(value: 0),
        'amount': PlutoCell(value: 0),
        'item': PlutoCell(value: ''),
        'sale_type': PlutoCell(value: SaleType.packed.value),
        'uom': PlutoCell(value: ''),
        'qty_prec': PlutoCell(value: 0),
        'round_step': PlutoCell(value: ''),
        'last_edited': PlutoCell(value: ''),
        'remove': PlutoCell(value: ''),
      };

  PlutoRow _emptyLineRow() => PlutoRow(cells: _emptyCells());

  PlutoRow _lineRow(InvoiceItem item) => PlutoRow(
        cells: {
          ..._emptyCells(),
          'item': PlutoCell(value: item.itemId),
          'qty': PlutoCell(value: item.quantity),
          'rate': PlutoCell(value: item.unitPrice),
          'tax': PlutoCell(value: item.taxRate),
        },
      );

  void _setLines(List<InvoiceItem> items) {
    final rows = [
      for (final item in items)
        _lineRow(item),
    ];
    if (rows.isEmpty) rows.add(_emptyLineRow());
    final manager = _gridStateManager;
    if (manager == null) {
      _rows = rows;
      return;
    }
    manager.removeAllRows(notify: false);
    manager.insertRows(manager.rows.length, rows);
    setState(() {});
  }

  Future<void> _loadInvoiceDetail(int id) async {
    final result = await ref.read(invoiceRepositoryProvider).invoice(id);
    switch (result) {
      case ApiSuccess(:final data):
        if (!mounted) return;
        setState(() {
          _setLines(data.items ?? const <InvoiceItem>[]);
        });
      case ApiFailure(:final error):
        if (!mounted) return;
        showAppToast(context, 'Failed to load invoice: ${error.message}');
    }
  }

  Future<void> _loadExistingPayments(int id) async {
    final result = await ref.read(invoiceRepositoryProvider).invoicePayments(id);
    switch (result) {
      case ApiSuccess(:final data):
        if (!mounted) return;
        setState(() => _existingPayments = data);
      case ApiFailure():
        break; // non-blocking; the panel just shows no history
    }
  }

  void _addLine() {
    final manager = _gridStateManager;
    if (manager == null) {
      _rows.add(_emptyLineRow());
      _markGridDirty();
      return;
    }
    final row = _emptyLineRow();
    manager.insertRows(manager.rows.length, [row]);
    setState(() {});
    _nav.focusNewRow(row);
  }

  void _removeLine(PlutoRow row) {
    final manager = _gridStateManager;
    _nav.handleRowRemoved(row);
    if (manager == null) {
      _rows.remove(row);
      _markGridDirty();
      return;
    }
    manager.removeRows([row]);
    setState(() {});
  }

  List<LineRowData> get _filledLines => [
        for (final row in _rows)
          if (LineRowData(row).itemId.isNotEmpty || LineRowData(row).description.isNotEmpty)
            LineRowData(row),
      ];

  /// Writes a selected item's defaults into the line (reference
  /// `onItemSelect`): item id, description, selling price, tax, sale
  /// type/uom/precision, amount=0, then lands on the quantity cell.
  void _onItemSelected(PlutoRow row, Item item) {
    final data = LineRowData(row);
    data
      ..itemId = '${item.id}'
      ..description = item.itemName
      ..rate = item.standardSellingPrice ?? item.standardPrice ?? 0
      ..tax = 0
      ..quantity = 1
      ..amount = 0
      ..saleType = item.saleType
      ..unitOfMeasure = item.unitOfMeasure
      ..qtyDecimalPrecision = item.qtyDecimalPrecision ?? 0
      ..roundingStep = item.roundingStep
      ..discountValue = 0
      ..discountType = DiscountType.flat
      ..lastEditedField = null;
    setState(() {});
    _nav.moveToCell(row, LineColumn.quantity);
  }

  // ── Price hint (rate edits) ───────────────────────────────────

  Future<void> _onRateEdit(PlutoRow row) async {
    final data = LineRowData(row);
    final itemId = int.tryParse(data.itemId);
    final customerId = _customerId;
    if (itemId == null || customerId == null) {
      _priceHistory = null;
      return;
    }
    if (_hintFetching) return;
    _hintFetching = true;
    _hintRow = row;
    _priceHistory = null;
    final result = await ref
        .read(invoiceRepositoryProvider)
        .itemCustomerPriceHistory(itemId: itemId, customerId: customerId);
    _hintFetching = false;
    if (!mounted || _hintRow != row) return;
    // The endpoint is advisory; any failure means "no hint" (and the
    // endpoint does not exist server-side yet — degrades silently).
    setState(() {
      _priceHistory = switch (result) {
        ApiSuccess(:final data) when data.hasHistory => data,
        _ => null,
      };
    });
  }

  // ── Dates / discount ──────────────────────────────────────────

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

  void _setScope(DiscountScope scope) {
    if (scope == _scope) return;
    _priceHistory = null;
    setState(() => _scope = scope);
    // Hide/show the discount column without rebuilding the grid.
    final manager = _gridStateManager;
    if (manager != null && _discountColumn != null) {
      manager.hideColumn(_discountColumn!, !(scope == DiscountScope.item));
    }
  }

  num get _invoiceDiscountValue =>
      double.tryParse(_discountController.text) ?? 0;

  Discount get _invoiceDiscount =>
      Discount(type: DiscountType.flat, value: _invoiceDiscountValue);

  // ── Payment helpers ───────────────────────────────────────────

  num get _paymentSum => _paymentMethods.fold<num>(0, (s, m) => s + m.amount);

  num get _remainingBalance => _isEdit
      ? (widget.invoice!.balanceAmount - _paymentSum)
      : (calculateTotal(_filledLines, _scope, _invoiceDiscount) - _paymentSum);

  void _addPaymentMethod() {
    setState(() {
      _paymentMethods.add(PaymentMethod(
        id: _methodSeq++,
        method: kPaymentMethods.first,
        amount: 0,
      ));
    });
  }

  void _removePaymentMethod(int id) {
    setState(() => _paymentMethods.removeWhere((m) => m.id == id));
  }

  void _updatePaymentMethod(int id, String field, Object? value) {
    setState(() {
      for (final m in _paymentMethods) {
        if (m.id != id) continue;
        switch (field) {
          case 'method':
            _paymentMethods[_paymentMethods.indexOf(m)] = PaymentMethod(
              id: m.id,
              method: value as String,
              amount: m.amount,
              referenceNo: m.referenceNo,
            );
          case 'amount':
            _paymentMethods[_paymentMethods.indexOf(m)] = PaymentMethod(
              id: m.id,
              method: m.method,
              amount: (value as num?) ?? 0,
              referenceNo: m.referenceNo,
            );
          case 'reference_no':
            _paymentMethods[_paymentMethods.indexOf(m)] = PaymentMethod(
              id: m.id,
              method: m.method,
              amount: m.amount,
              referenceNo: value as String?,
            );
        }
      }
    });
  }

  Future<void> _pickPaymentDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paymentDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) setState(() => _paymentDate = picked);
  }

  bool _validatePayment() {
    final l10n = AppLocalizations.of(context)!;
    if (!isValidPaymentAmount(_paymentSum)) {
      showAppToast(context, l10n.paymentsErrorAmountGreaterThanZero);
      return false;
    }
    if (doesPaymentExceedBalance(_paymentSum, _remainingBalance)) {
      showAppToast(
        context,
        l10n.paymentsErrorAmountExceedsBalance(
          Formatters.currency(_remainingBalance < 0 ? 0 : _remainingBalance),
        ),
      );
      return false;
    }
    return true;
  }

  /// Edit mode only: post each positive method sequentially.
  Future<void> _recordPayments() async {
    if (!_validatePayment()) return;
    setState(() => _recordingPayment = true);
    final repo = ref.read(invoiceRepositoryProvider);
    final l10n = AppLocalizations.of(context)!;
    final bodies = _paymentBodies();
    var ok = true;
    for (final body in bodies) {
      final result = await repo.createInvoicePayment(body);
      if (result case ApiFailure(:final error)) {
        ok = false;
        if (mounted) showAppToast(context, error.message);
        break;
      }
    }
    if (!mounted) return;
    setState(() {
      _recordingPayment = false;
      _paymentMethods.clear();
      _methodSeq = 0;
    });
    if (ok) {
      showAppToast(context, l10n.salesPaymentrecorded);
      await _loadExistingPayments(widget.invoice!.id);
      _markGridDirty();
    }
  }

  List<Map<String, dynamic>> _paymentBodies() => [
        for (final m in _paymentMethods)
          if (m.amount > 0)
            {
              'customer_id': _customerId!,
              'payment_date': _isoDate(_paymentDate),
              'amount': m.amount,
              'payment_method': m.method,
              if (m.referenceNo != null && m.referenceNo!.isNotEmpty)
                'reference_no': m.referenceNo,
              'description': 'Payment for ${widget.invoice?.invoiceNo ?? ''}',
              if (_paymentNotes.text.trim().isNotEmpty)
                'notes': _paymentNotes.text.trim(),
              'invoice_allocations': [
                {
                  'invoice_id': _isEdit ? widget.invoice!.id : 0,
                  'amount': m.amount,
                },
              ],
            },
      ];

  void _onDeletePayment(InvoicePaymentRecord p) {
    setState(() => _deletedPayments.add(p.id));
  }

  Future<void> _onEditPayment(InvoicePaymentRecord p) async {
    final l10n = AppLocalizations.of(context)!;
    final amountController =
        TextEditingController(text: _numText(p.amount));
    final refController =
        TextEditingController(text: p.referenceNo ?? '');
    final updated = await showDialog<(num, String)>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.salesEditpayment),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: l10n.fieldsAmount),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: refController,
              decoration: InputDecoration(labelText: l10n.salesReference),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop((
              num.tryParse(amountController.text) ?? 0,
              refController.text.trim(),
            )),
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
    amountController.dispose();
    refController.dispose();
    if (updated == null || !mounted) return;

    setState(() => _recordingPayment = true);
    final result = await ref
        .read(invoiceRepositoryProvider)
        .updatePayment(p.id, {
          'amount': updated.$1,
          if (updated.$2.isNotEmpty) 'reference_no': updated.$2,
        });
    if (!mounted) return;
    setState(() => _recordingPayment = false);
    switch (result) {
      case ApiSuccess():
        showAppToast(context, l10n.salesPaymentupdated);
        await _loadExistingPayments(widget.invoice!.id);
      case ApiFailure(:final error):
        showAppToast(context, error.message);
    }
  }

  // ── Submit ────────────────────────────────────────────────────

  Map<String, dynamic> _buildBody() {
    final notes = _notesController.text.trim();
    final filled = _filledLines;
    final scope = _scope == DiscountScope.item ? 'item' : 'invoice';
    return {
      if (!_isEdit) 'invoice_no': generateInvoiceNo(),
      'customer_id': _customerId!,
      'invoice_date': _isoDate(_invoiceDate),
      'due_date': _isoDate(_dueDate),
      'status': _status!,
      'discount_scope': scope,
      'discount_type': 'flat',
      'discount_value': _scope == DiscountScope.invoice
          ? _invoiceDiscountValue
          : 0,
      'items': [
        for (final line in filled)
          {
            'item_id': int.tryParse(line.itemId) ?? 0,
            'description': line.description,
            'quantity': line.quantity,
            'unit_price': line.rate,
            'tax_rate': line.tax,
            'discount_type': line.row.cells['discount_type']?.value ?? 'none',
            'discount_value': line.discountValue,
            if (line.isLoose) 'amount': line.amount,
          },
      ],
      'total_amount': calculateTotal(filled, _scope, _invoiceDiscount),
      if (notes.isNotEmpty) 'notes': notes,
      if (_isEdit && _deletedPayments.isNotEmpty)
        'deleted_payments': _deletedPayments.toList(),
    };
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_customerId == null) {
      setState(() => _error = l10n.salesErrorCustomerRequired);
      return;
    }
    final filled = _filledLines;
    if (filled.isEmpty) {
      setState(() => _error = l10n.salesErrorItemsRequired);
      return;
    }
    if (filled.any((line) => line.quantity <= 0)) {
      setState(() => _error = _invalidQuantityMessage);
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
      case ApiSuccess(:final data):
        // Create mode: record any positive payment methods against the
        // fresh invoice, sequentially.
        if (!_isEdit && _recordPayment && _paymentMethods.any((m) => m.amount > 0)) {
          final bodies = [
            for (final m in _paymentMethods)
              if (m.amount > 0)
                {
                  'customer_id': _customerId!,
                  'payment_date': _isoDate(_paymentDate),
                  'amount': m.amount,
                  'payment_method': m.method,
                  if (m.referenceNo != null && m.referenceNo!.isNotEmpty)
                    'reference_no': m.referenceNo,
                  'description': 'Payment for ${data.invoiceNo}',
                  if (_paymentNotes.text.trim().isNotEmpty)
                    'notes': _paymentNotes.text.trim(),
                  'invoice_allocations': [
                    {'invoice_id': data.id, 'amount': m.amount},
                  ],
                },
          ];
          for (final body in bodies) {
            final paymentResult = await repo.createInvoicePayment(body);
            if (paymentResult case ApiFailure(:final error)) {
              if (mounted) showAppToast(context, error.message);
            }
          }
        }
        if (!mounted) return;
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

  // ── Columns ───────────────────────────────────────────────────

  List<PlutoColumn> _buildColumns(AppLocalizations l10n) {
    PlutoColumn column(
      String field,
      String title,
      double width,
      PlutoColumnRenderer renderer, {
      PlutoColumnTextAlign align = PlutoColumnTextAlign.left,
    }) => PlutoColumn(
          title: title,
          field: field,
          type: PlutoColumnType.text(),
          enableEditingMode: false,
          enableContextMenu: false,
          width: width,
          textAlign: align,
          renderer: renderer,
        );

    final result = <PlutoColumn>[
      column('serial', '#', 44, (ctx) => SerialCell(index: ctx.rowIdx)),
      column('description', l10n.fieldsItem, 240, (ctx) => DescriptionCell(
            nav: _nav,
            row: ctx.row,
            items: _searchPool,
            formatCurrency: Formatters.currency,
            onItemSelected: _onItemSelected,
          )),
      column('qty', l10n.fieldsQuantity, 96, (ctx) => LineCell(
            nav: _nav,
            row: ctx.row,
            column: LineColumn.quantity,
          ), align: PlutoColumnTextAlign.end),
      column('rate', l10n.salesRate, 110, (ctx) => LineCell(
            nav: _nav,
            row: ctx.row,
            column: LineColumn.rate,
            onBeginEdit: _onRateEdit,
            overlayBuilder: () => _priceHintFor(ctx.row),
          ), align: PlutoColumnTextAlign.end),
      column('discount', l10n.fieldsDiscount, 96, (ctx) => LineCell(
            nav: _nav,
            row: ctx.row,
            column: LineColumn.discountValue,
          ), align: PlutoColumnTextAlign.end),
      column('tax', l10n.salesTax, 80, (ctx) => LineCell(
            nav: _nav,
            row: ctx.row,
            column: LineColumn.tax,
          ), align: PlutoColumnTextAlign.end),
      column('amount', l10n.fieldsAmount, 120, (ctx) => LineCell(
            nav: _nav,
            row: ctx.row,
            column: LineColumn.amount,
          ), align: PlutoColumnTextAlign.end),
      column('remove', '', 52, (ctx) => RemoveCell(
            onRemove: () => _removeLine(ctx.row),
          )),
    ];
    for (final c in result) {
      if (c.field == 'discount') _discountColumn = c;
    }
    return result;
  }

  Widget? _priceHintFor(PlutoRow row) {
    final history = _priceHistory;
    final data = LineRowData(row);
    if (history == null || _hintRow != row) return null;
    return PriceHistoryHint(
      history: history,
      currentPrice: data.rate,
    );
  }

  // ── Layout ────────────────────────────────────────────────────

  Widget _buildGrid(AppLocalizations l10n) {
    final columns = _columns;
    if (columns == null) {
      return SizedBox(
        height: _gridHeight,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const CircularProgressIndicator(),
        ),
      );
    }
    return SizedBox(
      height: _gridHeight,
      child: PlutoGrid(
        columns: columns,
        rows: _rows,
        onLoaded: (event) {
          _gridStateManager = event.stateManager;
          if (_discountColumn != null && _scope == DiscountScope.invoice) {
            event.stateManager.hideColumn(_discountColumn!, true);
          }
        },
        onChanged: (_) => _markGridDirty(),
        onRowsMoved: (_) => setState(() {}),
      ),
    );
  }

  Widget _scopeToggle(AppLocalizations l10n) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(l10n.salesDiscountscope, style: const TextStyle(fontSize: 12)),
        _scopeChip(l10n.salesInvoice, DiscountScope.invoice),
        _scopeChip(l10n.salesPeritem, DiscountScope.item),
      ],
    );
  }

  Widget _scopeChip(String label, DiscountScope scope) {
    final selected = _scope == scope;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      visualDensity: VisualDensity.compact,
      onSelected: _submitting
          ? null
          : (_) => _setScope(scope),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final customers = ref.watch(invoiceCustomersProvider);
    final itemsAsync = ref.watch(invoiceItemsProvider);
    final items = itemsAsync.valueOrNull ?? const <Item>[];

    if (_columns == null && items.isNotEmpty) {
      _columns = _buildColumns(l10n);
    }

    final filled = _filledLines;
    final subtotal = calculateSubtotal(filled);
    final tax = calculateTax(filled, discountScope: _scope);
    final discount = calculateDiscount(filled, _scope, _invoiceDiscount);
    final total = calculateTotal(filled, _scope, _invoiceDiscount);

    final customerItems = [
      for (final c in customers.valueOrNull ?? const <Customer>[]) c.id,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? l10n.salesEditinvoice : l10n.salesNewinvoice),
        actions: [
          if (_isEdit)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: () => showInvoiceReturnDialog(
                  context,
                  invoiceId: widget.invoice!.id,
                ),
                icon: const Icon(Icons.assignment_return_outlined, size: 18),
                label: Text(l10n.salesreturnsProcessreturn),
              ),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Customer + dates.
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
                                : (value) => setState(() => _status = value),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: _scopeToggle(l10n)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    l10n.salesItems,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  _buildGrid(l10n),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: _submitting ? null : _addLine,
                        icon: const Icon(Icons.add, size: 16),
                        label: Text(l10n.salesAdditem),
                      ),
                      const Spacer(),
                      // Desktop: grid (left) + payment panel (right) side
                      // by side; below 900px they stack.
                      Text(
                        '${l10n.salesGrandtotal}: ${Formatters.currency(total)}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 720;
                      final grid = _totalsAndGrid(l10n, subtotal, tax,
                          discount, total, filled);
                      final panel = PaymentPanel(
                        isEdit: _isEdit,
                        recordPayment: _recordPayment,
                        paymentDate: _paymentDate,
                        methods: _paymentMethods,
                        existingPayments: _existingPayments,
                        deletedPayments: _deletedPayments,
                        total: total,
                        paidAmount: widget.invoice?.paidAmount ?? 0,
                        balance: _remainingBalance < 0
                            ? 0
                            : _remainingBalance,
                        saving: _submitting || _recordingPayment,
                        onRecordChanged: (v) =>
                            setState(() => _recordPayment = v),
                        onPickPaymentDate: _pickPaymentDate,
                        onPaymentNotesChanged: (v) =>
                            _paymentNotes.text = v,
                        onAddMethod: _addPaymentMethod,
                        onRemoveMethod: _removePaymentMethod,
                        onUpdateMethod: _updatePaymentMethod,
                        onRecord: () => _recordPayments(),
                        onDeletePayment: _onDeletePayment,
                        onEditPayment: _onEditPayment,
                      );
                      if (wide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: grid),
                            const SizedBox(width: 12),
                            SizedBox(width: 330, child: panel),
                          ],
                        );
                      }
                      return Column(
                        children: [grid, const SizedBox(height: 12), panel],
                      );
                    },
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
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
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
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save_outlined, size: 18),
                        label: Text(l10n.commonSave),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Totals card + discount field (invoice scope) / per-line hints.
  Widget _totalsAndGrid(
    AppLocalizations l10n,
    num subtotal,
    num tax,
    num discount,
    num total,
    List<LineRowData> filled,
  ) {
    Widget totalsRow(String label, num value, {bool bold = false}) => Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                label,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (_scope == DiscountScope.invoice) ...[
                Expanded(
                  child: TextFormField(
                    controller: _discountController,
                    enabled: !_submitting,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      labelText: l10n.fieldsDiscount,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 16),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    totalsRow(l10n.salesSubtotal, subtotal),
                    const SizedBox(height: 4),
                    totalsRow(l10n.salesTax, tax),
                    if (_scope == DiscountScope.invoice) ...[
                      const SizedBox(height: 4),
                      totalsRow(l10n.salesDiscount, discount),
                    ],
                    const Divider(height: 10),
                    totalsRow(l10n.salesGrandtotal, total, bold: true),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Item> get _searchPool {
    final items = ref.read(invoiceItemsProvider).valueOrNull ??
        const <Item>[];
    return [
      for (final it in items)
        if (it.isFinishedGood || it.isPurchased) it,
    ];
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

  static String _numText(num value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();

  static String _isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
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

/// Quantity must be positive — shown in the error banner when a filled
/// line has a zero/empty qty. No l10n key exists for this phrasing.
const String _invalidQuantityMessage = 'Quantity must be greater than zero';
