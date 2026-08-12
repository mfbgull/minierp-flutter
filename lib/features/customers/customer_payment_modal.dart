// Record Payment modal — web `PaymentModal` parity (customer-module-spec.md
// §7): customer pre-bound, a Total Amount field, invoice allocations
// (available list with Add, per-line amounts capped at each invoice's
// balance, remove, Auto Allocate filling the remaining amount oldest-
// first), an Unallocated summary and validation that the amount equals
// the allocation total, then a success screen with Print Receipt (A4).
// Distinct from the Payments module's global RecordPaymentDialog (which
// keeps its customer-picker flow).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart' show isoDate;
import '../../core/utils/formatters.dart';
import '../../core/utils/print_utils.dart' show printPdfBytes;
import '../../data/models/customer.dart' show Customer;
import '../../data/models/invoice.dart' show Invoice;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/invoice_repository.dart'
    show InvoiceFilters, invoiceRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/date_picker_helpers.dart' show pickDate;
import '../../widgets/form_field.dart';
import '../../widgets/form_helpers.dart';
import '../../widgets/searchable_select.dart';
import '../payments/payments_providers.dart' show paymentsProvider;
import '../sales/invoice_providers.dart' show invoicesProvider;
import '../sales/payment_panel.dart' show kPaymentMethods;
import 'customer_providers.dart';
import '../../widgets/payment_receipt_pdf.dart' show buildPaymentReceiptPdf;

/// Opens the web-style Record Payment modal with [customer] pre-bound.
Future<void> showCustomerPaymentModal(
  BuildContext context, {
  required Customer customer,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => CustomerPaymentModal(customer: customer),
  );
}

/// The customer's open invoices (balance > 0) for allocation.
final _openInvoicesProvider = FutureProvider.autoDispose
    .family<List<Invoice>, int>((ref, customerId) async {
      final result = await ref.watch(invoiceRepositoryProvider).invoices(
        filters: InvoiceFilters(
          customerId: customerId,
          status: 'Unpaid,Partially Paid,Overdue',
        ),
      );
      return switch (result) {
        ApiSuccess(:final data) => [
          for (final invoice in data)
            if (invoice.balanceAmount > 0) invoice,
        ],
        ApiFailure(:final error) => throw error,
      };
    });

class CustomerPaymentModal extends ConsumerStatefulWidget {
  const CustomerPaymentModal({super.key, required this.customer});

  final Customer customer;

  @override
  ConsumerState<CustomerPaymentModal> createState() =>
      _CustomerPaymentModalState();
}

/// One allocation line: the invoice + its amount controller.
class _Allocation {
  _Allocation(this.invoice, this.controller);

  final Invoice invoice;
  final TextEditingController controller;
}

class _CustomerPaymentModalState extends ConsumerState<CustomerPaymentModal> {
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

