// Edit payment dialog — port of the web EditPaymentForm: only the
// payment date, method, reference and notes are editable; the amount is
// immutable (the server has no PUT path for it — delete and re-record
// instead). Posts `PUT /payments/:id`, then [onSaved] refreshes the
// detail dialog + list.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart' show isoDate;
import '../../core/utils/formatters.dart';
import '../../data/models/payment.dart' show Payment;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/invoice_repository.dart'
    show invoiceRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/date_picker.dart' show pickDate;
import '../../widgets/form_field.dart';
import '../../widgets/form_helpers.dart';
import '../../widgets/searchable_select.dart';
import '../sales/payment_panel.dart' show kPaymentMethods;
import 'package:minierp_app/core/theme/app_border_radius.dart';

/// Opens the edit dialog for [payment]. [onSaved] runs after a successful
/// PUT so the caller can invalidate its providers.
Future<void> showPaymentEditDialog(
  BuildContext context, {
  required Payment payment,
  VoidCallback? onSaved,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) =>
        PaymentEditDialog(payment: payment, onSaved: onSaved),
  );
}

class PaymentEditDialog extends ConsumerStatefulWidget {
  const PaymentEditDialog({super.key, required this.payment, this.onSaved});

  final Payment payment;
  final VoidCallback? onSaved;

  @override
  ConsumerState<PaymentEditDialog> createState() => _PaymentEditDialogState();
}

class _PaymentEditDialogState extends ConsumerState<PaymentEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _paymentDate;
  late String _paymentMethod;
  final _referenceController = TextEditingController();
  final _notesController = TextEditingController();

  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _paymentDate =
        DateTime.tryParse(widget.payment.paymentDate) ?? DateTime.now();
    _paymentMethod = kPaymentMethods.contains(widget.payment.paymentMethod)
        ? widget.payment.paymentMethod
        : kPaymentMethods.first;
    _referenceController.text = widget.payment.referenceNo ?? '';
    _notesController.text = widget.payment.notes ?? '';
  }

  @override
  void dispose() {
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
    if (picked != null) setState(() => _paymentDate = picked);
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    final result = await ref
        .read(invoiceRepositoryProvider)
        .updatePayment(widget.payment.id, {
          'payment_date': isoDate(_paymentDate),
          'payment_method': _paymentMethod,
          if (_referenceController.text.trim().isNotEmpty)
            'reference_no': _referenceController.text.trim(),
          if (_notesController.text.trim().isNotEmpty)
            'notes': _notesController.text.trim(),
        });
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        showAppToast(context, l10n.salesPaymentupdated);
        widget.onSaved?.call();
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

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.salesEditpayment,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${l10n.paymentsPaymentno}: ${widget.payment.paymentNo}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FormFieldShell(
                    label: l10n.fieldsAmount,
                    child: TextFormField(
                      initialValue: Formatters.currency(widget.payment.amount),
                      readOnly: true,
                      // PAY-04 (task 2.7): amount edits are rejected by the
                      // server — explain the void-and-reissue policy inline.
                      decoration: formInputDecoration().copyWith(
                        helperText: 'Amount is fixed — void this payment and '
                            'record a new one to change it',
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
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
                            initialValue: Formatters.dateTime(_paymentDate),
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: AppBorderRadius.smRadius,
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
                        onPressed: _submitting
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: Text(l10n.commonCancel),
                      ),
                      FilledButton.icon(
                        onPressed: _submitting ? null : _submit,
                        icon: _submitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
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
}
