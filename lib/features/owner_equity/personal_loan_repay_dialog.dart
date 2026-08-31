// Personal loan repayment dialog — form for recording a repayment received.
// Purely record-keeping — no GL impact.

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
import 'package:minierp_app/core/theme/app_border_radius.dart';
import 'personal_loan_models.dart';
import 'personal_loan_repository.dart' show personalLoanRepositoryProvider;

/// Opens the personal loan repayment dialog. Returns true if saved.
Future<bool?> showPersonalLoanRepayDialog(
  BuildContext context, {
  required int loanId,
  required PersonalLoan loan,
}) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) =>
        _PersonalLoanRepayDialog(loanId: loanId, loan: loan),
  );
}

class _PersonalLoanRepayDialog extends ConsumerStatefulWidget {
  const _PersonalLoanRepayDialog({
    required this.loanId,
    required this.loan,
  });

  final int loanId;
  final PersonalLoan loan;

  @override
  ConsumerState<_PersonalLoanRepayDialog> createState() =>
      _PersonalLoanRepayDialogState();
}

class _PersonalLoanRepayDialogState
    extends ConsumerState<_PersonalLoanRepayDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _notesController;
  late DateTime _paymentDate;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.loan.balance.toString(),
    );
    _notesController = TextEditingController();
    _paymentDate = DateTime.now();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _buildBody() {
    final amount = num.tryParse(_amountController.text.trim()) ?? 0;
    return {
      'amount': amount,
      'payment_date': isoDate(_paymentDate),
      if (_notesController.text.trim().isNotEmpty)
        'notes': _notesController.text.trim(),
    };
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final amount = num.tryParse(_amountController.text.trim()) ?? 0;
    if (amount > widget.loan.balance) {
      setState(() {
        _error = l10n.equityPersonalLoanRepaymentExceeds;
      });
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final result = await ref
        .read(personalLoanRepositoryProvider)
        .addRepayment(widget.loanId, _buildBody());
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        Navigator.of(context).pop(true);
        showAppToast(context, l10n.equityPersonalLoanRepaymentAdded);
      case ApiFailure(:final error):
        setState(() {
          _submitting = false;
          _error = error.message;
        });
    }
  }

  Future<void> _pickPaymentDate() async {
    final picked = await pickDate(context, initialDate: _paymentDate);
    if (picked == null || !mounted) return;
    setState(() => _paymentDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final loan = widget.loan;

    return MovableDialog(
      dialogId: 'personal_loan_repay',
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.equityPersonalLoanAddRepayment,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${loan.loanNo} · ${loan.borrowerName} · Balance: ${Formatters.currency(loan.balance)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
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
                    // Amount
                    FormFieldShell(
                      label: l10n.equityPersonalLoanRepaymentAmount,
                      required: true,
                      child: TextFormField(
                        controller: _amountController,
                        autofocus: true,
                        enabled: !_submitting,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: _decoration(),
                        validator: (v) {
                          final amount = num.tryParse(v?.trim() ?? '');
                          if (amount == null || amount <= 0) {
                            return l10n.employeesInvalidamount;
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Payment Date
                    FormFieldShell(
                      label: l10n.equityPersonalLoanRepaymentDate,
                      required: true,
                      child: SizedBox(
                        height: 44,
                        child: OutlinedButton.icon(
                          onPressed: _submitting ? null : _pickPaymentDate,
                          icon: const Icon(Icons.calendar_today_outlined,
                              size: 16),
                          label: Text(Formatters.date(isoDate(_paymentDate))),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Notes
                    FormFieldShell(
                      label: l10n.equityPersonalLoanRepaymentNotes,
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
                            : const Icon(Icons.payments_outlined, size: 16),
                        label: Text(l10n.equityPersonalLoanAddRepayment),
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
