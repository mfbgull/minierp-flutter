// Record Payment dialog — the invoice payments flow (`POST /payments`
// with `invoice_allocations`; there is no `POST /invoices/:id/pay` — the
// server allocates a customer payment across that customer's open
// invoices, validating each line against the invoice's remaining balance
// and the total against the payment amount). Opens from the Payments
// screen toolbar.
//
// Flow: pick a customer → their open invoices (balance > 0) load as
// allocation lines → enter per-invoice amounts (capped at each balance) →
// the payment amount is derived as the running total (so the server's
// sum-match check always passes) → POST. On success the payments list
// and the invoices list are invalidated — the invoice's paid/balance
// amounts refetch on next view.

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart' show isoDate;
import '../../core/utils/formatters.dart';
import '../../data/models/customer.dart' show Customer;
import '../../data/models/invoice.dart' show Invoice;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/invoice_repository.dart'
    show invoiceRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/date_picker_helpers.dart' show pickDate;
import '../../widgets/form_field.dart';
import '../../widgets/form_helpers.dart';
import '../../widgets/searchable_select.dart';
import '../sales/invoice_providers.dart' show invoicesProvider;
import '../sales/payment_panel.dart' show kPaymentMethods;
import 'payments_providers.dart';

/// Opens the Record Payment dialog (customer + allocations).
Future<void> showRecordPaymentDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => const RecordPaymentDialog(),
  );
}

class RecordPaymentDialog extends ConsumerStatefulWidget {
  const RecordPaymentDialog({super.key});

  @override
  ConsumerState<RecordPaymentDialog> createState() =>
      _RecordPaymentDialogState();
}

class _RecordPaymentDialogState extends ConsumerState<RecordPaymentDialog> {
  final _formKey = GlobalKey<FormState>();

  int? _customerId;
  late DateTime _paymentDate;

  /// One amount controller per open invoice (parallel lists — rebuilt
  /// when the customer's invoice set changes).
  final List<TextEditingController> _amountControllers = [];

  /// Invoice ids the [_amountControllers] are currently wired to — the
  /// sync guard compares identity, not just length, so a different
  /// invoice set of the same size still rebuilds the controllers.
  List<int> _wiredInvoiceIds = const [];

  late final TextEditingController _dateController;

  String _paymentMethod = kPaymentMethods.first;
  final _referenceController = TextEditingController();
  final _notesController = TextEditingController();

  bool _submitting = false;
  String? _error;

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
    for (final c in _amountControllers) {
      c.dispose();
    }
    _dateController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _onCustomerChanged(int? customerId) {
    for (final c in _amountControllers) {
      c.dispose();
    }
    setState(() {
      _customerId = customerId;
      _amountControllers.clear();
      _error = null;
    });
  }

  void _syncAmountControllers(List<Invoice> invoices) {
    // Rebuild only when the invoice set actually changed (e.g. a
    // different customer), not on every rebuild.
    final ids = [for (final i in invoices) i.id];
    if (listEquals(ids, _wiredInvoiceIds)) return;
    for (final c in _amountControllers) {
      c.dispose();
    }
    _amountControllers
      ..clear()
      ..addAll([for (final _ in invoices) TextEditingController()]);
    _wiredInvoiceIds = ids;
  }

  num get _totalAllocated {
    var total = 0.0;
    for (final c in _amountControllers) {
      total += double.tryParse(c.text.trim()) ?? 0;
    }
    return total;
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

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_customerId == null) return;
    final invoices =
        ref.read(customerOpenInvoicesProvider(_customerId!)).valueOrNull ??
        const <Invoice>[];

