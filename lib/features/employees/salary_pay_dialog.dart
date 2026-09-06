// Salary pay dialog — PORTING.md §5 ("EmployeesScreen incl. salary pay
// modal"). Posts `POST /employees/:id/salary/pay` with amount, payment
// date, method, reference and notes; the server records the salary_payment
// and posts the GL entry. Amount defaults to the employee's monthly salary
// and must be positive; the payment date defaults to today.

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
import 'employee_models.dart';
import 'employee_providers.dart';
import 'employee_repository.dart' show employeeRepositoryProvider;
import 'loan_models.dart' show EmployeeLoan;
import 'loan_providers.dart';
import 'loan_repository.dart' show loanRepositoryProvider;
import 'package:minierp_app/core/theme/app_border_radius.dart';

/// Opens the salary pay modal for one employee.
Future<void> showSalaryPayDialog(
  BuildContext context, {
  required Employee employee,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => SalaryPayDialog(employee: employee),
  );
}

class SalaryPayDialog extends ConsumerStatefulWidget {
  const SalaryPayDialog({super.key, required this.employee});

  final Employee employee;

  @override
  ConsumerState<SalaryPayDialog> createState() => _SalaryPayDialogState();
}

class _SalaryPayDialogState extends ConsumerState<SalaryPayDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _referenceController;
  late final TextEditingController _notesController;

  late DateTime _paymentDate;
  String? _paymentMethod;
  String _paymentType = 'full';
  late final TextEditingController _loanDeductionController;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final employee = widget.employee;
    _amountController = TextEditingController(
      text: employee.salary == 0 ? '' : _numText(employee.salary),
    );
    _referenceController = TextEditingController();
    _notesController = TextEditingController();
    _loanDeductionController = TextEditingController();
    _paymentDate = DateTime.now();
    // The server defaults to `bank`; the reference dropdown leads with
    // the most common method.
    _paymentMethod = 'Bank Transfer';
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    _loanDeductionController.dispose();
    super.dispose();
  }

  static String _numText(num value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();

  Future<void> _pickDate() async {
    final picked = await pickDate(context, initialDate: _paymentDate);
    if (picked == null || !mounted) return;
    setState(() => _paymentDate = picked);
  }

  String? _validateAmount(String? value) {
    final l10n = AppLocalizations.of(context)!;
    final amount = num.tryParse(value?.trim() ?? '');
    if (amount == null || amount <= 0) {
      return l10n.employeesInvalidamount;
    }
    return null;
  }

  Map<String, dynamic> _buildBody() {
    final reference = _referenceController.text.trim();
    final notes = _notesController.text.trim();
    return {
      'amount': num.parse(_amountController.text.trim()),
      'payment_date': isoDate(_paymentDate),
      'payment_method': _paymentMethod ?? 'bank',
      'payment_type': _paymentType,
      if (reference.isNotEmpty) 'reference_no': reference,
      if (notes.isNotEmpty) 'notes': notes,
    };
  }

  /// Loan deduction amount entered by the user.
  num get _loanDeduction =>
      num.tryParse(_loanDeductionController.text.trim()) ?? 0;

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final result = await ref
        .read(employeeRepositoryProvider)
        .paySalary(widget.employee.id, _buildBody());
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        // If loan deduction > 0, create a loan repayment record.
        if (_loanDeduction > 0) {
          await _recordLoanDeduction();
        }
        if (!mounted) return;
        ref.invalidate(employeesProvider);
        ref.invalidate(employeeDetailProvider(widget.employee.id));
        ref.invalidate(employeeSalaryHistoryProvider(widget.employee.id));
        ref.invalidate(employeeLoansProvider(widget.employee.id));
        Navigator.of(context).pop();
        showAppToast(context, l10n.employeesSalarypaid);
      case ApiFailure(:final error):
        setState(() {
          _submitting = false;
          _error = error.message;
        });
    }
  }

  /// Records a loan repayment for each active loan with the deduction amount.
  Future<void> _recordLoanDeduction() async {
    final deduction = _loanDeduction;
    if (deduction <= 0) return;

    final activeLoans = ref.read(employeeActiveLoansProvider(widget.employee.id));
    if (activeLoans.isEmpty) return;

    // Apply deduction to the first active loan (sorted by due date)
    final loan = activeLoans.first;
    final repayAmount = deduction <= loan.balance ? deduction : loan.balance;

    await ref.read(loanRepositoryProvider).repayLoan(
      widget.employee.id,
      loan.id,
      {
        'amount': repayAmount,
        'payment_date': isoDate(_paymentDate),
        'payment_method': _paymentMethod?.toLowerCase() ?? 'bank',
        'notes': 'Loan deduction from salary payment',
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final employee = widget.employee;
    final activeLoans = ref.watch(employeeActiveLoansProvider(employee.id));

    return MovableDialog(
      dialogId: 'salary_pay',
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.employeesPaysalary,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${employee.employeeCode} · ${employee.fullName}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.employeesSalaryamount,
                              required: true,
                              child: TextFormField(
                                controller: _amountController,
                                onFieldSubmitted: submitOnEnter(_submit),
                                autofocus: true,
                                enabled: !_submitting,
                                keyboardType: const TextInputType
                                    .numberWithOptions(decimal: true),
                                decoration: _decoration(),
                                validator: _validateAmount,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.employeesPaymentdate,
                              required: true,
                              child: SizedBox(
                                height: 44,
                                child: OutlinedButton.icon(
                                  onPressed: _submitting ? null : _pickDate,
                                  icon: const Icon(
                                    Icons.calendar_today_outlined,
                                    size: 16,
                                  ),
                                  label: Text(
                                    Formatters.date(isoDate(_paymentDate)),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      FormFieldShell(
                        label: l10n.employeesPaymenttype,
                        child: SearchableSelect<String>(
                          items: const ['full', 'advance', 'partial'],
                          selected: _paymentType,
                          labelBuilder: (v) => switch (v) {
                            'full' => l10n.employeesPaymenttypeFull,
                            'advance' => l10n.employeesPaymenttypeAdvance,
                            'partial' => l10n.employeesPaymenttypePartial,
                            _ => v,
                          },
                          onChanged: (v) => setState(() => _paymentType = v ?? 'full'),
                        ),
                      ),
                      const SizedBox(height: 6),
                      _RemainingBalance(employee: widget.employee, paymentType: _paymentType, paymentDate: _paymentDate),
                      if (activeLoans.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _LoanDeductionSection(
                          activeLoans: activeLoans,
                          controller: _loanDeductionController,
                          enabled: !_submitting,
                        ),
                      ],
                      const SizedBox(height: 10),
                      FormFieldShell(
                        label: l10n.employeesPaymentmethod,
                        child: SearchableSelect<String>(
                          items: kPaymentMethods,
                          selected: _paymentMethod,
                          labelBuilder: (v) => v,
                          onChanged: (v) =>
                              setState(() => _paymentMethod = v),
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
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.errorContainer,
                          borderRadius: AppBorderRadius.smRadius,
                        ),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onErrorContainer,
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
                              : () => Navigator.of(context).pop(),
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
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.payments_outlined, size: 16),
                          label: Text(l10n.employeesPaysalary),
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
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(borderRadius: AppBorderRadius.smRadius),
  );
}

/// Shows remaining salary balance for the selected month based on payment type.
class _RemainingBalance extends ConsumerWidget {
  const _RemainingBalance({
    required this.employee,
    required this.paymentType,
    required this.paymentDate,
  });

  final Employee employee;
  final String paymentType;
  final DateTime paymentDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final history = ref.watch(employeeSalaryHistoryProvider(employee.id));

    if (paymentType == 'advance') {
      // For advance payments, just show the salary amount as context
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: AppBorderRadius.smRadius,
      ),
      child: Text(
        '${l10n.employeesSalaryamount}: ${Formatters.currency(employee.salary)}',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
    }

    return history.when(
      data: (months) {
        final selectedMonth = '${paymentDate.year}-${paymentDate.month.toString().padLeft(2, '0')}';
        final thisMonth = months.where((m) => m.payPeriod == selectedMonth);
        final totalPaid = thisMonth.fold<num>(0, (sum, m) => sum + m.totalPaid);
        final advanceCarryover = thisMonth.fold<num>(0, (sum, m) => sum + m.advanceCarryover);
        final sourceMonth = thisMonth.isNotEmpty ? thisMonth.first.displaySourceMonth : null;
        final effectiveRemaining = employee.salary - totalPaid - advanceCarryover;
        if (effectiveRemaining <= 0 && advanceCarryover <= 0) return const SizedBox.shrink();
        final advanceLabel = sourceMonth != null
          ? '${l10n.employeesAdvanceFrom} $sourceMonth'
          : l10n.employeesAdvanceFromPrevious;
        if (effectiveRemaining <= 0) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: AppBorderRadius.smRadius,
            ),
            child: Text(
              '$advanceLabel: ${Formatters.currency(advanceCarryover)} — ${l10n.employeesRemainingbalance}: ${Formatters.currency(0)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onPrimaryContainer,
              ),
            ),
          );
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.tertiaryContainer.withValues(alpha: 0.3),
            borderRadius: AppBorderRadius.smRadius,
          ),
          child: Text(
            advanceCarryover > 0
              ? '${l10n.employeesAlreadyPaid}: ${Formatters.currency(totalPaid)} + $advanceLabel: ${Formatters.currency(advanceCarryover)} — ${l10n.employeesRemainingbalance}: ${Formatters.currency(effectiveRemaining)}'
              : '${l10n.employeesAlreadyPaid}: ${Formatters.currency(totalPaid)} — ${l10n.employeesRemainingbalance}: ${Formatters.currency(effectiveRemaining)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onTertiaryContainer,
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

/// Shows active loan banner with deduction field.
class _LoanDeductionSection extends StatelessWidget {
  const _LoanDeductionSection({
    required this.activeLoans,
    required this.controller,
    required this.enabled,
  });

  final List<EmployeeLoan> activeLoans;
  final TextEditingController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final loan = activeLoans.first;

    // Default suggestion: monthly installment or remaining balance
    final suggested = loan.monthlyInstallment > 0 &&
            loan.monthlyInstallment <= loan.balance
        ? loan.monthlyInstallment
        : loan.balance;

    // Pre-fill if empty
    if (controller.text.isEmpty && suggested > 0) {
      controller.text = suggested == suggested.roundToDouble()
          ? suggested.toInt().toString()
          : suggested.toString();
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.3),
        borderRadius: AppBorderRadius.smRadius,
        border: Border.all(
          color: scheme.tertiary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Loan info banner
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 16,
                color: scheme.tertiary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${l10n.employeesLoanAmount}: ${loan.purpose ?? Formatters.currency(loan.amount)} — ${l10n.employeesLoanBalance}: ${Formatters.currency(loan.balance)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onTertiaryContainer,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          if (loan.dueDate != null) ...[
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Text(
                '${l10n.employeesLoanDueDate}: ${Formatters.date(loan.dueDate!)}${loan.monthlyInstallment > 0 ? ' · ${l10n.employeesLoanSuggestedInstallment}: ${Formatters.currency(loan.monthlyInstallment)}' : ''}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onTertiaryContainer.withValues(alpha: 0.8),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          // Deduction field
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.employeesLoanDeductFromSalary,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onTertiaryContainer,
                  ),
                ),
              ),
              SizedBox(
                width: 120,
                child: TextFormField(
                  controller: controller,
                  enabled: enabled,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: Theme.of(context).textTheme.bodySmall,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    border: OutlineInputBorder(borderRadius: AppBorderRadius.smRadius),
                    prefixText: 'Rs. ',
                    prefixStyle: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
