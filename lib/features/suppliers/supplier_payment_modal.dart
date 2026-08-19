// Record Payment modal — web `SupplierPaymentModal` parity: supplier
// pre-bound, a Total Amount field, PO allocations (available POs with a
// balance > 0, per-line amounts capped at each PO's balance, remove, Auto
// Allocate filling the remaining amount), an Unallocated summary and
// validation that the amount equals the allocation total, then a success
// screen with Print Receipt (A4). Distinct from the Payments module's
// global RecordPaymentDialog (which keeps its customer-picker flow).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart' show isoDate;
import '../../core/utils/formatters.dart';
import '../../data/models/purchase_order.dart' show PurchaseOrder;
import '../../data/models/supplier.dart' show Supplier;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/invoice_repository.dart'
    show invoiceRepositoryProvider;
import '../../data/repositories/purchase_order_repository.dart'
    show purchaseOrderRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/date_picker.dart' show pickDate;
import '../../widgets/form_field.dart';
import '../../widgets/form_helpers.dart';
import '../../widgets/payment_success_screen.dart' show PaymentSuccessScreen;
import '../../widgets/searchable_select.dart';
import '../payments/payments_providers.dart' show paymentsProvider;
import '../sales/payment_panel.dart' show kPaymentMethods;
import 'supplier_providers.dart';

/// Opens the web-style Record Payment modal with [supplier] pre-bound.
Future<void> showSupplierPaymentModal(
  BuildContext context, {
  required Supplier supplier,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => SupplierPaymentModal(supplier: supplier),
  );
}

/// The supplier's purchase orders with an outstanding balance (balance >
/// 0) for allocation — the web modal's `purchaseOrders` source.
final _openPosProvider = FutureProvider.autoDispose
    .family<List<PurchaseOrder>, int>((ref, supplierId) async {
      final result = await ref
          .watch(purchaseOrderRepositoryProvider)
          .list(supplierId: supplierId);
      return switch (result) {
        ApiSuccess(:final data) => [
          for (final po in data)
            if ((po.balanceAmount > 0)) po,
        ],
        ApiFailure(:final error) => throw error,
      };
    });

class SupplierPaymentModal extends ConsumerStatefulWidget {
  const SupplierPaymentModal({super.key, required this.supplier});

  final Supplier supplier;

  @override
  ConsumerState<SupplierPaymentModal> createState() =>
      _SupplierPaymentModalState();
}

/// One allocation line: the PO + its amount controller.
class _Allocation {
  _Allocation(this.po, this.controller);

  final PurchaseOrder po;
  final TextEditingController controller;
}

