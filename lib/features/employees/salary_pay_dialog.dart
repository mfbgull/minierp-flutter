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
import '../../widgets/date_picker_helpers.dart' show pickDate;
import '../../widgets/form_field.dart';
import '../../widgets/form_helpers.dart';
import '../../widgets/searchable_select.dart';
import '../../features/sales/payment_panel.dart' show kPaymentMethods;
import 'employee_models.dart';
import 'employee_providers.dart';
import 'employee_repository.dart' show employeeRepositoryProvider;

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
      if (reference.isNotEmpty) 'reference_no': reference,
      if (notes.isNotEmpty) 'notes': notes,
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
        .read(employeeRepositoryProvider)
        .paySalary(widget.employee.id, _buildBody());
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        ref.invalidate(employeesProvider);
        ref.invalidate(employeeDetailProvider(widget.employee.id));
        ref.invalidate(employeeSalaryHistoryProvider(widget.employee.id));
        Navigator.of(context).pop();
        showAppToast(context, l10n.employeesSalarypaid);
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
    final employee = widget.employee;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
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
                          borderRadius: BorderRadius.circular(8),
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
      ),
    );
  }

  InputDecoration _decoration() => InputDecoration(
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
  );
}
