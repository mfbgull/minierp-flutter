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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../widgets/pluto_grid_screen.dart'
    show plutoGridConfigurationFor;

import '../../core/utils/date_utils.dart' show isoDate;
import '../../core/utils/print_utils.dart' show printPdfBytes;
import '../../core/utils/formatters.dart';
import '../../core/utils/invoice_status.dart';
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
import '../../widgets/date_picker.dart' show pickDate;
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
import 'invoice_pdf.dart' show buildA4InvoicePdf;
import 'invoice_providers.dart';
import 'invoice_return_dialog.dart' show showInvoiceReturnDialog;
import 'line_cells.dart' show DescriptionCell, LineCell, RemoveCell, SerialCell;
import 'line_items_grid.dart' show GridNavController, LineColumn, LineRowData;
import 'models/sales_forms.dart' show DiscountScope;
import 'payment_panel.dart'
    show PaymentPanel, PaymentPanelState, kPaymentMethods;
import 'price_history_hint.dart' show PriceHistoryHint;
import 'package:minierp_app/core/theme/app_border_radius.dart';

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
  /// Line-items grid minimum height (fills all remaining space above it).
  static const double _gridMinHeight = 320;

  final _formKey = GlobalKey<FormState>();
  final _paymentPanelKey = GlobalKey<PaymentPanelState>();

  /// Fires the customer popup on demand (Alt+C, spec §7).
  final ValueNotifier<int> _customerOpenSignal = ValueNotifier<int>(0);

  /// Customer selected before the grid existed — run on `onLoaded`.
  bool _pendingHandoff = false;

  /// Edit mode: focus the first row's description cell once loaded.
  bool _focusFirstRowOnLoad = false;

  late final TextEditingController _notesController;
  late final TextEditingController _discountController;

  /// Invoice-level Tax % convenience input — writes the rate to every
  /// filled line (spec: invoice-form-layout §4.4).
  late final TextEditingController _taxPercentController;

  final TextEditingController _paymentNotes = TextEditingController();

  /// Auto-dismisses the error banner after 5 seconds (spec §4.5).
  Timer? _errorTimer;

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
  /// New invoices default to per-item (spec §4.2); edit mode honors the
  /// saved scope (see `initState`).
  DiscountScope _scope = DiscountScope.item;

  bool _submitting = false;
  bool _printing = false;
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
    // Create mode defaults to per-item discount scope (spec §4.2); edit
    // mode honors the saved scope so invoice-level discounts round-trip
    // untouched on save.
    _scope = invoice == null
        ? DiscountScope.item
        : (invoice.discountScope == 'item'
              ? DiscountScope.item
              : DiscountScope.invoice);
    _taxPercentController = TextEditingController();

    _nav = GridNavController(
      scopeOf: () => _scope,
      rowsOf: () => _rows,
      onGridChanged: () => _markGridDirty(),
      onMoveResolved: (_) => _markGridDirty(),
    )..onAppendRow = _addLine;

    // Global combos (spec §7) — registered on HardwareKeyboard so they
    // fire even while a cell editor holds focus.
    HardwareKeyboard.instance.addHandler(_shortcutHandler);
    _focusFirstRowOnLoad = _isEdit;

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
    HardwareKeyboard.instance.removeHandler(_shortcutHandler);
    _customerOpenSignal.dispose();
    _notesController.dispose();
    _discountController.dispose();
    _taxPercentController.dispose();
    _errorTimer?.cancel();
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
    'amount_driven': PlutoCell(value: false),
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
    final rows = [for (final item in items) _lineRow(item)];
    if (rows.isEmpty) rows.add(_emptyLineRow());
    final manager = _gridStateManager;
    if (manager == null) {
      _rows = rows;
      return;
    }
    manager.removeAllRows(notify: false);
    manager.insertRows(manager.rows.length, rows);
    setState(() {});
    _maybeFocusFirstRow();
  }

  /// Edit mode: focus the first row's description cell (in edit mode,
  /// dropdown closed) once the grid is loaded — spec §2.2. Fires once.
  void _maybeFocusFirstRow() {
    if (!_focusFirstRowOnLoad || _gridStateManager == null) return;
    _focusFirstRowOnLoad = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_rows.isEmpty) _rows.add(_emptyLineRow());
      _nav.moveToCell(_rows.first, LineColumn.description);
    });
  }

  /// Customer selected (create or edit): commit any in-flight grid cell,
  /// then hand focus to the first row's description cell in edit mode
  /// (dropdown closed) — spec §2.3.
  void _onCustomerChanged(int? value) {
    setState(() => _customerId = value);
    _nav.commitCurrent();
    _pendingHandoff = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_gridStateManager == null) return; // onLoaded picks it up
      _performHandoff();
    });
  }

  void _performHandoff() {
    _pendingHandoff = false;
    if (_rows.isEmpty) _rows.add(_emptyLineRow());
    _nav.moveToCell(_rows.first, LineColumn.description);
  }

  // ── Global shortcuts (spec §7) ────────────────────────────────

  /// Page-wide combos: Alt+C customer, Shift+Enter payments amount,
  /// Ctrl+S save, Ctrl+P save+print. Registered on `HardwareKeyboard` so
  /// they fire even while a cell editor holds focus (cell handlers return
  /// `handled` for Enter/Tab/arrows, which a `Shortcuts` widget would
  /// never see). Ignored while a modal route (dialog/date picker) is on
  /// top.
  /// Returns `true` (handled) only for the four combos — everything else
  /// passes through untouched.
  bool _shortcutHandler(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    final hw = HardwareKeyboard.instance;
    final key = event.logicalKey;
    if (hw.isAltPressed &&
        !hw.isControlPressed &&
        !hw.isMetaPressed &&
        key == LogicalKeyboardKey.keyC) {
      _focusCustomer();
      return true;
    }
    if (hw.isShiftPressed &&
        !hw.isAltPressed &&
        !hw.isControlPressed &&
        key == LogicalKeyboardKey.enter) {
      _focusFirstPaymentAmount();
      return true;
    }
    if (hw.isControlPressed &&
        !hw.isAltPressed &&
        !hw.isMetaPressed &&
        key == LogicalKeyboardKey.keyS) {
      if (!_submitting && !_printing) _submit();
      return true;
    }
    if (hw.isControlPressed &&
        !hw.isAltPressed &&
        !hw.isMetaPressed &&
        key == LogicalKeyboardKey.keyP) {
      if (!_submitting && !_printing) _saveAndPrint();
      return true;
    }
    return false;
  }

  void _focusCustomer() {
    _nav.commitCurrent();
    _customerOpenSignal.value++;
  }

  /// Shift+Enter — commit the in-flight grid edit, ensure the payment
  /// form is visible, then focus the first method's Amount field
  /// (spec §7 / §8.20).
  void _focusFirstPaymentAmount() {
    _nav.commitCurrent();
    final panel = _paymentPanelKey.currentState;
    if (_isEdit || _recordPayment) {
      panel?.focusFirstAmount();
      return;
    }
    // Create mode with "Record payment" off: flip it on, then focus once
    // the panel has rebuilt with the amount field. The rebuild happens in
    // the frame *after* the setState, and a post-frame callback can fire
    // before that rebuild (when the shortcut arrives mid-frame) — chain
    // a second one so the Amount field provably exists (spec §8.20).
    setState(() => _recordPayment = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _paymentPanelKey.currentState?.focusFirstAmount();
      });
    });
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
    final result = await ref
        .read(invoiceRepositoryProvider)
        .invoicePayments(id);
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
      if (LineRowData(row).itemId.isNotEmpty ||
          LineRowData(row).description.isNotEmpty)
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
      ..lastEditedField = null
      ..amountDriven = false; // fresh item = fresh line state (spec §5.4)
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
    final picked = await pickDate(
      context,
      initialDate: isDue ? _dueDate : _invoiceDate,
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

  /// The totals-card Tax % field writes its rate to every filled line
  /// (existing per-line tax pipeline — no calc/API changes, spec §4.4).
  /// An explicit 0 clears the applied rate from all lines; an empty
  /// field is a no-op (per-line values are respected until the field is
  /// used).
  void _applyTaxPercent(String value) {
    final rate = double.tryParse(value.trim());
    if (rate == null) return;
    for (final line in _filledLines) {
      line.tax = rate;
    }
    setState(() {});
  }

  /// Shows the error banner and auto-dismisses it after 5 seconds.
  /// Re-triggering restarts the window; the timer is cancelled on
  /// dispose (spec §4.5).
  void _showError(String message) {
    _errorTimer?.cancel();
    setState(() => _error = message);
    _errorTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _error = null);
    });
  }

  // ── Payment helpers ───────────────────────────────────────────

  num get _paymentSum => _paymentMethods.fold<num>(0, (s, m) => s + m.amount);

  num get _remainingBalance => _isEdit
      ? (widget.invoice!.balanceAmount - _paymentSum)
      : (calculateTotal(_filledLines, _scope, _invoiceDiscount) - _paymentSum);

  void _addPaymentMethod() {
    setState(() {
      _paymentMethods.add(
        PaymentMethod(
          id: _methodSeq++,
          method: kPaymentMethods.first,
          amount: 0,
        ),
      );
    });
  }

  void _removePaymentMethod(int id) {
    setState(() => _paymentMethods.removeWhere((m) => m.id == id));
  }

  /// Rebuilds the method at [id] with a single field changed. Locates the
  /// method once by index (rather than looping and comparing every id)
  /// and reconstructs it via one `switch` — same net effect as before:
  /// only the matching method is replaced, all others are untouched.
  void _updatePaymentMethod(int id, String field, Object? value) {
    setState(() {
      final index = _paymentMethods.indexWhere((m) => m.id == id);
      if (index == -1) return;
      final m = _paymentMethods[index];
      _paymentMethods[index] = switch (field) {
        'method' => PaymentMethod(
          id: m.id,
          method: value as String,
          amount: m.amount,
          referenceNo: m.referenceNo,
        ),
        'amount' => PaymentMethod(
          id: m.id,
          method: m.method,
          amount: (value as num?) ?? 0,
          referenceNo: m.referenceNo,
        ),
        'reference_no' => PaymentMethod(
          id: m.id,
          method: m.method,
          amount: m.amount,
          referenceNo: value as String?,
        ),
        _ => m,
      };
    });
  }

  Future<void> _pickPaymentDate() async {
    final picked = await pickDate(context, initialDate: _paymentDate);
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

  /// Builds one `POST /payments` body for [method] against the invoice
  /// identified by [invoiceId]/[invoiceNo]. Shared by the edit-mode
  /// "record payment" flow (against the already-saved invoice) and the
  /// create-mode flow (against the invoice that was just created).
  Map<String, dynamic> _paymentBody(
    PaymentMethod method, {
    required int invoiceId,
    required String invoiceNo,
  }) => {
    'customer_id': _customerId!,
    'payment_date': isoDate(_paymentDate),
    'amount': method.amount,
    'payment_method': method.method,
    if (method.referenceNo != null && method.referenceNo!.isNotEmpty)
      'reference_no': method.referenceNo,
    'description': 'Payment for $invoiceNo',
    if (_paymentNotes.text.trim().isNotEmpty)
      'notes': _paymentNotes.text.trim(),
    'invoice_allocations': [
      {'invoice_id': invoiceId, 'amount': method.amount},
    ],
  };

  /// Edit-mode payment bodies — one per positive method, against the
  /// existing (already-saved) invoice.
  List<Map<String, dynamic>> _paymentBodies() => [
    for (final m in _paymentMethods)
      if (m.amount > 0)
        _paymentBody(
          m,
          invoiceId: _isEdit ? widget.invoice!.id : 0,
          invoiceNo: widget.invoice?.invoiceNo ?? '',
        ),
  ];

  /// Posts each body via `POST /payments` sequentially, surfacing a toast
  /// per failure. When [stopOnFirstFailure] is true (edit-mode "record
  /// payment"), the loop stops at the first failure; when false
  /// (create-mode payment posting), it keeps going so every method gets
  /// attempted. Returns whether every post succeeded.
  Future<bool> _postPaymentBodies(
    List<Map<String, dynamic>> bodies, {
    required bool stopOnFirstFailure,
  }) async {
    final repo = ref.read(invoiceRepositoryProvider);
    var ok = true;
    for (final body in bodies) {
      final result = await repo.createInvoicePayment(body);
      if (result case ApiFailure(:final error)) {
        ok = false;
        if (mounted) showAppToast(context, error.message);
        if (stopOnFirstFailure) break;
      }
    }
    return ok;
  }

  /// Edit mode only: post each positive method sequentially, stopping at
  /// the first failure.
  Future<void> _recordPayments() async {
    if (!_validatePayment()) return;
    setState(() => _recordingPayment = true);
    final l10n = AppLocalizations.of(context)!;
    final ok = await _postPaymentBodies(
      _paymentBodies(),
      stopOnFirstFailure: true,
    );
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

  void _onDeletePayment(InvoicePaymentRecord p) {
    setState(() => _deletedPayments.add(p.id));
  }

  Future<void> _onEditPayment(InvoicePaymentRecord p) async {
    final l10n = AppLocalizations.of(context)!;
    final amountController = TextEditingController(text: _numText(p.amount));
    final refController = TextEditingController(text: p.referenceNo ?? '');
    final updated = await showDialog<(num, String)>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.salesEditpayment),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
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
    final result = await ref.read(invoiceRepositoryProvider).updatePayment(
      p.id,
      {
        'amount': updated.$1,
        if (updated.$2.isNotEmpty) 'reference_no': updated.$2,
      },
    );
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

  // ── A4 print (edit mode) ──────────────────────────────────────

  /// Builds the A4 invoice PDF from the *saved* invoice (fresh
  /// `GET /invoices/:id` detail + payments, PORTING.md §12) and shows the
  /// native print dialog. Falls back to the share/save-as-PDF sheet when
  /// the platform has no print backend (e.g. some Linux setups).
  Future<void> _printInvoice(int invoiceId) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _printing = true);
    try {
      final repo = ref.read(invoiceRepositoryProvider);
      final detail = await repo.invoice(invoiceId);
      if (!mounted) return;
      final invoice = switch (detail) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => _printError(
          '${l10n.errorsFailed}: ${error.message}',
        ),
      };
      if (invoice == null) return;

      final paymentsResult = await repo.invoicePayments(invoiceId);
      if (!mounted) return;
      final payments = switch (paymentsResult) {
        ApiSuccess(:final data) => data,
        ApiFailure() => const <InvoicePaymentRecord>[],
      };

      final bytes = await buildA4InvoicePdf(
        invoice: invoice,
        payments: payments,
      );
      if (!mounted) return;
      await printPdfBytes(bytes, '${invoice.invoiceNo}.pdf', context);
    } catch (error) {
      if (mounted) _printError('${l10n.errorsFailed}: $error');
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  /// Shows the print error toast and signals the caller to abort.
  Invoice? _printError(String message) {
    showAppToast(context, message, isError: true);
    return null;
  }

  // ── Submit ────────────────────────────────────────────────────

  Map<String, dynamic> _buildBody() {
    final notes = _notesController.text.trim();
    final filled = _filledLines;
    final scope = _scope == DiscountScope.item ? 'item' : 'invoice';
    return {
      if (!_isEdit) 'invoice_no': generateInvoiceNo(),
      'customer_id': _customerId!,
      'invoice_date': isoDate(_invoiceDate),
      'due_date': isoDate(_dueDate),
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

  /// Validates and posts the invoice. Commits any in-flight grid cell so
  /// the edit being typed is included (spec §8.22). Returns the saved
  /// [Invoice] on success, `null` when validation or the API failed.
  Future<Invoice?> _save() async {
    final l10n = AppLocalizations.of(context)!;
    _nav.commitCurrent();
    if (!(_formKey.currentState?.validate() ?? false)) return null;
    if (_customerId == null) {
      _showError(l10n.salesErrorCustomerRequired);
      return null;
    }
    final filled = _filledLines;
    if (filled.isEmpty) {
      _showError(l10n.salesErrorItemsRequired);
      return null;
    }
    if (filled.any((line) => line.quantity <= 0)) {
      _showError(_invalidQuantityMessage);
      return null;
    }
    _errorTimer?.cancel();
    setState(() {
      _submitting = true;
      _error = null;
    });
    final repo = ref.read(invoiceRepositoryProvider);
    final result = _isEdit
        ? await repo.update(widget.invoice!.id, _buildBody())
        : await repo.create(_buildBody());
    if (!mounted) return null;

    switch (result) {
      case ApiSuccess(:final data):
        // Create mode: record any positive payment methods against the
        // fresh invoice, sequentially (a failed method doesn't block the
        // rest — matches edit-mode's non-blocking "keep trying" posting).
        if (!_isEdit &&
            _recordPayment &&
            _paymentMethods.any((m) => m.amount > 0)) {
          final bodies = [
            for (final m in _paymentMethods)
              if (m.amount > 0)
                _paymentBody(m, invoiceId: data.id, invoiceNo: data.invoiceNo),
          ];
          await _postPaymentBodies(bodies, stopOnFirstFailure: false);
        }
        return data;
      case ApiFailure(:final error):
        setState(() => _submitting = false);
        _showError(error.message);
        return null;
    }
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    final saved = await _save();
    if (!mounted || saved == null) return;
    ref.invalidate(invoicesProvider);
    Navigator.of(context).pop();
    showAppToast(context, l10n.salesInvoicesaved);
  }

  /// Ctrl+P — save (create/update), then print the A4 PDF from the saved
  /// invoice, then close the form (spec §7).
  Future<void> _saveAndPrint() async {
    final l10n = AppLocalizations.of(context)!;
    final saved = await _save();
    if (!mounted || saved == null) return;
    await _printInvoice(saved.id);
    if (!mounted) return;
    ref.invalidate(invoicesProvider);
    Navigator.of(context).pop();
    showAppToast(context, l10n.salesInvoicesaved);
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
    final result = await ref
        .read(invoiceRepositoryProvider)
        .delete(widget.invoice!.id);
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        ref.invalidate(invoicesProvider);
        Navigator.of(context).pop();
        showAppToast(context, l10n.salesInvoicedeleted);
      case ApiFailure(:final error):
        setState(() => _submitting = false);
        _showError(error.message);
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
      column(
        'description',
        l10n.fieldsItem,
        240,
        (ctx) => DescriptionCell(
          nav: _nav,
          row: ctx.row,
          items: _searchPool,
          formatCurrency: Formatters.currency,
          onItemSelected: _onItemSelected,
        ),
      ),
      column(
        'qty',
        l10n.fieldsQuantity,
        96,
        (ctx) => LineCell(nav: _nav, row: ctx.row, column: LineColumn.quantity),
        align: PlutoColumnTextAlign.end,
      ),
      column(
        'rate',
        l10n.salesRate,
        110,
        (ctx) => LineCell(
          nav: _nav,
          row: ctx.row,
          column: LineColumn.rate,
          onBeginEdit: _onRateEdit,
          overlayBuilder: () => _priceHintFor(ctx.row),
        ),
        align: PlutoColumnTextAlign.end,
      ),
      column(
        'discount',
        l10n.fieldsDiscount,
        96,
        (ctx) =>
            LineCell(nav: _nav, row: ctx.row, column: LineColumn.discountValue),
        align: PlutoColumnTextAlign.end,
      ),
      column(
        'tax',
        l10n.salesTax,
        80,
        (ctx) => LineCell(nav: _nav, row: ctx.row, column: LineColumn.tax),
        align: PlutoColumnTextAlign.end,
      ),
      column(
        'amount',
        l10n.fieldsAmount,
        120,
        (ctx) => LineCell(nav: _nav, row: ctx.row, column: LineColumn.amount),
        align: PlutoColumnTextAlign.end,
      ),
      column(
        'remove',
        '',
        52,
        (ctx) => RemoveCell(onRemove: () => _removeLine(ctx.row)),
      ),
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
    return PriceHistoryHint(history: history, currentPrice: data.rate);
  }

  // ── Layout ────────────────────────────────────────────────────

  Widget _buildGrid(AppLocalizations l10n) {
    final columns = _columns;
    if (columns == null) {
      // Fills whatever height the layout gives it — Expanded on wide
      // screens, SizedBox(height: 320) in the stacked layout.
      return Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: AppBorderRadius.xsRadius,
        ),
        child: const CircularProgressIndicator(),
      );
    }
    return PlutoGrid(
      configuration: plutoGridConfigurationFor(context),
      columns: columns,
      rows: _rows,
      onLoaded: (event) {
        _gridStateManager = event.stateManager;
        // Let the cell editors arm PlutoGrid's key `skip` flag so
        // character keys reach the IME instead of being consumed by the
        // grid's FocusScope (spec §2.3/§5.2).
        _nav.keyEventResult = event.stateManager.keyManager?.eventResult;
        if (_discountColumn != null && _scope == DiscountScope.invoice) {
          event.stateManager.hideColumn(_discountColumn!, true);
        }
        _maybeFocusFirstRow();
        if (_pendingHandoff) _performHandoff();
      },
      onChanged: (_) => _markGridDirty(),
      onRowsMoved: (_) => setState(() {}),
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
      onSelected: _submitting ? null : (_) => _setScope(scope),
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

    final customerItems = _customerItems(customers);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? l10n.salesEditinvoice : l10n.salesNewinvoice),
        actions: [
          if (_isEdit) ...[
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: _printing || _submitting
                    ? null
                    : () => _printInvoice(widget.invoice!.id),
                icon: _printing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.print_outlined, size: 18),
                label: Text(l10n.salesPrinta4),
              ),
            ),
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
        ],
      ),
      body: Form(
        key: _formKey,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Wide + tall enough → fixed-height two-column layout
                // (line items left, payment right, buttons below the
                // payment section). Otherwise the stacked scrollable
                // layout (spec §3.1/§3.2).
                final wide = constraints.maxWidth >= 720;
                final header = _buildHeader(
                  l10n,
                  customerItems,
                  customers,
                  wide: wide,
                );
                final heading = _itemsHeadingRow(l10n, wide: wide);
                final grid = _buildGrid(l10n);
                final totalsCard = _buildTotalsCard(
                  l10n,
                  subtotal,
                  tax,
                  discount,
                  total,
                );
                final notes = _notesField(l10n);
                final panel = _buildPaymentPanel(l10n, total);
                final errorBanner = _error == null
                    ? null
                    : _buildErrorBanner(l10n);
                final buttons = _buildButtonsRow(l10n);
                if (wide && constraints.maxHeight >= 660) {
                  return _buildWideLayout(
                    l10n,
                    header,
                    heading,
                    grid,
                    totalsCard,
                    notes,
                    panel,
                    errorBanner,
                    buttons,
                  );
                }
                return _buildNarrowLayout(
                  l10n,
                  header,
                  heading,
                  grid,
                  totalsCard,
                  notes,
                  panel,
                  errorBanner,
                  buttons,
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Totals card: Subtotal / Discount (always visible) / Tax % input +
  /// computed Tax / Grand Total; the invoice-scope discount input shows
  /// alongside when scope is Invoice (spec §4.4).
  Widget _buildTotalsCard(
    AppLocalizations l10n,
    num subtotal,
    num tax,
    num discount,
    num total,
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

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: AppBorderRadius.smRadius,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_scope == DiscountScope.invoice) ...[
                  TextFormField(
                    controller: _discountController,
                    enabled: !_submitting,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      labelText: l10n.fieldsDiscount,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                ],
                TextFormField(
                  controller: _taxPercentController,
                  enabled: !_submitting,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    labelText: '${l10n.salesTax} %',
                  ),
                  onChanged: _applyTaxPercent,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                totalsRow(l10n.salesSubtotal, subtotal),
                const SizedBox(height: 4),
                totalsRow(l10n.salesDiscount, discount),
                const SizedBox(height: 4),
                totalsRow(l10n.salesTax, tax),
                const Divider(height: 10),
                totalsRow(l10n.salesGrandtotal, total, bold: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _notesField(AppLocalizations l10n) {
    return FormFieldShell(
      label: l10n.fieldsNotes,
      child: TextFormField(
        controller: _notesController,
        enabled: !_submitting,
        maxLines: 2,
        decoration: _decoration(),
      ),
    );
  }

  /// Error banner — pinned above the buttons row in the right column
  /// (spec §4.5). Auto-dismissed by `_showError` after 5 seconds.
  Widget _buildErrorBanner(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.errorContainer.withValues(alpha: 0.6),
        borderRadius: AppBorderRadius.smRadius,
      ),
      child: Text(
        _error!,
        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
      ),
    );
  }

  /// Save / Cancel / Delete row — sits below the payment section in the
  /// right column (spec §4.5). Wraps so the trio fits the 330px column
  /// in edit mode (Delete + Cancel + Save would otherwise overflow).
  Widget _buildButtonsRow(AppLocalizations l10n) {
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 10,
      runSpacing: 8,
      children: [
        if (_isEdit)
          OutlinedButton.icon(
            onPressed: _submitting ? null : _delete,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: Text(l10n.commonDelete),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
          ),
        OutlinedButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
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
    );
  }

  Widget _buildPaymentPanel(AppLocalizations l10n, num total) {
    return PaymentPanel(
      key: _paymentPanelKey,
      isEdit: _isEdit,
      recordPayment: _recordPayment,
      paymentDate: _paymentDate,
      methods: _paymentMethods,
      existingPayments: _existingPayments,
      deletedPayments: _deletedPayments,
      total: total,
      paidAmount: widget.invoice?.paidAmount ?? 0,
      balance: _remainingBalance < 0 ? 0 : _remainingBalance,
      saving: _submitting || _recordingPayment,
      onRecordChanged: (v) => setState(() => _recordPayment = v),
      onPickPaymentDate: _pickPaymentDate,
      onPaymentNotesChanged: (v) => _paymentNotes.text = v,
      onAddMethod: _addPaymentMethod,
      onRemoveMethod: _removePaymentMethod,
      onUpdateMethod: _updatePaymentMethod,
      onRecord: () => _recordPayments(),
      onDeletePayment: _onDeletePayment,
      onEditPayment: _onEditPayment,
    );
  }

  /// Customer | Invoice Date | Due Date | Status — one row on wide
  /// screens, two stacked rows on narrow ones (status shares the row
  /// with the customer and the date pickers, spec §4.1).
  Widget _buildHeader(
    AppLocalizations l10n,
    List<int> customerItems,
    AsyncValue<List<Customer>> customers, {
    required bool wide,
  }) {
    final customer = FormFieldShell(
      label: l10n.fieldsCustomer,
      required: true,
      child: SearchableSelect<int>(
        items: customerItems,
        selected: _customerId,
        labelBuilder: (id) {
          final match = (customers.valueOrNull ?? const <Customer>[]).where(
            (c) => c.id == id,
          );
          return match.isEmpty ? '$id' : match.first.customerName;
        },
        autoOpen: !_isEdit,
        openSignal: _customerOpenSignal,
        onChanged: _onCustomerChanged,
      ),
    );
    final date = FormFieldShell(
      label: l10n.fieldsDate,
      required: true,
      child: _dateField(l10n.fieldsDate, _invoiceDate, isDue: false),
    );
    final due = FormFieldShell(
      label: l10n.salesDuedate,
      child: _dateField(l10n.salesDuedate, _dueDate, isDue: true),
    );
    final status = FormFieldShell(
      label: l10n.fieldsStatus,
      child: SearchableSelect<String>(
        items: _statusValues,
        selected: _status,
        labelBuilder: (s) => _statusLabel(l10n, s),
        enabled: !_submitting,
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 10),
        ),
        onChanged: (value) {
          if (value != null) setState(() => _status = value);
        },
      ),
    );
    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: customer),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: date),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: due),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: status),
        ],
      );
    }
    // Narrow: the header wraps onto two rows (customer + status, then
    // the two date pickers).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: customer),
            const SizedBox(width: 12),
            Expanded(child: status),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: date),
            const SizedBox(width: 12),
            Expanded(child: due),
          ],
        ),
      ],
    );
  }

  /// "Items" heading row — heading + discount-scope toggle + Add item
  /// (spec §4.4). Wraps on narrow screens.
  Widget _itemsHeadingRow(AppLocalizations l10n, {required bool wide}) {
    final title = Text(
      l10n.salesItems,
      style: Theme.of(context).textTheme.titleSmall,
    );
    final addButton = TextButton.icon(
      onPressed: _submitting ? null : _addLine,
      icon: const Icon(Icons.add, size: 16),
      label: Text(l10n.salesAdditem),
    );
    if (wide) {
      return Row(
        children: [
          title,
          const Spacer(),
          _scopeToggle(l10n),
          const SizedBox(width: 12),
          addButton,
        ],
      );
    }
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [title, _scopeToggle(l10n), addButton],
    );
  }

  /// Fixed-height two-column layout (spec §3.1): grid left, payment +
  /// error + buttons right, totals + notes under the grid.
  Widget _buildWideLayout(
    AppLocalizations l10n,
    Widget header,
    Widget heading,
    Widget grid,
    Widget totals,
    Widget notes,
    Widget panel,
    Widget? errorBanner,
    Widget buttons,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: header,
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      heading,
                      const SizedBox(height: 8),
                      Expanded(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minHeight: _gridMinHeight,
                          ),
                          child: grid,
                        ),
                      ),
                      const SizedBox(height: 8),
                      totals,
                      const SizedBox(height: 8),
                      notes,
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 250,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: panel,
                        ),
                      ),
                      if (errorBanner != null) ...[
                        const SizedBox(height: 8),
                        errorBanner,
                      ],
                      const SizedBox(height: 10),
                      buttons,
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Stacked scrollable layout (spec §3.2) — used below the 720px width
  /// breakpoint and on short windows.
  Widget _buildNarrowLayout(
    AppLocalizations l10n,
    Widget header,
    Widget heading,
    Widget grid,
    Widget totals,
    Widget notes,
    Widget panel,
    Widget? errorBanner,
    Widget buttons,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 10),
          heading,
          const SizedBox(height: 8),
          SizedBox(height: _gridMinHeight, child: grid),
          const SizedBox(height: 8),
          totals,
          const SizedBox(height: 8),
          notes,
          const SizedBox(height: 12),
          panel,
          if (errorBanner != null) ...[const SizedBox(height: 10), errorBanner],
          const SizedBox(height: 12),
          buttons,
        ],
      ),
    );
  }

  List<Item>? _cachedSearchPool;

  /// All active items are sellable from the invoice form (spec §4.3) —
  /// raw materials included. Memoized so the list *identity* is stable
  /// across rebuilds; the description cell's `didUpdateWidget` compares
  /// identities to detect a genuinely changed pool (spec §4.5).
  List<Item> get _searchPool {
    final items = ref.read(invoiceItemsProvider).valueOrNull ?? const <Item>[];
    final active = [
      for (final it in items)
        if (it.isActive) it,
    ];
    final cached = _cachedSearchPool;
    if (cached != null && _poolEquals(cached, active)) return cached;
    return _cachedSearchPool = active;
  }

  static bool _poolEquals(List<Item> a, List<Item> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (x.id != y.id ||
          x.itemName != y.itemName ||
          x.itemCode != y.itemCode ||
          x.isActive != y.isActive) {
        return false;
      }
    }
    return true;
  }

  List<int>? _cachedCustomerIds;

  /// Memoized customer id list — stable identity across rebuilds so the
  /// select's `didUpdateWidget` only refilters when the pool really
  /// changes (spec §8.1).
  List<int> _customerItems(AsyncValue<List<Customer>> customers) {
    final ids = [
      for (final c in customers.valueOrNull ?? const <Customer>[]) c.id,
    ];
    final cached = _cachedCustomerIds;
    if (cached != null &&
        cached.length == ids.length &&
        cached.every((id) => ids.contains(id))) {
      return cached;
    }
    return _cachedCustomerIds = ids;
  }

  InputDecoration _decoration() =>
      const InputDecoration(isDense: true, border: OutlineInputBorder());

  Widget _dateField(String label, DateTime value, {required bool isDue}) {
    return SizedBox(
      height: 44,
      child: OutlinedButton.icon(
        onPressed: _submitting ? null : () => _pickDate(isDue: isDue),
        icon: const Icon(Icons.calendar_today_outlined, size: 16),
        label: Text(Formatters.date(isoDate(value))),
      ),
    );
  }

  static String _numText(num value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();
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
    invoiceStatusLabel(l10n, status);

/// Quantity must be positive — shown in the error banner when a filled
/// line has a zero/empty qty. No l10n key exists for this phrasing.
const String _invalidQuantityMessage = 'Quantity must be greater than zero';
