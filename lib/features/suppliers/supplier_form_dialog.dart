// Supplier create/edit form — modal dialog over POST/PUT /suppliers.
//
// Field set + defaults port the zod `supplierSchema`
// (schemas/validation-schemas.ts) and the web SupplierForm: `supplier_code`
// + `supplier_name` required, email format checked when present, the rest
// optional. Unlike customers (whose code is server-generated CUSTnnn) the
// supplier code is user-entered on create; the server's PUT does not accept
// it, so it is read-only when editing. `is_active` mirrors the web form's
// toggle and is sent on PUT only (POST ignores it).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/supplier.dart' show Supplier;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/supplier_repository.dart'
    show supplierRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/form_field.dart';
import '../../widgets/form_helpers.dart';
import 'supplier_providers.dart';

/// Opens the create ([supplier] == null) or edit form dialog.
Future<void> showSupplierFormDialog(
  BuildContext context, {
  Supplier? supplier,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => SupplierFormDialog(supplier: supplier),
  );
}

class SupplierFormDialog extends ConsumerStatefulWidget {
  const SupplierFormDialog({super.key, this.supplier});

  /// Null → create; otherwise pre-fills and PUTs to `suppliers/:id`.
  final Supplier? supplier;

  @override
  ConsumerState<SupplierFormDialog> createState() => _SupplierFormDialogState();
}

class _SupplierFormDialogState extends ConsumerState<SupplierFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _codeController;
  late final TextEditingController _nameController;
  late final TextEditingController _contactController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  late final TextEditingController _termsController;

  late bool _isActive;

  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.supplier != null;

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void initState() {
    super.initState();
    final supplier = widget.supplier;
    _codeController = TextEditingController(text: supplier?.supplierCode ?? '');
    _nameController = TextEditingController(text: supplier?.supplierName ?? '');
    _contactController = TextEditingController(
      text: supplier?.contactPerson ?? '',
    );
    _emailController = TextEditingController(text: supplier?.email ?? '');
    _phoneController = TextEditingController(text: supplier?.phone ?? '');
    _addressController = TextEditingController(text: supplier?.address ?? '');
    // The web form defaults payment terms to 'Net 30'.
    _termsController = TextEditingController(
      text: supplier?.paymentTerms ?? 'Net 30',
    );
    _isActive = supplier?.isActive ?? true;
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _contactController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _termsController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return _emailPattern.hasMatch(value.trim())
        ? null
        : AppLocalizations.of(context)!.suppliersErrorEmail;
  }

  Map<String, dynamic> _buildBody() {
    return {
      if (_isEdit) ...{
        // PUT shape: name + optional fields + is_active; supplier_code is
        // not updatable server-side.
        'supplier_name': _nameController.text.trim(),
        'is_active': _isActive ? 1 : 0,
      } else ...{
        'supplier_code': _codeController.text.trim(),
        'supplier_name': _nameController.text.trim(),
      },
      // Optional fields are omitted when empty (the server model keeps its
      // defaults; empty strings would otherwise overwrite stored values on
      // edit).
      if (_contactController.text.trim().isNotEmpty)
        'contact_person': _contactController.text.trim(),
      if (_emailController.text.trim().isNotEmpty)
        'email': _emailController.text.trim(),
      if (_phoneController.text.trim().isNotEmpty)
        'phone': _phoneController.text.trim(),
      if (_addressController.text.trim().isNotEmpty)
        'address': _addressController.text.trim(),
      if (_termsController.text.trim().isNotEmpty)
        'payment_terms': _termsController.text.trim(),
    };
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final repo = ref.read(supplierRepositoryProvider);
    final result = _isEdit
        ? await repo.update(widget.supplier!.id, _buildBody())
        : await repo.create(_buildBody());
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        // Refresh the list; if editing, also refresh the (possibly open)
        // detail dialog's data for this supplier.
        if (_isEdit) {
          ref.invalidate(supplierDetailProvider(widget.supplier!.id));
        }
        ref.invalidate(suppliersProvider);
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
                            ? l10n.suppliersEditsupplier
                            : l10n.suppliersNewsupplier,
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
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.suppliersSuppliercode,
                              required: true,
                              child: TextFormField(
                                controller: _codeController,
                                onFieldSubmitted: submitOnEnter(_submit),
                                enabled: !_submitting && !_isEdit,
                                decoration: formInputDecoration(),
                                validator: _isEdit
                                    ? null
                                    : (v) => requiredValidator(
                                        v,
                                        l10n.suppliersErrorCodeRequired,
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.suppliersSuppliername,
                              required: true,
                              child: TextFormField(
                                controller: _nameController,
                                onFieldSubmitted: submitOnEnter(_submit),
                                autofocus: true,
                                enabled: !_submitting,
                                decoration: formInputDecoration(),
                                validator: (v) => requiredValidator(
                                  v,
                                  l10n.suppliersErrorNameRequired,
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
                              label: l10n.suppliersContactperson,
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
                              label: l10n.suppliersPhone,
                              child: TextFormField(
                                controller: _phoneController,
                                onFieldSubmitted: submitOnEnter(_submit),
                                enabled: !_submitting,
                                keyboardType: TextInputType.phone,
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
                              label: l10n.suppliersEmail,
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
                              label: l10n.suppliersPaymentterms,
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
                      FormFieldShell(
                        label: l10n.suppliersAddress,
                        child: TextFormField(
                          controller: _addressController,
                          enabled: !_submitting,
                          minLines: 2,
                          maxLines: 3,
                          decoration: formInputDecoration(),
                        ),
                      ),
                      // The Active toggle only matters on edit: the server's
                      // createSupplier ignores `is_active` (model default 1),
                      // so showing it on create would be a silent no-op.
                      if (_isEdit) ...[
                        const SizedBox(height: 4),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(l10n.statusActive),
                          value: _isActive,
                          onChanged: _submitting
                              ? null
                              : (value) => setState(() => _isActive = value),
                        ),
                      ],
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