    final allocations = <Map<String, dynamic>>[];
    for (var i = 0; i < invoices.length; i++) {
      final qty = double.tryParse(_amountControllers[i].text.trim()) ?? 0;
      if (qty > 0) {
        allocations.add({'invoice_id': invoices[i].id, 'amount': qty});
      }
    }
    if (allocations.isEmpty) {
      setState(() => _error = l10n.paymentsErrorAmountGreaterThanZero);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final result = await ref
        .read(invoiceRepositoryProvider)
        .createInvoicePayment({
          'customer_id': _customerId,
          'payment_date': isoDate(_paymentDate),
          'amount': _totalAllocated,
          'payment_method': _paymentMethod,
          if (_referenceController.text.trim().isNotEmpty)
            'reference_no': _referenceController.text.trim(),
          if (_notesController.text.trim().isNotEmpty)
            'notes': _notesController.text.trim(),
          'invoice_allocations': allocations,
        });
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        ref.invalidate(paymentsProvider);
        ref.invalidate(invoicesProvider);
        showAppToast(
          context,
          '${l10n.paymentsRecordedsuccess} — '
          '${Formatters.currency(_totalAllocated)}',
        );
        Navigator.of(context).pop();
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
    final customers =
        ref.watch(paymentCustomerOptionsProvider).valueOrNull ??
        const <Customer>[];
    final customerIds = [for (final c in customers) c.id];
    final openInvoices = _customerId == null
        ? null
        : ref.watch(customerOpenInvoicesProvider(_customerId!)).valueOrNull;

    // Keep the per-line controllers aligned with the loaded invoice set.
    if (openInvoices != null) _syncAmountControllers(openInvoices);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.paymentsRecordpayment,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 2),
              Text(
                l10n.paymentsSubtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: _buildBody(l10n, customers, customerIds, openInvoices),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    AppLocalizations l10n,
    List<Customer> customers,
    List<int> customerIds,
    List<Invoice>? openInvoices,
  ) {
    if (_submitting) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FormFieldShell(
              label: l10n.paymentsSelectcustomer,
              required: true,
              child: SearchableSelect<int>(
                items: customerIds,
                selected: _customerId,
                labelBuilder: (id) {
                  final match = customers.where((c) => c.id == id);
                  final customer = match.isEmpty ? null : match.first;
                  return customer == null
                      ? '$id'
                      : '${customer.customerCode} — ${customer.customerName}';
                },
                validator: (v) => v == null ? l10n.commonRequired : null,
                onChanged: _onCustomerChanged,
              ),
            ),
            if (_customerId != null) ...[
              const SizedBox(height: 12),
              Text(
                l10n.paymentsOpeninvoices,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                l10n.paymentsSelectinvoices,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              if (openInvoices == null)
                const SizedBox(
                  height: 120,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (openInvoices.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    l10n.paymentsNoopeninvoices,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                for (var i = 0; i < openInvoices.length; i++) ...[
                  if (i > 0) const Divider(height: 12),
                  _AllocationLineRow(
                    invoice: openInvoices[i],
                    controller: _amountControllers[i],
                    autofocus: i == 0,
                    onAmountChanged: () => setState(() {}),
                    onSubmit: _submit,
                  ),
                ],
              if (_totalAllocated > 0) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${l10n.paymentsTotalallocated}: '
                    '${Formatters.currency(_totalAllocated)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ],
            const SizedBox(height: 12),
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
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        suffixIcon: const Icon(Icons.calendar_today, size: 16),
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
                          setState(() => _paymentMethod = value);
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            FormFieldShell(
              label: l10n.fieldsReference,
              child: TextFormField(
                controller: _referenceController,
                onFieldSubmitted: submitOnEnter(_submit),
                decoration: formInputDecoration(
                  hintText: l10n.paymentsReferencehint,
                ),
              ),
            ),
            const SizedBox(height: 10),
            FormFieldShell(
              label: l10n.fieldsNotes,
              child: TextFormField(
                controller: _notesController,
                onFieldSubmitted: submitOnEnter(_submit),
                decoration: formInputDecoration(
                  hintText: l10n.paymentsNoteshint,
                ),
              ),
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
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.commonCancel),
                ),
                FilledButton.icon(
                  onPressed: _customerId == null || _totalAllocated <= 0
                      ? null
                      : _submit,
                  icon: const Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 18,
                  ),
                  label: Text(l10n.paymentsRecordpayment),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One allocation line: invoice no + remaining balance on the left, the
/// amount input on the right (capped at the balance).
class _AllocationLineRow extends StatelessWidget {
  const _AllocationLineRow({
    required this.invoice,
    required this.controller,
    required this.autofocus,
    required this.onAmountChanged,
    required this.onSubmit,
  });

  final Invoice invoice;
  final TextEditingController controller;

  /// Focuses the first allocation amount on open so the user can start
  /// typing straight away (the amounts are the dialog's primary input).
  final bool autofocus;

  /// Rebuilds the dialog so the running total + submit button track the
  /// entered amounts (enterText alone doesn't rebuild the parent).
  final VoidCallback onAmountChanged;

  /// Enter-to-submit: pressing Enter in a filled line saves the payment
  /// (same [submitOnEnter] contract as the header's reference/notes).
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final muted = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final balance = invoice.balanceAmount;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                invoice.invoiceNo,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (invoice.customerName != null)
                Text(invoice.customerName!, style: muted),
              const SizedBox(height: 2),
              Text(
                '${l10n.paymentsBalance}: ${Formatters.currency(balance)}',
                style: muted,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 140,
          child: FormFieldShell(
            label: l10n.fieldsAmount,
            child: TextFormField(
              controller: controller,
              autofocus: autofocus,
              onChanged: (_) => onAmountChanged(),
              onFieldSubmitted: submitOnEnter(onSubmit),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: formInputDecoration(
                hintText: Formatters.number(balance),
              ),
              // Empty lines are optional; a filled line must be a valid,
              // non-negative amount within the remaining balance.
              validator: (v) {
                final text = (v ?? '').trim();
                if (text.isEmpty) return null;
                final amount = double.tryParse(text);
                if (amount == null || amount <= 0) {
                  return l10n.paymentsErrorAmountGreaterThanZero;
                }
                if (amount > balance) {
                  return l10n.paymentsErrorAmountExceedsBalance(
                    Formatters.currency(balance),
                  );
                }
                return null;
              },
            ),
          ),
        ),
      ],
    );
  }
}
