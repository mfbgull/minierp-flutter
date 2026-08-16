// Record Payment dialog pre-bound to one invoice — opened from the sales
// grid's per-row ⋮ menu (Payment). Port of the web invoice-actions
// payment flow: a single payment against the invoice, allocated 1:1 via
// `invoice_allocations` (the server caps the amount at the invoice's
// remaining balance). Reuses the shared payment-method list + POST body
// shape from the Payments module's RecordPaymentDialog.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart' show isoDate;
import '../../core/utils/formatters.dart';
import '../../data/models/invoice.dart' show Invoice;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/invoice_repository.dart'
    show invoiceRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/date_picker.dart' show pickDate;
import '../../widgets/form_helpers.dart';
import '../../widgets/searchable_select.dart';
import '../payments/payments_providers.dart' show paymentsProvider;
import 'invoice_providers.dart' show invoicesProvider;
import 'payment_panel.dart' show kPaymentMethods;

/// Opens the record-payment dialog for one invoice.
Future<void> showInvoicePaymentDialog(
  BuildContext context, {
  required Invoice invoice,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => InvoicePaymentDialog(invoice: invoice),
  );
}

class InvoicePaymentDialog extends ConsumerStatefulWidget {
  const InvoicePaymentDialog({super.key, required this.invoice});

  final Invoice invoice;

  @override
  ConsumerState<InvoicePaymentDialog> createState() =>
      _InvoicePaymentDialogState();
}

class _InvoicePaymentDialogState extends ConsumerState<InvoicePaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _paymentDate;
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  final _notesController = TextEditingController();
  String _paymentMethod = kPaymentMethods.first;
  bool _submitting = false;
  String? _error;

  num get _remaining => widget.invoice.balanceAmount;

  @override
  void initState() {
    super.initState();
    _paymentDate = DateTime.now();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await pickDate(
      context,
      initialDate: _paymentDate,
      firstDate: DateTime(2020),
    );
    if (picked != null) {
      setState(() => _paymentDate = picked);
    }
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    if (amount <= 0) {
      setState(() => _error = l10n.paymentsErrorAmountGreaterThanZero);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final invoice = widget.invoice;
    final result = await ref
        .read(invoiceRepositoryProvider)
        .createInvoicePayment({
          'customer_id': invoice.customerId,
          'payment_date': isoDate(_paymentDate),
          'amount': amount,
          'payment_method': _paymentMethod,
          if (_referenceController.text.trim().isNotEmpty)
            'reference_no': _referenceController.text.trim(),
          if (_notesController.text.trim().isNotEmpty)
            'notes': _notesController.text.trim(),
          'description': 'Payment for ${invoice.invoiceNo}',
          'invoice_allocations': [
            {'invoice_id': invoice.id, 'amount': amount},
          ],
        });
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        ref.invalidate(paymentsProvider);
        ref.invalidate(invoicesProvider);
        showAppToast(
          context,
          '${l10n.paymentsRecordedsuccess} — ${Formatters.currency(amount)}',
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
    final invoice = widget.invoice;

    return AlertDialog(
      title: Text(l10n.paymentsRecordpayment),
      content: SizedBox(
        width: 420,
        child: _submitting
            ? const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              )
            : Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Invoice summary line.
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(
                            alpha: 0.5,
                          ),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              invoice.invoiceNo,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (invoice.customerName != null)
                              Text(
                                invoice.customerName!,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            const SizedBox(height: 2),
                            Text(
                              '${l10n.salesBalance}: '
                              '${Formatters.currency(_remaining)}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.primary),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _pickDate,
                              icon: const Icon(
                                Icons.calendar_today_outlined,
                                size: 16,
                              ),
                              label: Text(
                                Formatters.date(isoDate(_paymentDate)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
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
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _amountController,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => setState(() {}),
                        onFieldSubmitted: (_) => _submit(),
                        decoration: formInputDecoration(
                          hintText:
                              '${l10n.fieldsAmount} · ${Formatters.number(_remaining)}',
                        ),
                        validator: (v) {
                          final amount = double.tryParse(v ?? '') ?? 0;
                          if (amount <= 0) {
                            return l10n.paymentsErrorAmountGreaterThanZero;
                          }
                          if (amount > _remaining) {
                            return l10n.paymentsErrorAmountExceedsBalance(
                              Formatters.currency(_remaining),
                            );
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _referenceController,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: formInputDecoration(
                          hintText: l10n.fieldsReference,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _notesController,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: formInputDecoration(
                          hintText: l10n.fieldsNotes,
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: scheme.error,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton.icon(
          onPressed: _submitting ? null : _submit,
          icon: const Icon(Icons.payments_outlined, size: 18),
          label: Text(l10n.paymentsRecordpayment),
        ),
      ],
    );
  }
}
