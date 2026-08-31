// Record-purchase dialog — opened from the Purchases tab toolbar. Records
// ONE purchase containing MULTIPLE item lines via `POST /purchases`
// (repo.createMulti): the server creates one purchase row per line — each
// with its own doc no, batch, stock movement and ledger/GL entries —
// atomically in one transaction. The payment section records a supplier
// payment spread across the just-created purchase rows (`POST /payments`
// with `purchase_allocations`). Without a linked supplier the payment
// section is disabled (the server has no ledger to apply it to). On
// success the dialog closes with a confirmation toast; failures stay
// inline as an error banner.
//
// Layout follows the other data-entry dialogs: sectioned cards
// (Document / Items / Payment) with a running total and a payment
// summary.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart' show isoDate;
import '../../core/utils/formatters.dart';
import '../../data/models/supplier.dart' show Supplier;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/invoice_repository.dart'
    show invoiceRepositoryProvider;
import '../../data/repositories/purchase_repository.dart'
    show purchaseRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/date_picker.dart' show pickDate;
import '../../widgets/form_field.dart' show FormFieldShell;
import '../../widgets/form_helpers.dart'
    show ErrorBanner, formInputDecoration, numText, submitOnEnter;
import '../../widgets/form_section_card.dart' show FormSectionCard;
import '../../widgets/searchable_select.dart';
import '../inventory/inventory_providers.dart'
    show allItemsProvider, warehousesProvider;
import '../payments/payments_providers.dart' show paymentsProvider;
import '../purchase_orders/purchase_order_providers.dart'
    show poSupplierOptionsProvider;
import '../sales/payment_panel.dart' show kPaymentMethods;
import 'purchase_providers.dart' show purchasesProvider;
import 'package:minierp_app/core/theme/app_border_radius.dart';
import 'package:minierp_app/widgets/movable_dialog.dart';

/// Opens the new-purchase dialog (create only).
Future<void> showPurchaseFormDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => const _PurchaseFormDialog(),
  );
}

/// Mutable form line — the item picker value plus qty/unit-cost fields
/// (same shape as the PO form's `_PoLine`).
class _PurchaseLine {
  _PurchaseLine() : qtyController = TextEditingController(), costController = TextEditingController();

  int? itemId;

  final TextEditingController qtyController;
  final TextEditingController costController;

  /// Optional expiry date for expiry-tracked items (flows into the batch).
  DateTime? expiryDate;

  num get quantity => num.tryParse(qtyController.text.trim()) ?? 0;
  num get unitCost => num.tryParse(costController.text.trim()) ?? 0;

  void dispose() {
    qtyController.dispose();
    costController.dispose();
  }
}

class _PurchaseFormDialog extends ConsumerStatefulWidget {
  const _PurchaseFormDialog();

  @override
  ConsumerState<_PurchaseFormDialog> createState() =>
      _PurchaseFormDialogState();
}

class _PurchaseFormDialogState extends ConsumerState<_PurchaseFormDialog> {
  final _formKey = GlobalKey<FormState>();

  // Document.
  int? _supplierId;
  late DateTime _purchaseDate;
  final _invoiceNoController = TextEditingController();
  final _remarksController = TextEditingController();

  // Item lines (at least one).
  final List<_PurchaseLine> _lines = [_PurchaseLine()];
  int? _warehouseId;

  // Payment.
  bool _recordPayment = true;
  late DateTime _paymentDate;
  String _paymentMethod = kPaymentMethods.first;
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  final _paymentNotesController = TextEditingController();