  List<Invoice> get _availableInvoices {
    final all = ref
            .watch(_openInvoicesProvider(widget.customer.id))
            .valueOrNull ??
        const <Invoice>[];
    final allocatedIds = {for (final a in _allocations) a.invoice.id};
    return [for (final i in all) if (!allocatedIds.contains(i.id)) i];
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

  void _addAllocation(Invoice invoice) {
    if (_allocations.any((a) => a.invoice.id == invoice.id)) return;
    // Initial amount: web parity `Math.min(balance, amount)` — capped at
    // the entered total so the sum can never silently exceed it.
    final initial = invoice.balanceAmount < _totalAmount
        ? invoice.balanceAmount
        : _totalAmount;
    final controller = TextEditingController(text: initial.toStringAsFixed(2));
    controller.addListener(() => setState(() {}));
    setState(() {
      _allocations.add(_Allocation(invoice, controller));
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
    final capped = parsed.clamp(0.0, allocation.invoice.balanceAmount.toDouble());
    if (parsed != capped) {
      // Clamp to the invoice's remaining balance (web caps per line).
      allocation.controller.text = capped.toStringAsFixed(2);
    }
    setState(() {});
  }

  void _autoAllocate() {
    final amountLeft = _totalAmount - _allocationTotal;
    if (amountLeft <= 0) return;
    var remaining = amountLeft;
    final newlyAdded = <_Allocation>[];
    for (final invoice in _availableInvoices) {
      if (remaining <= 0) break;
      final take = remaining < invoice.balanceAmount
          ? remaining
          : invoice.balanceAmount;
      final controller = TextEditingController(text: take.toStringAsFixed(2));
      controller.addListener(() => setState(() {}));
      final allocation = _Allocation(invoice, controller);
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
      setState(() => _error = l10n.customersAllocationrequired);
      return;
    }
    if ((_totalAmount - _allocationTotal).abs() > 0.005) {
      setState(
        () => _error =
            '${l10n.customersAmountmustmatch} '
            '(${Formatters.currency(_allocationTotal)})',
      );
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final invoiceNos = [
      for (final a in _allocations) a.invoice.invoiceNo,
    ];
    final result = await ref
        .read(invoiceRepositoryProvider)
        .createInvoicePayment({
          'customer_id': widget.customer.id,
          'payment_date': isoDate(_paymentDate),
          'amount': _totalAmount,
          'payment_method': _paymentMethod,
          if (_referenceController.text.trim().isNotEmpty)
            'reference_no': _referenceController.text.trim(),
          if (_notesController.text.trim().isNotEmpty)
            'notes': _notesController.text.trim(),
          'description': invoiceNos.isEmpty
              ? 'Payment'
              : 'Payment for ${invoiceNos.join(', ')}',
          'invoice_allocations': [
            for (final a in _allocations)
              {
                'invoice_id': a.invoice.id,
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
        ref.invalidate(invoicesProvider);
        invalidateCustomerQueries(ref, widget.customer.id);
      case ApiFailure(:final error):
        setState(() {
          _submitting = false;
          _error = error.message;
        });
    }
  }

  Future<void> _printReceipt() async {
    final l10n = AppLocalizations.of(context)!;
    final id = _lastPaymentId;
    if (id == null) return;
    try {
      final result = await ref.read(invoiceRepositoryProvider).payment(id);
      final payment = switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure() => null,
      };
      if (payment == null) return;
      final bytes = await buildPaymentReceiptPdf(payment);
      if (!mounted) return;
      await printPdfBytes(bytes, 'receipt-$id.pdf', context);
    } catch (error) {
      if (mounted) {
        showAppToast(context, '${l10n.errorsFailed}: $error', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    if (_lastPaymentId != null) {
      return Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    size: 36,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.customersPaymentrecordedsuccess,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.customersWhatnext,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _printReceipt,
                  icon: const Icon(Icons.print_outlined, size: 18),
                  label: Text(l10n.customersPrintreceipta4),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.commonClose),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final openInvoices =
        ref.watch(_openInvoicesProvider(widget.customer.id)).valueOrNull;

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
                l10n.customersRecordpayment,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 2),
              Text(
                '${widget.customer.customerCode} — ${widget.customer.customerName}',
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
                                label: l10n.customersTotalamount,
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
                              // Invoice allocations.
                              Text(
                                l10n.customersAllocation,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 4),
                              if (openInvoices == null)
                                const SizedBox(
                                  height: 120,
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                )
                              else if (openInvoices.isEmpty)
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  child: Text(
                                    l10n.paymentsNoopeninvoices,
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
                                // Available invoices.
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        l10n.customersAvailableinvoices,
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
                                        l10n.customersAutoallocate,
                                      ),
                                    ),
                                  ],
                                ),
                                if (_availableInvoices.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    child: Text(
                                      l10n.customersAllinvoicesallocated,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                  )
                                else
                                  for (final invoice in _availableInvoices)
                                    _AvailableInvoiceRow(
                                      invoice: invoice,
                                      onAdd: () => _addAllocation(invoice),
                                    ),
                              ],
                              const SizedBox(height: 10),
                              // Summary: Total / Allocated / Unallocated.
                              _summaryRow(
                                context,
                                l10n.customersTotalamount,
                                Formatters.currency(_totalAmount),
                              ),
                              _summaryRow(
                                context,
                                l10n.customersAllocatedinvoices,
                                Formatters.currency(_allocationTotal),
                              ),
                              _summaryRow(
                                context,
                                l10n.customersUnallocated,
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
                                    label: Text(l10n.customersRecordpayment),
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

/// One allocated line: invoice no + balance, editable amount, remove.
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
    final invoice = allocation.invoice;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invoice.invoiceNo,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  Formatters.currency(invoice.balanceAmount),
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
                suffixText: '',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: AppLocalizations.of(context)!.customersRemove,
            icon: const Icon(Icons.close, size: 18),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

/// One available invoice with an Add button.
class _AvailableInvoiceRow extends StatelessWidget {
  const _AvailableInvoiceRow({
    required this.invoice,
    required this.onAdd,
  });

  final Invoice invoice;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${invoice.invoiceNo} — ${Formatters.currency(invoice.balanceAmount)}',
              style: const TextStyle(fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            invoice.status,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: onAdd,
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: Text(
              AppLocalizations.of(context)!.customersAdd,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
