// New-purchase dialog — opened from the Purchases tab toolbar. Records a
// direct purchase via `POST /purchases` (repo.create): the server writes
// the purchase row, posts the stock movement, and — when a supplier is
// linked — posts the AP supplier-ledger entry. The payment section
// records a supplier payment against the just-created purchase
// (`POST /payments` with `purchase_allocations`) so a cash purchase is
// entered in one go. Without a supplier the payment section is disabled
// (the server has no ledger to apply it to).
//
// Layout follows the other data-entry dialogs: sectioned cards
// (Document / Item / Payment) with a running total and a payment
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
import '../../widgets/payment_success_screen.dart' show PaymentSuccessScreen;
import '../../widgets/searchable_select.dart';
import '../inventory/inventory_providers.dart'
    show allItemsProvider, warehousesProvider;
import '../payments/payments_providers.dart' show paymentsProvider;
import '../purchase_orders/purchase_order_providers.dart'
    show poSupplierOptionsProvider;
import '../sales/payment_panel.dart' show kPaymentMethods;
import 'purchase_providers.dart' show purchasesProvider;
import 'package:minierp_app/core/theme/app_border_radius.dart';

/// Opens the new-purchase dialog (create only).
Future<void> showPurchaseFormDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => const _PurchaseFormDialog(),
  );
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

  // Item.
  int? _itemId;
  int? _warehouseId;
  DateTime? _expiryDate;
  final _qtyController = TextEditingController();
  final _costController = TextEditingController();

  // Payment.
  bool _recordPayment = true;
  late DateTime _paymentDate;
  String _paymentMethod = kPaymentMethods.first;
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  final _paymentNotesController = TextEditingController();

  /// The line total the amount field was last synced to — lets the
  /// amount track the total until the user types their own number.
  num _lastSyncedTotal = 0;

  bool _busy = false;
  String? _error;

  /// Set once the purchase + payment both saved — the dialog body
  /// switches to the success screen (print receipt / close).
  int? _lastPaymentId;

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
    _qtyController.dispose();
    _costController.dispose();
    _amountController.dispose();
    _referenceController.dispose();
    _paymentNotesController.dispose();
    super.dispose();
  }

  num get _quantity => num.tryParse(_qtyController.text.trim()) ?? 0;
  num get _unitCost => num.tryParse(_costController.text.trim()) ?? 0;
  num get _lineTotal => _quantity * _unitCost;
  num get _paymentAmount => num.tryParse(_amountController.text.trim()) ?? 0;

  /// Whether a payment can actually be posted — needs a linked supplier
  /// and a positive amount.
  bool get _canPay => _supplierId != null && _paymentAmount > 0;

  /// Keeps the payment amount in lock-step with the line total until the
  /// user edits it themselves (the common flow is "pay the full amount").
  void _syncPaymentToTotal() {
    final total = _lineTotal;
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

  Future<void> _pickExpiryDate() async {
    final picked = await pickDate(
      context,
      initialDate: _expiryDate ?? DateTime.now(),
      firstDate: DateTime.now(),
    );
    if (picked != null && mounted) setState(() => _expiryDate = picked);
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_recordPayment && _supplierId != null && _paymentAmount <= 0) {
      setState(() => _error = l10n.paymentsErrorAmountGreaterThanZero);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    final result = await ref.read(purchaseRepositoryProvider).create(
          itemId: _itemId!,
          warehouseId: _warehouseId!,
          quantity: _quantity,
          unitCost: _unitCost,
          purchaseDate: isoDate(_purchaseDate),
          supplierId: _supplierId,
          invoiceNo: _invoiceNoController.text,
          remarks: _remarksController.text,
          expiryDate: _expiryDate != null ? isoDate(_expiryDate!) : null,
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
                'purchase_allocations': [
                  {'purchase_id': data.id, 'amount': _paymentAmount},
                ],
              });
          if (!mounted) return;
          ref.invalidate(paymentsProvider);
          switch (payResult) {
            case ApiSuccess(:final data):
              setState(() {
                _busy = false;
                _lastPaymentId = data.id;
              });
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

  /// Expiry-date picker — only shown when the selected item tracks expiry.
  Widget _expiryPicker(AppLocalizations l10n) {
    final items = ref.watch(allItemsProvider).valueOrNull ?? const [];
    final selectedItem = items.where((i) => i.id == _itemId).firstOrNull;
    if (selectedItem?.hasExpiry != true) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        FormFieldShell(
          label: l10n.expiryDate,
          child: SizedBox(
            height: 42,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _pickExpiryDate,
              icon: const Icon(Icons.calendar_today_outlined, size: 15),
              label: Text(
                _expiryDate != null
                    ? Formatters.date(isoDate(_expiryDate!))
                    : l10n.expirySelectDateOptional,
              ),
            ),
          ),
        ),
      ],
    );
  }

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
        ],
      ),
    );
  }

  Widget _itemSection(AppLocalizations l10n) {
    return FormSectionCard(
      icon: Icons.inventory_2_outlined,
      title: l10n.purchasesItemscard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormFieldShell(
            label: l10n.fieldsItem,
            required: true,
            child: _ItemSelect(
              selected: _itemId,
              onChanged: (value) => setState(() {
                _itemId = value;
                _syncPaymentToTotal();
              }),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: FormFieldShell(
                  label: l10n.fieldsQuantity,
                  required: true,
                  child: TextFormField(
                    controller: _qtyController,
                    onChanged: (_) => _syncPaymentToTotal(),
                    onFieldSubmitted: submitOnEnter(_submit),
                    enabled: !_busy,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: formInputDecoration(),
                    validator: (value) {
                      final qty = num.tryParse(value?.trim() ?? '');
                      if (qty == null || qty <= 0) return l10n.commonRequired;
                      return null;
                    },
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FormFieldShell(
                  label: l10n.purchasesUnitcost,
                  required: true,
                  child: TextFormField(
                    controller: _costController,
                    onChanged: (_) => _syncPaymentToTotal(),
                    onFieldSubmitted: submitOnEnter(_submit),
                    enabled: !_busy,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: formInputDecoration(),
                    validator: (value) {
                      final cost = num.tryParse(value?.trim() ?? '');
                      if (cost == null || cost < 0) return l10n.commonRequired;
                      return null;
                    },
                  ),
                ),
              ),
            ],
          ),
          _expiryPicker(l10n),
          const SizedBox(height: 14),
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
                  Formatters.currency(_lineTotal),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
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
            _summaryLine(l10n.salesGrandtotal, _lineTotal),
            _summaryLine(l10n.fieldsAmount, _paymentAmount),
            _summaryLine(
              l10n.salesBalance,
              _lineTotal - _paymentAmount,
              bold: true,
              color: _lineTotal - _paymentAmount > 0
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

    final paymentId = _lastPaymentId;
    if (paymentId != null) {
      final matches = suppliers.where((s) => s.id == _supplierId);
      final supplier = matches.isEmpty ? null : matches.first;
      return PaymentSuccessScreen(
        title: l10n.purchasesPurchasesaved,
        subtitle: l10n.suppliersWhatnext,
        paymentId: paymentId,
        entityName: supplier?.supplierName,
      );
    }

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 760),
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