  /// The grand total the amount field was last synced to — lets the
  /// amount track the total until the user types their own number.
  num _lastSyncedTotal = 0;

  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _purchaseDate = DateTime.now();
    _paymentDate = _purchaseDate;
  }

  @override
  void dispose() {
    _invoiceNoController.dispose();
    _remarksController.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    _amountController.dispose();
    _referenceController.dispose();
    _paymentNotesController.dispose();
    super.dispose();
  }

  /// Lines with an item chosen — only these are submitted.
  List<_PurchaseLine> get _filledLines =>
      _lines.where((line) => line.itemId != null).toList();

  num get _total => _filledLines.fold<num>(
    0,
    (sum, line) => sum + line.quantity * line.unitCost,
  );
  num get _paymentAmount => num.tryParse(_amountController.text.trim()) ?? 0;

  /// Whether a payment can actually be posted — needs a linked supplier
  /// and a positive amount.
  bool get _canPay => _supplierId != null && _paymentAmount > 0;

  /// Keeps the payment amount in lock-step with the items total until the
  /// user edits it themselves (the common flow is "pay the full amount").
  void _syncPaymentToTotal() {
    final total = _total;
    final current = num.tryParse(_amountController.text.trim()) ?? 0;
    final untouched = current == 0 || current == _lastSyncedTotal;
    if (_recordPayment && total > 0 && untouched) {
      _amountController.text = numText(total);
      _lastSyncedTotal = total;
    }
    setState(() {});
  }

  Future<void> _pickDate() async {
    final picked = await pickDate(context, initialDate: _purchaseDate);
    if (picked != null && mounted) setState(() => _purchaseDate = picked);
  }

  Future<void> _pickPaymentDate() async {
    final picked = await pickDate(context, initialDate: _paymentDate);
    if (picked != null && mounted) setState(() => _paymentDate = picked);
  }

  Future<void> _pickLineExpiryDate(int index) async {
    final picked = await pickDate(
      context,
      initialDate: _lines[index].expiryDate ?? DateTime.now(),
      firstDate: DateTime.now(),
    );
    if (picked != null && mounted) {
      setState(() => _lines[index].expiryDate = picked);
    }
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final filled = _filledLines;
    if (filled.isEmpty) {
      setState(() => _error = l10n.purchaseordersErrorItemsrequired);
      return;
    }
    if (_recordPayment && _supplierId != null && _paymentAmount <= 0) {
      setState(() => _error = l10n.paymentsErrorAmountGreaterThanZero);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    final result = await ref
        .read(purchaseRepositoryProvider)
        .createMulti(
          warehouseId: _warehouseId!,
          purchaseDate: isoDate(_purchaseDate),
          supplierId: _supplierId,
          invoiceNo: _invoiceNoController.text,
          remarks: _remarksController.text,
          items: [
            for (final line in filled)
              (
                itemId: line.itemId!,
                quantity: line.quantity,
                unitCost: line.unitCost,
                expiryDate:
                    line.expiryDate != null ? isoDate(line.expiryDate!) : null,
              ),
          ],
        );
    if (!mounted) return;

    switch (result) {
      case ApiFailure(:final error):
        setState(() {
          _busy = false;
          _error = error.message;
        });
      case ApiSuccess(:final data):
        ref.invalidate(purchasesProvider);
        if (_recordPayment && _canPay) {
          // Spread the payment across the created rows in order, capped
          // at each row's total — with the amount synced to the grand
          // total this is exactly one allocation per line.
          var remaining = _paymentAmount;
          final allocations = <Map<String, dynamic>>[];
          for (final purchase in data) {
            if (remaining <= 0) break;
            final amount =
                remaining >= purchase.totalCost ? purchase.totalCost : remaining;
            allocations.add({'purchase_id': purchase.id, 'amount': amount});
            remaining -= amount;
          }
          if (remaining > 0 && allocations.isNotEmpty) {
            allocations.last['amount'] =
                (allocations.last['amount'] as num) + remaining;
          }

          final payResult = await ref
              .read(invoiceRepositoryProvider)
              .createSupplierPayment({
                'supplier_id': _supplierId!,
                'payment_date': isoDate(_paymentDate),
                'amount': _paymentAmount,
                'payment_method': _paymentMethod,
                if (_referenceController.text.trim().isNotEmpty)
                  'reference_no': _referenceController.text.trim(),
                if (_paymentNotesController.text.trim().isNotEmpty)
                  'notes': _paymentNotesController.text.trim(),
                'purchase_allocations': allocations,
              });
          if (!mounted) return;
          ref.invalidate(paymentsProvider);
          switch (payResult) {
            case ApiSuccess():
              Navigator.of(context).pop();
              showAppToast(context, l10n.purchasesPurchasesaved);
            case ApiFailure(:final error):
              Navigator.of(context).pop();
              showAppToast(
                context,
                '${l10n.purchasesPurchasesaved} — '
                '${l10n.errorsFailed}: ${error.message}',
                isError: true,
              );
          }
          return;
        }
        Navigator.of(context).pop();
        showAppToast(context, l10n.purchasesPurchasesaved);
    }
  }

  // ── Shared chrome ─────────────────────────────────────────────

  Widget _summaryLine(
    String label,
    num value, {
    bool bold = false,
    Color? color,
  }) {
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

  Widget _dateField({
    required String label,
    required DateTime value,
    required VoidCallback onTap,
  }) {
    return FormFieldShell(
      label: label,
      required: true,
      child: SizedBox(
        height: 42,
        child: OutlinedButton.icon(
          onPressed: _busy ? null : onTap,
          icon: const Icon(Icons.calendar_today_outlined, size: 15),
          label: Text(Formatters.date(isoDate(value))),
        ),
      ),
    );
  }

  // ── Sections ──────────────────────────────────────────────────

  Widget _documentSection(AppLocalizations l10n, List<Supplier> suppliers) {
    final supplierIds = [for (final s in suppliers) s.id];
    return FormSectionCard(
      icon: Icons.receipt_long_outlined,
      title: l10n.purchasesDocument,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormFieldShell(
            label: l10n.fieldsSupplier,
            child: SearchableSelect<int>(
              items: supplierIds,
              selected: _supplierId,
              labelBuilder: (id) {
                final match = suppliers.where((s) => s.id == id);
                final supplier = match.isEmpty ? null : match.first;
                return supplier == null
                    ? '$id'
                    : '${supplier.supplierCode} — ${supplier.supplierName}';
              },
              decoration: formInputDecoration(),
              onChanged: (value) => setState(() => _supplierId = value),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _dateField(
                  label: l10n.purchasesPurchasedate,
                  value: _purchaseDate,
                  onTap: _pickDate,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FormFieldShell(
                  label: l10n.fieldsWarehouse,
                  required: true,
                  child: _WarehouseSelect(
                    selected: _warehouseId,
                    onChanged: (value) =>
                        setState(() => _warehouseId = value),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FormFieldShell(
            label: l10n.purchasesInvoicenumber,
            child: TextFormField(
              controller: _invoiceNoController,
              enabled: !_busy,
              decoration: formInputDecoration(
                hintText: l10n.purchasesInvoiceplaceholder,
              ),
            ),
          ),
          const SizedBox(height: 12),
          FormFieldShell(
            label: l10n.purchasesRemarks,
            child: TextFormField(
              controller: _remarksController,
              enabled: !_busy,
              minLines: 2,
              maxLines: 3,
              decoration: formInputDecoration(),
            ),
          ),
        ],
      ),
    );
  }

  /// Per-line expiry picker button — shown only when that line's item
  /// tracks expiry.
  bool _lineShowsExpiry(int index) {
    final items = ref.watch(allItemsProvider).valueOrNull ?? const [];
    final itemId = _lines[index].itemId;
    final selectedItem = items.where((i) => i.id == itemId).firstOrNull;
    return selectedItem?.hasExpiry == true;
  }

  Widget _lineRow(AppLocalizations l10n, int index) {
    final line = _lines[index];
    final scheme = Theme.of(context).colorScheme;
    final amount = line.quantity * line.unitCost;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: _ItemSelect(
                selected: line.itemId,
                onChanged: (value) => setState(() {
                  line.itemId = value;
                  if (value == null) line.expiryDate = null;
                  _syncPaymentToTotal();
                }),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 92,
              child: TextFormField(
                controller: line.qtyController,
                enabled: !_busy,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: formInputDecoration(),
                validator: (value) =>
                    (num.tryParse(value?.trim() ?? '') ?? -1) <= 0
                    ? l10n.commonRequired
                    : null,
                onChanged: (_) => _syncPaymentToTotal(),
                onFieldSubmitted: submitOnEnter(_submit),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 110,
              child: TextFormField(
                controller: line.costController,
                enabled: !_busy,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: formInputDecoration(),
                validator: (value) =>
                    (num.tryParse(value?.trim() ?? '') ?? -1) < 0
                    ? l10n.commonRequired
                    : null,
                onChanged: (_) => _syncPaymentToTotal(),
                onFieldSubmitted: submitOnEnter(_submit),
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
                onPressed: _busy || _lines.length <= 1
                    ? null
                    : () => setState(() {
                        _lines.removeAt(index).dispose();
                        _syncPaymentToTotal();
                      }),
              ),
            ),
          ],
        ),
        if (_lineShowsExpiry(index)) ...[
          const SizedBox(height: 6),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: SizedBox(
              height: 38,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _pickLineExpiryDate(index),
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
      ],
    );
  }

  Widget _itemSection(AppLocalizations l10n) {
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
          Row(
            children: [
              Expanded(flex: 3, child: Text(l10n.fieldsItem, style: headerStyle)),
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
          for (var i = 0; i < _lines.length; i++) ...[
            _lineRow(l10n, i),
            if (i < _lines.length - 1) const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy
                  ? null
                  : () => setState(() => _lines.add(_PurchaseLine())),
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.purchaseordersAdditem),
            ),
          ),
          const Divider(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: AppBorderRadius.smRadius,
            ),
            child: Row(
              children: [
                Text(
                  '${l10n.commonTotal}:',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Text(
                  Formatters.currency(_total),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentSection(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final hasSupplier = _supplierId != null;
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
                onChanged: _busy
                    ? null
                    : (v) => setState(() {
                        _recordPayment = v;
                        if (v) _syncPaymentToTotal();
                      }),
              ),
            ],
          ),
          if (!hasSupplier)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                l10n.purchasesSupplierrequiredforpayment,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          if (_recordPayment && hasSupplier) ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _dateField(
                    label: l10n.salesPaymentdate,
                    value: _paymentDate,
                    onTap: _pickPaymentDate,
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
                        if (value != null) setState(() => _paymentMethod = value);
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
                onFieldSubmitted: submitOnEnter(_submit),
                enabled: !_busy,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
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
                      enabled: !_busy,
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
                      enabled: !_busy,
                      decoration: formInputDecoration(),
                    ),
                  ),
                ),
              ],
            ),
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
    final suppliers =
        ref.watch(poSupplierOptionsProvider).valueOrNull ?? const <Supplier>[];

    return MovableDialog(
      dialogId: 'purchase_form',
      maxWidth: 620,
      maxHeight: 760,
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
                        Icons.shopping_cart_outlined,
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
                            l10n.purchasesRecordpurchase,
                            style: Theme.of(
                              context,
                            ).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            l10n.purchasesSubtitle,
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
                      _documentSection(l10n, suppliers),
                      const SizedBox(height: 12),
                      _itemSection(l10n),
                      const SizedBox(height: 12),
                      _paymentSection(l10n),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        ErrorBanner(message: _error!),
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
                      onPressed: _busy ? null : () => Navigator.of(context).pop(),
                      child: Text(l10n.commonCancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _busy ? null : _submit,
                      icon: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
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
    );
  }
}

/// Warehouse picker — reads the shared warehouses provider (kept as a
/// small widget so the section builder stays readable).
class _WarehouseSelect extends ConsumerWidget {
  const _WarehouseSelect({this.selected, required this.onChanged});

  final int? selected;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final warehouses = ref.watch(warehousesProvider).valueOrNull ?? const [];
    return SearchableSelect<int>(
      items: [for (final w in warehouses) w.id],
      selected: selected,
      labelBuilder: (id) {
        final match = warehouses.where((w) => w.id == id);
        return match.isEmpty
            ? '$id'
            : match.first.warehouseName ?? match.first.warehouseCode;
      },
      decoration: formInputDecoration(),
      validator: (v) => v == null ? l10n.commonRequired : null,
      onChanged: onChanged,
    );
  }
}

/// Item picker — reads the shared items provider (kept as a small widget
/// so the section builder stays readable).
class _ItemSelect extends ConsumerWidget {
  const _ItemSelect({this.selected, required this.onChanged});

  final int? selected;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final items = ref.watch(allItemsProvider).valueOrNull ?? const [];
    return SearchableSelect<int>(
      items: [for (final item in items) item.id],
      selected: selected,
      labelBuilder: (id) {
        final match = items.where((i) => i.id == id);
        return match.isEmpty ? '$id' : '${match.first.itemCode} — ${match.first.itemName}';
      },
      decoration: formInputDecoration(),
      validator: (v) => v == null ? l10n.commonRequired : null,
      onChanged: onChanged,
    );
  }
}
