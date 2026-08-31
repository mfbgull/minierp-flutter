// Loan create dialog — form for creating a new employee loan.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart' show isoDate;
import '../../core/utils/formatters.dart';
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/date_picker.dart' show pickDate;
import '../../widgets/form_field.dart';
import '../../widgets/movable_dialog.dart';
import '../../widgets/searchable_select.dart';
import '../../features/sales/payment_panel.dart' show kPaymentMethods;
import 'loan_repository.dart' show loanRepositoryProvider;
import 'package:minierp_app/core/theme/app_border_radius.dart';

/// Opens the loan create dialog. Returns true if a loan was created.
Future<bool?> showLoanCreateDialog(
  BuildContext context, {
  required int employeeId,
}) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => _LoanCreateDialog(employeeId: employeeId),
  );
}

class _LoanCreateDialog extends ConsumerStatefulWidget {
  const _LoanCreateDialog({required this.employeeId});

  final int employeeId;

  @override
  ConsumerState<_LoanCreateDialog> createState() => _LoanCreateDialogState();
}

class _LoanCreateDialogState extends ConsumerState<_LoanCreateDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _purposeController;
  late final TextEditingController _installmentController;
  late final TextEditingController _notesController;

  late DateTime _disbursementDate;
  DateTime? _dueDate;
  String? _paymentMethod;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController();
    _purposeController = TextEditingController();
    _installmentController = TextEditingController();
    _notesController = TextEditingController();
    _disbursementDate = DateTime.now();
    _paymentMethod = 'Cash';
  }

  @override
  void dispose() {
    _amountController.dispose();
    _purposeController.dispose();
    _installmentController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDisbursementDate() async {
    final picked = await pickDate(context, initialDate: _disbursementDate);
    if (picked == null || !mounted) return;
    setState(() => _disbursementDate = picked);
  }

  Future<void> _pickDueDate() async {
    final picked = await pickDate(
      context,
      initialDate: _dueDate ?? _disbursementDate.add(const Duration(days: 90)),
    );
    if (picked == null || !mounted) return;
    setState(() => _dueDate = picked);
  }

  String? _validateAmount(String? value) {
    final l10n = AppLocalizations.of(context)!;
    final amount = num.tryParse(value?.trim() ?? '');
    if (amount == null || amount <= 0) return l10n.employeesInvalidamount;
    return null;
  }

  Map<String, dynamic> _buildBody() {
    final amount = num.tryParse(_amountController.text.trim()) ?? 0;
    return {
      'amount': amount,
      'disbursement_date': isoDate(_disbursementDate),
      if (_dueDate != null) 'due_date': isoDate(_dueDate!),
      if (_purposeController.text.trim().isNotEmpty)
        'purpose': _purposeController.text.trim(),
      'payment_method': _paymentMethod?.toLowerCase() ?? 'cash',
      if (_installmentController.text.trim().isNotEmpty)
        'monthly_installment':
            num.tryParse(_installmentController.text.trim()) ?? 0,
      if (_notesController.text.trim().isNotEmpty)
        'notes': _notesController.text.trim(),
    };
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final result = await ref
        .read(loanRepositoryProvider)
        .createLoan(widget.employeeId, _buildBody());
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        Navigator.of(context).pop(true);
        showAppToast(context, l10n.employeesLoanCreated);
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
      dialogId: 'loan_create',
      maxWidth: 460,
      maxHeight: 600,
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
                l10n.employeesNewLoan,
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
                    // Amount
                    FormFieldShell(
                      label: l10n.employeesLoanAmount,
                      required: true,
                      child: TextFormField(
                        controller: _amountController,
                        autofocus: true,
                        enabled: !_submitting,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: _decoration(),
                        validator: _validateAmount,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Disbursement Date + Due Date
                    Row(
                      children: [
                        Expanded(
                          child: FormFieldShell(
                            label: l10n.employeesLoanDisbursementDate,
                            required: true,
                            child: SizedBox(
                              height: 44,
                              child: OutlinedButton.icon(
                                onPressed:
                                    _submitting ? null : _pickDisbursementDate,
                                icon: const Icon(Icons.calendar_today_outlined,
                                    size: 16),
                                label: Text(
                                    Formatters.date(isoDate(_disbursementDate))),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FormFieldShell(
                            label: l10n.employeesLoanDueDate,
                            required: true,
                            child: SizedBox(
                              height: 44,
                              child: OutlinedButton.icon(
                                onPressed: _submitting ? null : _pickDueDate,
                                icon: const Icon(Icons.calendar_today_outlined,
                                    size: 16),
                                label: Text(
                                  _dueDate != null
                                      ? Formatters.date(isoDate(_dueDate!))
                                      : l10n.employeesLoanDueDate,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Purpose
                    FormFieldShell(
                      label: l10n.employeesLoanPurpose,
                      child: TextFormField(
                        controller: _purposeController,
                        enabled: !_submitting,
                        decoration: _decoration(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Payment Method
                    FormFieldShell(
                      label: l10n.employeesLoanPaymentMethod,
                      child: SearchableSelect<String>(
                        items: kPaymentMethods,
                        selected: _paymentMethod,
                        labelBuilder: (v) => v,
                        onChanged: (v) =>
                            setState(() => _paymentMethod = v),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Monthly Installment
                    FormFieldShell(
                      label: l10n.employeesLoanMonthlyInstallment,
                      child: TextFormField(
                        controller: _installmentController,
                        enabled: !_submitting,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: _decoration(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Notes
                    FormFieldShell(
                      label: l10n.employeesSalarynotes,
                      child: TextFormField(
                        controller: _notesController,
                        enabled: !_submitting,
                        minLines: 2,
                        maxLines: 3,
                        decoration: _decoration(),
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
                            : const Icon(Icons.add, size: 16),
                        label: Text(l10n.employeesNewLoan),
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
