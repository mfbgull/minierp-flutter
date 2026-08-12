// Customer create/edit form — modal dialog over POST/PUT /customers.
//
// Field set + defaults port the zod `customerSchema`
// (schemas/validation-schemas.ts): name + phone required, email format
// checked when present, numeric fields coerced and clamped to >= 0,
// `payment_terms_days` defaults 14, `credit_limit`/`opening_balance`
// default 0. `customer_code` is auto-generated server-side (CUSTnnn) and
// is not part of the form (matching the web app, where the code is
// read-only). POST additionally creates the opening-balance ledger entry
// when `opening_balance != 0`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/customer.dart' show Customer;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/customer_repository.dart'
    show customerRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/form_field.dart';
import '../../widgets/form_helpers.dart';
import 'customer_providers.dart';

/// Opens the create ([customer] == null) or edit form dialog.
Future<void> showCustomerFormDialog(
  BuildContext context, {
  Customer? customer,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => CustomerFormDialog(customer: customer),
  );
}

class CustomerFormDialog extends ConsumerStatefulWidget {
  const CustomerFormDialog({super.key, this.customer});

  /// Null → create; otherwise pre-fills and PUTs to `customers/:id`.
  final Customer? customer;

  @override
  ConsumerState<CustomerFormDialog> createState() => _CustomerFormDialogState();
}

