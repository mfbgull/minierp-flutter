// Borrower create/edit form dialog — manages borrower records.
// Purely record-keeping — no GL impact on business data.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/form_field.dart';
import '../../widgets/movable_dialog.dart';
import 'package:minierp_app/core/theme/app_border_radius.dart';
import 'personal_loan_models.dart';
import 'personal_loan_repository.dart' show personalLoanRepositoryProvider;

/// Opens the borrower form dialog. Returns true if saved.
Future<bool?> showBorrowerFormDialog(
  BuildContext context, {
  PersonalLoanBorrower? borrower,
}) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => _BorrowerFormDialog(borrower: borrower),
  );
}

class _BorrowerFormDialog extends ConsumerStatefulWidget {
  const _BorrowerFormDialog({this.borrower});

  final PersonalLoanBorrower? borrower;

  @override
  ConsumerState<_BorrowerFormDialog> createState() =>
      _BorrowerFormDialogState();
}

class _BorrowerFormDialogState extends ConsumerState<_BorrowerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  String? _linkedType;
  int? _linkedId;
  bool _submitting = false;
  String? _error;

  bool get _isEditing => widget.borrower != null;

  @override
  void initState() {
    super.initState();
    final b = widget.borrower;
    _nameController = TextEditingController(text: b?.name ?? '');
    _phoneController = TextEditingController(text: b?.phone ?? '');
    _linkedType = b?.linkedType;
    _linkedId = b?.linkedId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _buildBody() {
    return {
      'name': _nameController.text.trim(),
      if (_phoneController.text.trim().isNotEmpty)
        'phone': _phoneController.text.trim(),
      'linked_type': _linkedType,
      'linked_id': _linkedId,
    };
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_nameController.text.trim().isEmpty) {
      setState(() => _error = l10n.equityPersonalLoanBorrowerRequired);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final repo = ref.read(personalLoanRepositoryProvider);
    final result = _isEditing
        ? await repo.updateBorrower(widget.borrower!.id, _buildBody())
        : await repo.createBorrower(_buildBody());
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        Navigator.of(context).pop(true);
        showAppToast(
          context,
          _isEditing
              ? l10n.equityPersonalLoanBorrowerUpdated
              : l10n.equityPersonalLoanCreated,
        );
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

    return MovableDialog(
      dialogId: 'borrower_form',
      maxWidth: 420,
      maxHeight: 500,
      showHandle: false,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                _isEditing
                    ? l10n.equityPersonalLoanEditBorrower
                    : l10n.equityPersonalLoanAddBorrower,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Name
                    FormFieldShell(
                      label: l10n.equityPersonalLoanBorrowerName,
                      required: true,
                      child: TextFormField(
                        controller: _nameController,
                        autofocus: true,
                        enabled: !_submitting,
                        decoration: _decoration(),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return l10n.equityPersonalLoanBorrowerRequired;
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Phone
                    FormFieldShell(
                      label: l10n.equityPersonalLoanBorrowerPhone,
                      child: TextFormField(
                        controller: _phoneController,
                        enabled: !_submitting,
                        decoration: _decoration(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Link to
                    FormFieldShell(
                      label: l10n.equityPersonalLoanBorrowerLinkTo,
                      child: DropdownButtonFormField<String>(
                        initialValue: _linkedType,
                        isDense: true,
                        decoration: _decoration(),
                        items: const [
                          DropdownMenuItem(
                            value: null,
                            child: Text('— None (personal contact) —'),
                          ),
                          DropdownMenuItem(
                            value: 'customer',
                            child: Text('Customer'),
                          ),
                          DropdownMenuItem(
                            value: 'supplier',
                            child: Text('Supplier'),
                          ),
                        ],
                        onChanged: (v) => setState(() {
                          _linkedType = v;
                          _linkedId = null;
                        }),
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
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: AppBorderRadius.smRadius,
                      ),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _submitting
                            ? null
                            : () => Navigator.of(context).pop(false),
                        child: Text(l10n.commonCancel),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _submitting ? null : _submit,
                        icon: _submitting
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))
                            : Icon(_isEditing ? Icons.save : Icons.add,
                                size: 16),
                        label: Text(
                          _isEditing
                              ? l10n.commonSave
                              : l10n.equityPersonalLoanAddBorrower,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _decoration() => InputDecoration(
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: AppBorderRadius.smRadius),
      );
}
