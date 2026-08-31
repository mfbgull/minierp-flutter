// Loan repay dialog — form for recording a loan repayment.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart' show isoDate;
import '../../core/utils/formatters.dart';
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/date_picker.dart' show pickDate;
import '../../widgets/form_field.dart';
import '../../widgets/form_helpers.dart';
import '../../widgets/movable_dialog.dart';
import '../../widgets/searchable_select.dart';
import '../../features/sales/payment_panel.dart' show kPaymentMethods;
import 'loan_models.dart' show EmployeeLoan;
import 'loan_repository.dart' show loanRepositoryProvider;
import 'package:minierp_app/core/theme/app_border_radius.dart';

/// Opens the loan repay dialog. Returns true if a repayment was recorded.
Future<bool?> showLoanRepayDialog(
  BuildContext context, {
  required int employeeId,
  EmployeeLoan? loan,
  int? loanId,
}) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => _LoanRepayDialog(
      employeeId: employeeId,
      loan: loan,
      loanId: loanId,
    ),
  );
}

class _LoanRepayDialog extends ConsumerStatefulWidget {
  const _LoanRepayDialog({
    required this.employeeId,
    this.loan,
    this.loanId,
  });

  final int employeeId;
  final EmployeeLoan? loan;
  final int? loanId;

  @override
  ConsumerState<_LoanRepayDialog> createState() => _LoanRepayDialogState();
}

class _LoanRepayDialogState extends ConsumerState<_LoanRepayDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _referenceController;
  late final TextEditingController _notesController;

  late DateTime _paymentDate;
  String? _paymentMethod;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final loan = widget.loan;
    // Default to remaining balance or monthly installment
    final defaultAmount = loan != null
        ? (loan.monthlyInstallment > 0 &&
                loan.monthlyInstallment <= loan.balance
            ? loan.monthlyInstallment
            : loan.balance)
        : null;
    _amountController = TextEditingController(
      text: defaultAmount != null ? _numText(defaultAmount) : '',
    );
    _referenceController = TextEditingController();
    _notesController = TextEditingController();
    _paymentDate = DateTime.now();
    _paymentMethod = 'Cash';
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  static String _numText(num value) =>
      value == value.roundToDouble() ? value.toInt().toString() : value.toString();

  Future<void> _pickDate() async {
    final picked = await pickDate(context, initialDate: _paymentDate);
    if (picked == null || !mounted) return;
    setState(() => _paymentDate = picked);
  }

  String? _validateAmount(String? value) {
    final l10n = AppLocalizations.of(context)!;
    final amount = num.tryParse(value?.trim() ?? '');
    if (amount == null || amount <= 0) return l10n.employeesInvalidamount;
    final loan = widget.loan;
    if (loan != null && amount > loan.balance) {
      return l10n.employeesLoanRepaymentExceeds;
    }
    return null;
  }

  Map<String, dynamic> _buildBody() {
    return {
      'amount': num.parse(_amountController.text.trim()),
      'payment_date': isoDate(_paymentDate),
      'payment_method': _paymentMethod?.toLowerCase() ?? 'cash',
      if (_referenceController.text.trim().isNotEmpty)
        'reference_no': _referenceController.text.trim(),
      if (_notesController.text.trim().isNotEmpty)
        'notes': _notesController.text.trim(),
    };
  }

  int get _targetLoanId => widget.loan?.id ?? widget.loanId ?? 0;

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final result = await ref.read(loanRepositoryProvider).repayLoan(
          widget.employeeId,
          _targetLoanId,
          _buildBody(),
        );
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        Navigator.of(context).pop(true);
        showAppToast(context, l10n.employeesLoanRepaid);
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
    final loan = widget.loan;

    return MovableDialog(
      dialogId: 'loan_repay',
      maxWidth: 460,
      maxHeight: 550,
      showHandle: false,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.employeesRepayLoan,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (loan != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${loan.purpose ?? l10n.employeesLoanAmount} — ${l10n.employeesLoanBalance}: ${Formatters.currency(loan.balance)}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
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
                            label: l10n.employeesLoanRepaymentAmount,
                            required: true,
                            child: TextFormField(
                              controller: _amountController,
                              onFieldSubmitted: submitOnEnter(_submit),
                              autofocus: true,
                              enabled: !_submitting,
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                              decoration: _decoration(),
                              validator: _validateAmount,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FormFieldShell(
                            label: l10n.employeesLoanRepaymentDate,
                            required: true,
                            child: SizedBox(
                              height: 44,
                              child: OutlinedButton.icon(
                                onPressed: _submitting ? null : _pickDate,
                                icon: const Icon(Icons.calendar_today_outlined,
                                    size: 16),
                                label: Text(Formatters.date(isoDate(_paymentDate))),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    FormFieldShell(
                      label: l10n.employeesLoanPaymentMethod,
                      child: SearchableSelect<String>(
                        items: kPaymentMethods,
                        selected: _paymentMethod,
                        labelBuilder: (v) => v,
                        onChanged: (v) => setState(() => _paymentMethod = v),
                      ),
                    ),
                    const SizedBox(height: 10),
                    FormFieldShell(
                      label: l10n.employeesReferenceno,
                      child: TextFormField(
                        controller: _referenceController,
                        onFieldSubmitted: submitOnEnter(_submit),
                        enabled: !_submitting,
                        decoration: _decoration(),
                      ),
                    ),
                    const SizedBox(height: 10),
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
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.payments_outlined, size: 16),
                        label: Text(l10n.employeesRepayLoan),
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
