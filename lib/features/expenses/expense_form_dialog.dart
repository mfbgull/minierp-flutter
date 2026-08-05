// Expense create/edit form — modal dialog over POST/PUT /expenses.
//
// Field set mirrors the server's createExpense/updateExpense DTOs: only
// expense_category, amount and expense_date are required (400 otherwise);
// status defaults to Approved on create; everything else is optional.
// The category/status/payment-method dropdowns load from the reference
// endpoints; option lists always include the current value so an edit
// form never loses a value the loaded lists don't contain.
//
// Delete lives here too (edit mode): destructive confirm → DELETE
// /expenses/:id → toast + grid refresh.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/expense.dart'
    show Expense, ExpenseCategory, ExpenseOption;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/expense_repository.dart'
    show expenseRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/form_field.dart';
import '../../widgets/searchable_select.dart';
import 'expense_providers.dart';

/// Opens the create ([expense] == null) or edit form dialog.
Future<void> showExpenseFormDialog(BuildContext context, {Expense? expense}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => ExpenseFormDialog(expense: expense),
  );
}

class ExpenseFormDialog extends ConsumerStatefulWidget {
  const ExpenseFormDialog({super.key, this.expense});

  /// Null → create; otherwise pre-fills and PUTs to `expenses/:id`.
  final Expense? expense;

  @override
  ConsumerState<ExpenseFormDialog> createState() => _ExpenseFormDialogState();
}

