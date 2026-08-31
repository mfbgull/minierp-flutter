// Personal loan create/edit dialog — form for creating or editing a personal loan.
// Includes inline borrower selection with "Add New" option.

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
import 'personal_loan_providers.dart';
import 'personal_loan_repository.dart' show personalLoanRepositoryProvider;

/// Opens the personal loan create/edit dialog. Returns true if saved.
Future<bool?> showPersonalLoanCreateDialog(
  BuildContext context, {
  PersonalLoan? loan,
}) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => _PersonalLoanCreateDialog(loan: loan),
  );
}

class _PersonalLoanCreateDialog extends ConsumerStatefulWidget {
  const _PersonalLoanCreateDialog({this.loan});

  final PersonalLoan? loan;

  @override
  ConsumerState<_PersonalLoanCreateDialog> createState() =>
      _PersonalLoanCreateDialogState();
}

class _PersonalLoanCreateDialogState
    extends ConsumerState<_PersonalLoanCreateDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _purposeController;
  late final TextEditingController _notesController;

  late DateTime _loanDate;
  DateTime? _dueDate;
  String _currency = 'PKR';
  bool _submitting = false;
  String? _error;

  // Borrower state
  PersonalLoanBorrower? _selectedBorrower;
  bool _showAddBorrower = false;
  final _newBorrowerNameController = TextEditingController();
  final _newBorrowerPhoneController = TextEditingController();
  PersonalLoanBorrower? _newBorrowerLinkTo;

  bool get _isEditing => widget.loan != null;

  @override
  void initState() {
    super.initState();
    final loan = widget.loan;
    _amountController = TextEditingController(
      text: loan != null ? loan.amount.toString() : '',
    );
    _purposeController = TextEditingController(text: loan?.purpose ?? '');
    _notesController = TextEditingController(text: loan?.notes ?? '');
    _loanDate = loan != null
        ? (DateTime.tryParse(loan.loanDate) ?? DateTime.now())
        : DateTime.now();
    _dueDate = loan?.dueDate != null ? DateTime.tryParse(loan!.dueDate!) : null;
    _currency = loan?.currency ?? 'PKR';
  }

  @override
  void dispose() {
    _amountController.dispose();
    _purposeController.dispose();
    _notesController.dispose();
    _newBorrowerNameController.dispose();
    _newBorrowerPhoneController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _buildBody() {
    final amount = num.tryParse(_amountController.text.trim()) ?? 0;
    return {
      'borrower_name': _selectedBorrower?.name ??
          _newBorrowerNameController.text.trim(),
      'borrower_id': _selectedBorrower?.id,
      'borrower_type': _selectedBorrower?.linkedType,
      'amount': amount,
      'currency': _currency,
      'loan_date': isoDate(_loanDate),
      if (_dueDate != null) 'due_date': isoDate(_dueDate!),
      if (_purposeController.text.trim().isNotEmpty)
        'purpose': _purposeController.text.trim(),
      if (_notesController.text.trim().isNotEmpty)
        'notes': _notesController.text.trim(),
    };
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // Validate borrower
    if (_selectedBorrower == null && !_showAddBorrower) {
      setState(() => _error = l10n.equityPersonalLoanBorrowerRequired);
      return;
    }
    if (_showAddBorrower && _newBorrowerNameController.text.trim().isEmpty) {
      setState(() => _error = l10n.equityPersonalLoanBorrowerRequired);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final repo = ref.read(personalLoanRepositoryProvider);

    // If adding new borrower inline, create it first
    if (_showAddBorrower && _selectedBorrower == null) {
      final borrowerResult = await repo.createBorrower({
        'name': _newBorrowerNameController.text.trim(),
        if (_newBorrowerPhoneController.text.trim().isNotEmpty)
          'phone': _newBorrowerPhoneController.text.trim(),
        'linked_type': _newBorrowerLinkTo?.linkedType,
        'linked_id': _newBorrowerLinkTo?.id,
      });
      switch (borrowerResult) {
        case ApiSuccess(:final data):
          _selectedBorrower = data;
        case ApiFailure(:final error):
          setState(() {
            _submitting = false;
            _error = error.message;
          });
          return;
      }
    }

    // Create or update loan
    final result = _isEditing
        ? await repo.updateLoan(widget.loan!.id, _buildBody())
        : await repo.createLoan(_buildBody());
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        Navigator.of(context).pop(true);
        showAppToast(
          context,
          _isEditing
              ? l10n.equityPersonalLoanUpdated
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
      dialogId: 'personal_loan_create',
      maxWidth: 460,
      maxHeight: 700,
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
                    ? l10n.equityPersonalLoanEdit
                    : l10n.equityPersonalLoanNew,
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
                    // Borrower
                    _buildBorrowerSection(l10n),
                    const SizedBox(height: 10),
                    // Amount + Currency
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: FormFieldShell(
                            label: l10n.equityPersonalLoanAmount,
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
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FormFieldShell(
                            label: l10n.equityPersonalLoanCurrency,
                            child: DropdownButtonFormField<String>(
                              initialValue: _currency,
                              isDense: true,
                              decoration: _decoration(),
                              items: const [
                                DropdownMenuItem(value: 'PKR', child: Text('PKR')),
                                DropdownMenuItem(value: 'USD', child: Text('USD')),
                                DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                                DropdownMenuItem(value: 'GBP', child: Text('GBP')),
                              ],
                              onChanged: (v) =>
                                  setState(() => _currency = v ?? 'PKR'),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Loan Date + Due Date
                    Row(
                      children: [
                        Expanded(
                          child: FormFieldShell(
                            label: l10n.equityPersonalLoanDateGiven,
                            required: true,
                            child: SizedBox(
                              height: 44,
                              child: OutlinedButton.icon(
                                onPressed:
                                    _submitting ? null : _pickLoanDate,
                                icon: const Icon(Icons.calendar_today_outlined,
                                    size: 16),
                                label: Text(Formatters.date(isoDate(_loanDate))),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FormFieldShell(
                            label: l10n.equityPersonalLoanDueDate,
                            child: SizedBox(
                              height: 44,
                              child: OutlinedButton.icon(
                                onPressed: _submitting ? null : _pickDueDate,
                                icon: const Icon(Icons.calendar_today_outlined,
                                    size: 16),
                                label: Text(
                                  _dueDate != null
                                      ? Formatters.date(isoDate(_dueDate!))
                                      : l10n.equityPersonalLoanDueDate,
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
                      label: l10n.equityPersonalLoanPurpose,
                      child: TextFormField(
                        controller: _purposeController,
                        enabled: !_submitting,
                        decoration: _decoration(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Notes
                    FormFieldShell(
                      label: l10n.equityPersonalLoanNotes,
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
                            : Icon(_isEditing ? Icons.save : Icons.add,
                                size: 16),
                        label: Text(
                            _isEditing ? l10n.commonSave : l10n.equityPersonalLoanNew),
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

  // ── Borrower Section ────────────────────────────────────────

  Widget _buildBorrowerSection(AppLocalizations l10n) {
    final borrowersAsync = ref.watch(borrowersProvider);
    final borrowers = borrowersAsync.valueOrNull ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormFieldShell(
          label: l10n.equityPersonalLoanBorrower,
          required: true,
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _selectedBorrower?.id,
                  isDense: true,
                  decoration: _decoration().copyWith(
                    hintText: l10n.equityPersonalLoanBorrower,
                  ),
                  items: [
                    for (final b in borrowers)
                      DropdownMenuItem(
                        value: b.id,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                b.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (b.badge != null) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primaryContainer
                                      .withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  b.badge!,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(fontSize: 9),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                  onChanged: (id) {
                    final borrower = borrowers.firstWhere((b) => b.id == id);
                    setState(() {
                      _selectedBorrower = borrower;
                      _showAddBorrower = false;
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                  _showAddBorrower ? Icons.close : Icons.add_circle_outline,
                  size: 20,
                ),
                tooltip: l10n.equityPersonalLoanAddBorrower,
                onPressed: () => setState(() {
                  _showAddBorrower = !_showAddBorrower;
                  if (_showAddBorrower) _selectedBorrower = null;
                }),
              ),
            ],
          ),
        ),
        if (_showAddBorrower) ...[
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.equityPersonalLoanAddBorrower,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _newBorrowerNameController,
                    enabled: !_submitting,
                    decoration: _decoration().copyWith(
                      hintText: l10n.equityPersonalLoanBorrowerName,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _newBorrowerPhoneController,
                    enabled: !_submitting,
                    decoration: _decoration().copyWith(
                      hintText: l10n.equityPersonalLoanBorrowerPhone,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    isDense: true,
                    decoration: _decoration().copyWith(
                      hintText: l10n.equityPersonalLoanBorrowerLinkTo,
                    ),
                    items: [
                      for (final b in borrowers)
                        if (b.linkedType != null)
                          DropdownMenuItem(
                            value: b.id,
                            child: Text(
                              '${b.name} [${b.badge}]',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                    ],
                    onChanged: (id) {
                      final borrower = borrowers.firstWhere((b) => b.id == id);
                      setState(() => _newBorrowerLinkTo = borrower);
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ── Date Pickers ────────────────────────────────────────────

  Future<void> _pickLoanDate() async {
    final picked = await pickDate(context, initialDate: _loanDate);
    if (picked == null || !mounted) return;
    setState(() => _loanDate = picked);
  }

  Future<void> _pickDueDate() async {
    final picked = await pickDate(
      context,
      initialDate: _dueDate ?? _loanDate.add(const Duration(days: 90)),
    );
    if (picked == null || !mounted) return;
    setState(() => _dueDate = picked);
  }

  InputDecoration _decoration() => InputDecoration(
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: AppBorderRadius.smRadius),
      );
}