class _SupplierPaymentModalState extends ConsumerState<SupplierPaymentModal> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _paymentDate;
  late final TextEditingController _dateController;
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  final _notesController = TextEditingController();
  String _paymentMethod = kPaymentMethods.first;
  final List<_Allocation> _allocations = [];
  bool _submitting = false;
  String? _error;
  int? _lastPaymentId;

  @override
  void initState() {
    super.initState();
    _paymentDate = DateTime.now();
    _dateController = TextEditingController(
      text: Formatters.dateTime(_paymentDate),
    );
  }

  @override
  void dispose() {
    _dateController.dispose();
    _amountController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    for (final a in _allocations) {
      a.controller.dispose();
    }
    super.dispose();
  }

  num get _totalAmount => double.tryParse(_amountController.text.trim()) ?? 0;

  num get _allocationTotal {
    var total = 0.0;
    for (final a in _allocations) {
      total += double.tryParse(a.controller.text.trim()) ?? 0;
    }
    return total;
  }

  num get _unallocated => _totalAmount - _allocationTotal;

  List<PurchaseOrder> get _availablePos {
    final all =
        ref.watch(_openPosProvider(widget.supplier.id)).valueOrNull ??
        const <PurchaseOrder>[];
    final allocatedIds = {for (final a in _allocations) a.po.id};
    return [for (final po in all) if (!allocatedIds.contains(po.id)) po];
  }

  Future<void> _pickDate() async {
    final picked = await pickDate(
      context,
      initialDate: _paymentDate,
      firstDate: DateTime(2020),
    );
    if (picked != null) {
      setState(() {
        _paymentDate = picked;
        _dateController.text = Formatters.dateTime(picked);
      });
    }
  }

  void _addAllocation(PurchaseOrder po) {
    if (_allocations.any((a) => a.po.id == po.id)) return;
    // Initial amount: web parity `Math.min(balance, amount)` — capped at
    // the entered total so the sum can never silently exceed it.
    final initial = po.balanceAmount < _totalAmount
        ? po.balanceAmount
        : _totalAmount;
    final controller = TextEditingController(text: initial.toStringAsFixed(2));
    controller.addListener(() => setState(() {}));
    setState(() {
      _allocations.add(_Allocation(po, controller));
      _error = null;
    });
  }

  void _removeAllocation(_Allocation allocation) {
    allocation.controller.dispose();
    setState(() {
      _allocations.remove(allocation);
      _error = null;
    });
  }

  void _onAllocationAmountChanged(_Allocation allocation, String value) {
    final parsed = double.tryParse(value) ?? 0;
    final capped = parsed.clamp(0.0, allocation.po.balanceAmount.toDouble());
    if (parsed != capped) {
      // Clamp to the PO's remaining balance (web caps per line).
      allocation.controller.text = capped.toStringAsFixed(2);
    }
    setState(() {});
  }

  void _autoAllocate() {
    final amountLeft = _totalAmount - _allocationTotal;
    if (amountLeft <= 0) return;
    var remaining = amountLeft;
    final newlyAdded = <_Allocation>[];
    for (final po in _availablePos) {
      if (remaining <= 0) break;
      final take = remaining < po.balanceAmount
          ? remaining
          : po.balanceAmount;
      final controller = TextEditingController(text: take.toStringAsFixed(2));
      controller.addListener(() => setState(() {}));
      final allocation = _Allocation(po, controller);
      _allocations.add(allocation);
      newlyAdded.add(allocation);
      remaining -= take;
    }
    setState(() {
      _error = null;
    });
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_totalAmount <= 0) {
      setState(() => _error = l10n.paymentsErrorAmountGreaterThanZero);
      return;
    }
    if (_allocations.isEmpty) {
      setState(() => _error = l10n.suppliersAllocationrequired);
      return;
    }
    if ((_totalAmount - _allocationTotal).abs() > 0.005) {
      setState(
        () => _error =
            '${l10n.suppliersAmountmustmatch} '
            '(${Formatters.currency(_allocationTotal)})',
      );
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final poNos = [for (final a in _allocations) a.po.poNo];
    final result = await ref
        .read(invoiceRepositoryProvider)
        .createSupplierPayment({
          'supplier_id': widget.supplier.id,
          'payment_date': isoDate(_paymentDate),
          'amount': _totalAmount,
          'payment_method': _paymentMethod,
          if (_referenceController.text.trim().isNotEmpty)
            'reference_no': _referenceController.text.trim(),
          if (_notesController.text.trim().isNotEmpty)
            'notes': _notesController.text.trim(),
          'description': poNos.isEmpty
              ? 'Supplier Payment'
              : 'Payment for ${poNos.join(', ')}',
          'po_allocations': [
            for (final a in _allocations)
              {
                'po_id': a.po.id,
                'amount': double.tryParse(a.controller.text.trim()) ?? 0,
              },
          ],
        });
    if (!mounted) return;

    switch (result) {
      case ApiSuccess(:final data):
        setState(() {
          _submitting = false;
          _lastPaymentId = data.id;
        });
        ref.invalidate(paymentsProvider);
        invalidateSupplierQueries(ref, widget.supplier.id);
      case ApiFailure(:final error):
        setState(() {
          _submitting = false;
          _error = error.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    if (_lastPaymentId != null) {
      return PaymentSuccessScreen(
        title: l10n.suppliersPaymentrecordedsuccess,
        subtitle: l10n.suppliersWhatnext,
        paymentId: _lastPaymentId!,
        entityName: widget.supplier.supplierName,
      );
    }

    final openPos = ref.watch(_openPosProvider(widget.supplier.id)).valueOrNull;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.suppliersRecordpayment,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 2),
              Text(
                '${widget.supplier.supplierCode} — ${widget.supplier.supplierName}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: _submitting
                    ? const Center(child: CircularProgressIndicator())
                    : Form(
                        key: _formKey,
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Payment date + method.
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Expanded(
                                    child: FormFieldShell(
                                      label: l10n.salesPaymentdate,
                                      required: true,
                                      child: TextFormField(
                                        readOnly: true,
                                        onTap: _pickDate,
                                        controller: _dateController,
                                        decoration: InputDecoration(
                                          isDense: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 10,
                                              ),
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          suffixIcon: const Icon(
                                            Icons.calendar_today,
                                            size: 16,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
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
                                            setState(
                                              () => _paymentMethod = value,
                                            );
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              // Total amount.
                              FormFieldShell(
                                label: l10n.suppliersTotalamount,
                                required: true,
                                child: TextFormField(
                                  controller: _amountController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  onChanged: (_) => setState(() {}),
                                  decoration: formInputDecoration(
                                    hintText: '0.00',
                                  ),
                                  validator: (v) =>
                                      (double.tryParse(v ?? '') ?? 0) <= 0
                                      ? l10n.paymentsErrorAmountGreaterThanZero
                                      : null,
                                ),
                              ),
                              const SizedBox(height: 12),
                              // PO allocations.
                              Text(
                                l10n.suppliersAllocation,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 4),
                              if (openPos == null)
                                const SizedBox(
                                  height: 120,
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                )
                              else if (openPos.isEmpty)
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  child: Text(
                                    l10n.suppliersNoopenpos,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                  ),
                                )
                              else ...[
                                // Allocated lines.
                                if (_allocations.isNotEmpty) ...[
                                  for (final a in _allocations)
                                    _AllocationRow(
                                      allocation: a,
                                      onRemove: () =>
                                          _removeAllocation(a),
                                      onAmountChanged: (v) =>
                                          _onAllocationAmountChanged(a, v),
                                    ),
                                  const SizedBox(height: 8),
                                ],
                                // Available POs.
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        l10n.suppliersAvailablepos,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: _autoAllocate,
                                      icon: const Icon(
                                        Icons.auto_awesome,
                                        size: 16,
                                      ),
                                      label: Text(
                                        l10n.suppliersAutoallocate,
                                      ),
                                    ),
                                  ],
                                ),
                                if (_availablePos.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    child: Text(
                                      l10n.suppliersAllposallocated,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                  )
                                else
                                  for (final po in _availablePos)
                                    _AvailablePoRow(
                                      po: po,
                                      onAdd: () => _addAllocation(po),
                                    ),
                              ],
                              const SizedBox(height: 10),
                              // Summary: Total / Allocated / Unallocated.
                              _summaryRow(
                                context,
                                l10n.suppliersTotalamount,
                                Formatters.currency(_totalAmount),
                              ),
                              _summaryRow(
                                context,
                                l10n.suppliersAllocatedpos,
                                Formatters.currency(_allocationTotal),
                              ),
                              _summaryRow(
                                context,
                                l10n.suppliersUnallocated,
                                Formatters.currency(_unallocated),
                                highlight: _unallocated.abs() > 0.005,
                              ),
                              if (_error != null) ...[
                                const SizedBox(height: 10),
                                ErrorBanner(message: _error!),
                              ],
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                alignment: WrapAlignment.end,
                                children: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
                                    child: Text(l10n.commonCancel),
                                  ),
                                  FilledButton.icon(
                                    onPressed: _submitting
                                        ? null
                                        : _submit,
                                    icon: const Icon(
                                      Icons.account_balance_wallet_outlined,
                                      size: 18,
                                    ),
                                    label: Text(l10n.suppliersRecordpayment),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryRow(
    BuildContext context,
    String label,
    String value, {
    bool highlight = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: highlight ? scheme.error : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// One allocated line: PO no + balance, editable amount, remove.
class _AllocationRow extends StatelessWidget {
  const _AllocationRow({
    required this.allocation,
    required this.onRemove,
    required this.onAmountChanged,
  });

  final _Allocation allocation;
  final VoidCallback onRemove;
  final ValueChanged<String> onAmountChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final po = allocation.po;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  po.poNo,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  Formatters.currency(po.balanceAmount),
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 130,
            child: TextField(
              controller: allocation.controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: onAmountChanged,
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            onPressed: onRemove,
            icon: Icon(
              Icons.close,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// One available PO: no + balance + an Add button.
class _AvailablePoRow extends StatelessWidget {
  const _AvailablePoRow({required this.po, required this.onAdd});

  final PurchaseOrder po;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  po.poNo,
                  style: const TextStyle(fontSize: 13),
                ),
                Text(
                  '${Formatters.currency(po.balanceAmount)} '
                  '${scheme.brightness == Brightness.dark ? '' : ''}',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onAdd,
            child: const Text('+ Add'),
          ),
        ],
      ),
    );
  }
}