class _ExpenseFormDialogState extends ConsumerState<ExpenseFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _descriptionController;
  late final TextEditingController _amountController;
  late final TextEditingController _referenceNoController;
  late final TextEditingController _vendorController;
  late final TextEditingController _projectController;

  String? _category;
  String? _paymentMethod;
  String? _status;
  late DateTime _expenseDate;

  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.expense != null;

  @override
  void initState() {
    super.initState();
    final expense = widget.expense;
    _descriptionController =
        TextEditingController(text: expense?.description ?? '');
    _amountController = TextEditingController(
      text: expense == null ? '' : _numText(expense.amount),
    );
    _referenceNoController =
        TextEditingController(text: expense?.referenceNo ?? '');
    _vendorController = TextEditingController(text: expense?.vendorName ?? '');
    _projectController = TextEditingController(text: expense?.project ?? '');
    _category = expense?.expenseCategory;
    _paymentMethod = expense?.paymentMethod;
    _status = expense?.status ?? 'Approved';
    _expenseDate = DateTime.tryParse(expense?.expenseDate ?? '') ??
        DateTime.now();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    _referenceNoController.dispose();
    _vendorController.dispose();
    _projectController.dispose();
    super.dispose();
  }

  static String _numText(num value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();

  /// The dropdowns' items always include the current value so a pre-filled
  /// edit form never loses a value the loaded list doesn't contain.
  List<T> _withCurrent<T>(List<T> loaded, T? current) {
    if (current == null || loaded.contains(current)) return loaded;
    return [...loaded, current];
  }

  String? _validateAmount(String? value) {
    final l10n = AppLocalizations.of(context)!;
    if (value == null || value.trim().isEmpty) {
      return l10n.expensesErrorAmountRequired;
    }
    final parsed = double.tryParse(value.trim());
    if (parsed == null || parsed <= 0) {
      return l10n.expensesErrorAmountInvalid;
    }
    return null;
  }

  static String _isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expenseDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => _expenseDate = picked);
  }

  Map<String, dynamic> _buildBody() {
    final description = _descriptionController.text.trim();
    final referenceNo = _referenceNoController.text.trim();
    final vendor = _vendorController.text.trim();
    final project = _projectController.text.trim();
    return {
      'expense_category': _category!,
      if (description.isNotEmpty) 'description': description,
      'amount': double.parse(_amountController.text),
      'expense_date': _isoDate(_expenseDate),
      if (_paymentMethod != null) 'payment_method': _paymentMethod,
      if (referenceNo.isNotEmpty) 'reference_no': referenceNo,
      if (vendor.isNotEmpty) 'vendor_name': vendor,
      if (project.isNotEmpty) 'project': project,
      'status': _status!,
    };
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_category == null) {
      // The category select has no FormField validator — surface the
      // server's required-field rule via the error banner (matches the
      // 400: "Expense category, amount, and expense date are required").
      setState(() => _error = l10n.expensesErrorCategoryRequired);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final repo = ref.read(expenseRepositoryProvider);
    final result = _isEdit
        ? await repo.update(widget.expense!.id, _buildBody())
        : await repo.create(_buildBody());
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        ref.invalidate(expensesProvider);
        Navigator.of(context).pop();
      case ApiFailure(:final error):
        setState(() {
          _submitting = false;
          _error = error.message;
        });
    }
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.commonDelete,
      message: l10n.expensesDeleteconfirmdesc,
      confirmLabel: l10n.commonDelete,
      cancelLabel: l10n.commonCancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    final result =
        await ref.read(expenseRepositoryProvider).delete(widget.expense!.id);
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        ref.invalidate(expensesProvider);
        Navigator.of(context).pop();
        showAppToast(context, l10n.expensesDeleted);
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
    final categories = ref.watch(expenseCategoriesProvider);
    final statusOptions = ref.watch(expenseStatusOptionsProvider);
    final paymentMethods = ref.watch(expensePaymentMethodsProvider);

    final categoryItems = _withCurrent([
      for (final c in categories.valueOrNull ?? const <ExpenseCategory>[])
        c.categoryName,
    ], _category);
    final statusItems = _withCurrent([
      for (final o in statusOptions.valueOrNull ?? const <ExpenseOption>[])
        o.value,
    ], _status);
    final paymentItems = _withCurrent([
      for (final o in paymentMethods.valueOrNull ?? const <ExpenseOption>[])
        o.value,
    ], _paymentMethod);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
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
                            ? l10n.expensesEdit
                            : l10n.expensesNewexpense,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.commonClose,
                      icon: const Icon(Icons.close),
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).pop(),
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
                            flex: 3,
                            child: FormFieldShell(
                              label: l10n.fieldsCategory,
                              required: true,
                              child: SearchableSelect<String>(
                                items: categoryItems,
                                selected: _category,
                                labelBuilder: (v) => v,
                                onChanged: (v) =>
                                    setState(() => _category = v),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: FormFieldShell(
                              label: l10n.expensesExpensedate,
                              required: true,
                              child: SizedBox(
                                height: 44,
                                child: OutlinedButton.icon(
                                  onPressed: _submitting ? null : _pickDate,
                                  icon: const Icon(
                                      Icons.calendar_today_outlined,
                                      size: 16),
                                  label: Text(
                                    Formatters.date(_isoDate(_expenseDate)),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      FormFieldShell(
                        label: l10n.fieldsAmount,
                        required: true,
                        child: TextFormField(
                          controller: _amountController,
                          enabled: !_submitting,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: _decoration(),
                          validator: _validateAmount,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.expensesPaymentmethod,
                              child: SearchableSelect<String?>(
                                items: [null, ...paymentItems],
                                selected: _paymentMethod,
                                labelBuilder: (v) =>
                                    v ?? l10n.commonNone,
                                onChanged: (v) =>
                                    setState(() => _paymentMethod = v),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.fieldsStatus,
                              required: true,
                              child: SearchableSelect<String>(
                                items: statusItems,
                                selected: _status,
                                labelBuilder: (v) => v,
                                onChanged: (v) =>
                                    setState(() => _status = v),
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
                              label: l10n.expensesVendor,
                              child: TextFormField(
                                controller: _vendorController,
                                enabled: !_submitting,
                                decoration: _decoration(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.expensesReferenceno,
                              child: TextFormField(
                                controller: _referenceNoController,
                                enabled: !_submitting,
                                decoration: _decoration(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      FormFieldShell(
                        label: l10n.expensesProject,
                        child: TextFormField(
                          controller: _projectController,
                          enabled: !_submitting,
                          decoration: _decoration(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      FormFieldShell(
                        label: l10n.expensesDescription,
                        child: TextFormField(
                          controller: _descriptionController,
                          enabled: !_submitting,
                          minLines: 2,
                          maxLines: 4,
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
                      _ErrorBanner(message: _error!),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      children: [
                        if (_isEdit)
                          TextButton.icon(
                            onPressed: _submitting ? null : _delete,
                            style: TextButton.styleFrom(
                              foregroundColor:
                                  Theme.of(context).colorScheme.error,
                            ),
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: Text(l10n.commonDelete),
                          ),
                        const Spacer(),
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
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
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

  InputDecoration _decoration() => InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