class _CustomerFormDialogState extends ConsumerState<CustomerFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _contactController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _termsController;
  late final TextEditingController _termsDaysController;
  late final TextEditingController _creditLimitController;
  late final TextEditingController _openingBalanceController;
  late final TextEditingController _billingController;
  late final TextEditingController _shippingController;

  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.customer != null;

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void initState() {
    super.initState();
    final customer = widget.customer;
    _nameController = TextEditingController(text: customer?.customerName ?? '');
    _contactController = TextEditingController(
      text: customer?.contactPerson ?? '',
    );
    _emailController = TextEditingController(text: customer?.email ?? '');
    _phoneController = TextEditingController(text: customer?.phone ?? '');
    _termsController = TextEditingController(
      text: customer?.paymentTerms ?? '',
    );
    // Zod defaults: payment_terms_days 14, credit_limit 0, opening_balance 0.
    _termsDaysController = TextEditingController(
      text: numText(customer?.paymentTermsDays ?? 14),
    );
    _creditLimitController = TextEditingController(
      text: numText(customer?.creditLimit ?? 0),
    );
    _openingBalanceController = TextEditingController(
      text: numText(customer?.openingBalance ?? 0),
    );
    _billingController = TextEditingController(
      text: customer?.billingAddress ?? '',
    );
    _shippingController = TextEditingController(
      text: customer?.shippingAddress ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _termsController.dispose();
    _termsDaysController.dispose();
    _creditLimitController.dispose();
    _openingBalanceController.dispose();
    _billingController.dispose();
    _shippingController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return _emailPattern.hasMatch(value.trim())
        ? null
        : AppLocalizations.of(context)!.customersErrorEmail;
  }

  Map<String, dynamic> _buildBody() {
    return {
      'customer_name': _nameController.text.trim(),
      // Optional fields are omitted when empty (the server model keeps its
      // defaults; empty strings would otherwise overwrite stored values on
      // edit).
      if (_contactController.text.trim().isNotEmpty)
        'contact_person': _contactController.text.trim(),
      if (_emailController.text.trim().isNotEmpty)
        'email': _emailController.text.trim(),
      'phone': _phoneController.text.trim(),
      if (_billingController.text.trim().isNotEmpty)
        'billing_address': _billingController.text.trim(),
      if (_shippingController.text.trim().isNotEmpty)
        'shipping_address': _shippingController.text.trim(),
      if (_termsController.text.trim().isNotEmpty)
        'payment_terms': _termsController.text.trim(),
      // Guaranteed non-null: the field validators run before the body is
      // built.
      'payment_terms_days': double.parse(_termsDaysController.text),
      'credit_limit': double.parse(_creditLimitController.text),
      'opening_balance': double.parse(_openingBalanceController.text),
    };
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final repo = ref.read(customerRepositoryProvider);
    final result = _isEdit
        ? await repo.update(widget.customer!.id, _buildBody())
        : await repo.create(_buildBody());
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        // Refresh the list; if editing, also refresh the (possibly open)
        // detail dialog's data for this customer.
        if (_isEdit) {
          ref.invalidate(customerDetailProvider(widget.customer!.id));
        }
        ref.invalidate(customersProvider);
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
    String? validateNumber(String? v) => nonNegativeNumberValidator(
      v,
      emptyMessage: l10n.customersErrorNumber,
      invalidMessage: l10n.customersErrorNumber,
      nonNegativeMessage: l10n.customersErrorNonnegative,
    );

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
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
                            ? l10n.customersEditcustomer
                            : l10n.customersNewcustomer,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.commonClose,
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
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
                      FormFieldShell(
                        label: l10n.customersCustomername,
                        required: true,
                        child: TextFormField(
                          controller: _nameController,
                          onFieldSubmitted: submitOnEnter(_submit),
                          autofocus: true,
                          enabled: !_submitting,
                          decoration: formInputDecoration(),
                          validator: (v) => requiredValidator(
                            v,
                            l10n.customersErrorNameRequired,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.customersContactperson,
                              child: TextFormField(
                                controller: _contactController,
                                onFieldSubmitted: submitOnEnter(_submit),
                                enabled: !_submitting,
                                decoration: formInputDecoration(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.customersPhone,
                              required: true,
                              child: TextFormField(
                                controller: _phoneController,
                                onFieldSubmitted: submitOnEnter(_submit),
                                enabled: !_submitting,
                                keyboardType: TextInputType.phone,
                                decoration: formInputDecoration(),
                                validator: (v) => requiredValidator(
                                  v,
                                  l10n.customersErrorPhoneRequired,
                                ),
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
                              label: l10n.customersEmail,
                              child: TextFormField(
                                controller: _emailController,
                                onFieldSubmitted: submitOnEnter(_submit),
                                enabled: !_submitting,
                                keyboardType: TextInputType.emailAddress,
                                decoration: formInputDecoration(),
                                validator: _validateEmail,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.customersPaymentterms,
                              child: TextFormField(
                                controller: _termsController,
                                onFieldSubmitted: submitOnEnter(_submit),
                                enabled: !_submitting,
                                decoration: formInputDecoration(),
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
                              label: l10n.customersPaymenttermsdays,
                              child: TextFormField(
                                controller: _termsDaysController,
                                onFieldSubmitted: submitOnEnter(_submit),
                                enabled: !_submitting,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: formInputDecoration(),
                                validator: validateNumber,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.customersCreditlimit,
                              child: TextFormField(
                                controller: _creditLimitController,
                                onFieldSubmitted: submitOnEnter(_submit),
                                enabled: !_submitting,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: formInputDecoration(),
                                validator: validateNumber,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.customersOpeningbalance,
                              child: TextFormField(
                                controller: _openingBalanceController,
                                onFieldSubmitted: submitOnEnter(_submit),
                                enabled: !_submitting,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: formInputDecoration(),
                                validator: validateNumber,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      FormFieldShell(
                        label: l10n.customersBillingaddress,
                        child: TextFormField(
                          controller: _billingController,
                          enabled: !_submitting,
                          minLines: 2,
                          maxLines: 3,
                          decoration: formInputDecoration(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      FormFieldShell(
                        label: l10n.customersShippingaddress,
                        child: TextFormField(
                          controller: _shippingController,
                          enabled: !_submitting,
                          minLines: 2,
                          maxLines: 3,
                          decoration: formInputDecoration(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null) ...[
                      ErrorBanner(message: _error!),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _submitting
                              ? null
                              : () => Navigator.of(context).pop(),
                          child: Text(l10n.commonCancel),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _submitting ? null : _submit,
                          child: _submitting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(l10n.commonSave),
                        ),
                      ],
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
