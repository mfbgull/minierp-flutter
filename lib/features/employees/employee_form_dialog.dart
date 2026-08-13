// Employee create/edit form — modal dialog over POST/PUT /employees.
//
// Field set mirrors the server's createEmployee/updateEmployee DTOs: only
// first_name and last_name are required (422 otherwise); everything else
// is optional. The create form shows the server-generated employee code
// (`GET /employees/next-code`) read-only; the edit form keeps the stored
// code. Employment type / gender use the server's default option sets.
//
// Delete lives in the list screen's row menu (the edit form keeps the
// expense-form convention of offering it too).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart' show isoDate;
import '../../core/utils/formatters.dart';
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/date_picker.dart' show pickDate;
import '../../widgets/form_field.dart';
import '../../widgets/form_helpers.dart';
import '../../widgets/searchable_select.dart';
import 'employee_models.dart';
import 'employee_providers.dart';
import 'employee_repository.dart' show employeeRepositoryProvider;

/// Opens the create ([employee] == null) or edit form dialog.
Future<void> showEmployeeFormDialog(
  BuildContext context, {
  Employee? employee,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => EmployeeFormDialog(employee: employee),
  );
}

/// Employment types offered by the reference dropdown (the server defaults
/// to `Full-time`).
const List<String> kEmploymentTypes = [
  'Full-time',
  'Part-time',
  'Contract',
  'Intern',
];

/// Gender options offered by the reference dropdown.
const List<String> kGenderOptions = ['Male', 'Female', 'Other'];

class EmployeeFormDialog extends ConsumerStatefulWidget {
  const EmployeeFormDialog({super.key, this.employee});

  /// Null → create; otherwise pre-fills and PUTs to `employees/:id`.
  final Employee? employee;

  @override
  ConsumerState<EmployeeFormDialog> createState() => _EmployeeFormDialogState();
}

class _EmployeeFormDialogState extends ConsumerState<EmployeeFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _mobileController;
  late final TextEditingController _cnicController;
  late final TextEditingController _departmentController;
  late final TextEditingController _designationController;
  late final TextEditingController _salaryController;
  late final TextEditingController _cityController;
  late final TextEditingController _stateController;
  late final TextEditingController _postalCodeController;
  late final TextEditingController _countryController;
  late final TextEditingController _addressController;
  late final TextEditingController _bankNameController;
  late final TextEditingController _bankAccountController;
  late final TextEditingController _ibanController;
  late final TextEditingController _emergencyNameController;
  late final TextEditingController _emergencyPhoneController;
  late final TextEditingController _notesController;

  String? _employmentType;
  String? _gender;
  late DateTime _dateOfJoining;
  DateTime? _dateOfLeaving;
  late DateTime _dateOfBirth;
  bool _isActive = true;

  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.employee != null;

  @override
  void initState() {
    super.initState();
    final e = widget.employee;
    String text(String? value) => value ?? '';
    _firstNameController = TextEditingController(text: text(e?.firstName));
    _lastNameController = TextEditingController(text: text(e?.lastName));
    _emailController = TextEditingController(text: text(e?.email));
    _phoneController = TextEditingController(text: text(e?.phone));
    _mobileController = TextEditingController(text: text(e?.mobile));
    _cnicController = TextEditingController(text: text(e?.cnicNo));
    _departmentController = TextEditingController(text: text(e?.department));
    _designationController = TextEditingController(text: text(e?.designation));
    _salaryController = TextEditingController(
      text: e == null ? '' : _numText(e.salary),
    );
    _cityController = TextEditingController(text: text(e?.city));
    _stateController = TextEditingController(text: text(e?.state));
    _postalCodeController = TextEditingController(text: text(e?.postalCode));
    _countryController = TextEditingController(
      text: text(e?.country ?? 'Pakistan'),
    );
    _addressController = TextEditingController(text: text(e?.address));
    _bankNameController = TextEditingController(text: text(e?.bankName));
    _bankAccountController = TextEditingController(text: text(e?.bankAccountNo));
    _ibanController = TextEditingController(text: text(e?.bankIban));
    _emergencyNameController = TextEditingController(
      text: text(e?.emergencyContactName),
    );
    _emergencyPhoneController = TextEditingController(
      text: text(e?.emergencyContactPhone),
    );
    _notesController = TextEditingController(text: text(e?.notes));
    _employmentType = e?.employmentType;
    _gender = e?.gender;
    _dateOfJoining = DateTime.tryParse(e?.dateOfJoining ?? '') ?? DateTime.now();
    _dateOfLeaving = DateTime.tryParse(e?.dateOfLeaving ?? '');
    _dateOfBirth = DateTime.tryParse(e?.dateOfBirth ?? '') ?? DateTime.now();
    _isActive = e?.isActive ?? true;
  }

  @override
  void dispose() {
    for (final controller in [
      _firstNameController,
      _lastNameController,
      _emailController,
      _phoneController,
      _mobileController,
      _cnicController,
      _departmentController,
      _designationController,
      _salaryController,
      _cityController,
      _stateController,
      _postalCodeController,
      _countryController,
      _addressController,
      _bankNameController,
      _bankAccountController,
      _ibanController,
      _emergencyNameController,
      _emergencyPhoneController,
      _notesController,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  static String _numText(num value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();

  Future<void> _pickJoiningDate() async {
    final picked = await pickDate(context, initialDate: _dateOfJoining);
    if (picked == null || !mounted) return;
    setState(() => _dateOfJoining = picked);
  }

  Future<void> _pickLeavingDate() async {
    final picked = await pickDate(
      context,
      initialDate: _dateOfLeaving ?? DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() => _dateOfLeaving = picked);
  }

  Future<void> _pickBirthDate() async {
    final picked = await pickDate(context, initialDate: _dateOfBirth);
    if (picked == null || !mounted) return;
    setState(() => _dateOfBirth = picked);
  }

  String? _validateName(String? value) {
    final l10n = AppLocalizations.of(context)!;
    if (value == null || value.trim().isEmpty) {
      return l10n.employeesValidationFirstnamerequired;
    }
    return null;
  }

  String? _validateLastName(String? value) {
    final l10n = AppLocalizations.of(context)!;
    if (value == null || value.trim().isEmpty) {
      return l10n.employeesValidationLastnamerequired;
    }
    return null;
  }

  String? _validateEmail(String? value) {
    final l10n = AppLocalizations.of(context)!;
    final email = value?.trim() ?? '';
    if (email.isEmpty) return null;
    final valid = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
    return valid ? null : l10n.employeesValidationInvalidemail;
  }

  Map<String, dynamic> _buildBody() {
    String? trimmed(TextEditingController c) {
      final v = c.text.trim();
      return v.isEmpty ? null : v;
    }

    final salary = num.tryParse(_salaryController.text.trim()) ?? 0;
    return {
      'first_name': _firstNameController.text.trim(),
      'last_name': _lastNameController.text.trim(),
      if (trimmed(_emailController) != null) 'email': trimmed(_emailController),
      if (trimmed(_phoneController) != null) 'phone': trimmed(_phoneController),
      if (trimmed(_mobileController) != null)
        'mobile': trimmed(_mobileController),
      if (trimmed(_cnicController) != null) 'cnic_no': trimmed(_cnicController),
      if (trimmed(_departmentController) != null)
        'department': trimmed(_departmentController),
      if (trimmed(_designationController) != null)
        'designation': trimmed(_designationController),
      if (_employmentType != null) 'employment_type': _employmentType,
      'salary': salary,
      if (trimmed(_cityController) != null) 'city': trimmed(_cityController),
      if (trimmed(_stateController) != null) 'state': trimmed(_stateController),
      if (trimmed(_postalCodeController) != null)
        'postal_code': trimmed(_postalCodeController),
      if (trimmed(_countryController) != null)
        'country': trimmed(_countryController),
      if (trimmed(_addressController) != null)
        'address': trimmed(_addressController),
      if (trimmed(_bankNameController) != null)
        'bank_name': trimmed(_bankNameController),
      if (trimmed(_bankAccountController) != null)
        'bank_account_no': trimmed(_bankAccountController),
      if (trimmed(_ibanController) != null) 'bank_iban': trimmed(_ibanController),
      if (trimmed(_emergencyNameController) != null)
        'emergency_contact_name': trimmed(_emergencyNameController),
      if (trimmed(_emergencyPhoneController) != null)
        'emergency_contact_phone': trimmed(_emergencyPhoneController),
      if (trimmed(_notesController) != null) 'notes': trimmed(_notesController),
      'date_of_joining': isoDate(_dateOfJoining),
      if (_dateOfLeaving != null) 'date_of_leaving': isoDate(_dateOfLeaving!),
      if (_gender != null) 'gender': _gender,
      'date_of_birth': isoDate(_dateOfBirth),
      'is_active': _isActive,
    };
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final repo = ref.read(employeeRepositoryProvider);
    final result = _isEdit
        ? await repo.update(widget.employee!.id, _buildBody())
        : await repo.create(_buildBody());
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        ref.invalidate(employeesProvider);
        Navigator.of(context).pop();
        showAppToast(
          context,
          _isEdit ? l10n.employeesMessagesUpdated : l10n.employeesMessagesCreated,
        );
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
      message: l10n.employeesDeleteconfirm,
      confirmLabel: l10n.commonDelete,
      cancelLabel: l10n.commonCancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final result = await ref
        .read(employeeRepositoryProvider)
        .delete(widget.employee!.id);
    if (!mounted) return;
    switch (result) {
      case ApiSuccess():
        ref.invalidate(employeesProvider);
        Navigator.of(context).pop();
        showAppToast(context, l10n.employeesMessagesDeleted);
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
    final nextCode = ref.watch(employeeNextCodeProvider).valueOrNull;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
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
                            ? l10n.employeesEditemployee
                            : l10n.employeesAddnew,
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
                      if (!_isEdit) ...[
                        Row(
                          children: [
                            Expanded(
                              child: FormFieldShell(
                                label: 'Code',
                                child: TextFormField(
                                  // Keyed by the loaded next code so the
                                  // read-only field refreshes when the
                                  // async fetch completes (initialValue
                                  // only applies on first build).
                                  key: ValueKey('employee-code-$nextCode'),
                                  initialValue:
                                      widget.employee?.employeeCode ??
                                      nextCode ??
                                      'EMP-…',
                                  enabled: false,
                                  decoration: _decoration(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ],
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.employeesFieldsFirst_name,
                              required: true,
                              child: TextFormField(
                                controller: _firstNameController,
                                onFieldSubmitted: submitOnEnter(_submit),
                                autofocus: true,
                                enabled: !_submitting,
                                decoration: _decoration(),
                                validator: _validateName,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.employeesFieldsLast_name,
                              required: true,
                              child: TextFormField(
                                controller: _lastNameController,
                                onFieldSubmitted: submitOnEnter(_submit),
                                enabled: !_submitting,
                                decoration: _decoration(),
                                validator: _validateLastName,
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
                              label: l10n.employeesFieldsEmail,
                              child: TextFormField(
                                controller: _emailController,
                                onFieldSubmitted: submitOnEnter(_submit),
                                enabled: !_submitting,
                                decoration: _decoration(),
                                validator: _validateEmail,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.employeesFieldsPhone,
                              child: TextFormField(
                                controller: _phoneController,
                                onFieldSubmitted: submitOnEnter(_submit),
                                enabled: !_submitting,
                                decoration: _decoration(),
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
                              label: l10n.employeesFieldsMobile,
                              child: TextFormField(
                                controller: _mobileController,
                                onFieldSubmitted: submitOnEnter(_submit),
                                enabled: !_submitting,
                                decoration: _decoration(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.employeesFieldsCnic_no,
                              child: TextFormField(
                                controller: _cnicController,
                                onFieldSubmitted: submitOnEnter(_submit),
                                enabled: !_submitting,
                                decoration: _decoration(),
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
                              label: l10n.employeesFieldsDepartment,
                              child: TextFormField(
                                controller: _departmentController,
                                onFieldSubmitted: submitOnEnter(_submit),
                                enabled: !_submitting,
                                decoration: _decoration(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.employeesFieldsDesignation,
                              child: TextFormField(
                                controller: _designationController,
                                onFieldSubmitted: submitOnEnter(_submit),
                                enabled: !_submitting,
                                decoration: _decoration(),
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
                              label: l10n.employeesEmploymenttype,
                              child: SearchableSelect<String>(
                                items: _withCurrent(
                                  kEmploymentTypes,
                                  _employmentType,
                                ),
                                selected: _employmentType,
                                labelBuilder: (v) => v,
                                onChanged: (v) =>
                                    setState(() => _employmentType = v),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.employeesFieldsSalary,
                              child: TextFormField(
                                controller: _salaryController,
                                onFieldSubmitted: submitOnEnter(_submit),
                                enabled: !_submitting,
                                keyboardType: const TextInputType
                                    .numberWithOptions(decimal: true),
                                decoration: _decoration(),
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
                              label: l10n.employeesFieldsDate_of_joining,
                              child: SizedBox(
                                height: 44,
                                child: OutlinedButton.icon(
                                  onPressed: _submitting ? null : _pickJoiningDate,
                                  icon: const Icon(
                                    Icons.calendar_today_outlined,
                                    size: 16,
                                  ),
                                  label: Text(
                                    Formatters.date(isoDate(_dateOfJoining)),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.employeesFieldsDate_of_leaving,
                              child: SizedBox(
                                height: 44,
                                child: OutlinedButton.icon(
                                  onPressed: _submitting ? null : _pickLeavingDate,
                                  icon: const Icon(
                                    Icons.calendar_today_outlined,
                                    size: 16,
                                  ),
                                  label: Text(
                                    _dateOfLeaving == null
                                        ? l10n.commonNone
                                        : Formatters.date(
                                            isoDate(_dateOfLeaving!),
                                          ),
                                  ),
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
                              label: l10n.employeesFieldsGender,
                              child: SearchableSelect<String>(
                                items: _withCurrent(kGenderOptions, _gender),
                                selected: _gender,
                                labelBuilder: (v) => v,
                                onChanged: (v) =>
                                    setState(() => _gender = v),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.employeesFieldsDate_of_birth,
                              child: SizedBox(
                                height: 44,
                                child: OutlinedButton.icon(
                                  onPressed: _submitting ? null : _pickBirthDate,
                                  icon: const Icon(
                                    Icons.calendar_today_outlined,
                                    size: 16,
                                  ),
                                  label: Text(
                                    Formatters.date(isoDate(_dateOfBirth)),
                                  ),
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
                              label: l10n.employeesFieldsCity,
                              child: TextFormField(
                                controller: _cityController,
                                onFieldSubmitted: submitOnEnter(_submit),
                                enabled: !_submitting,
                                decoration: _decoration(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.employeesFieldsState,
                              child: TextFormField(
                                controller: _stateController,
                                onFieldSubmitted: submitOnEnter(_submit),
                                enabled: !_submitting,
                                decoration: _decoration(),
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
                              label: l10n.employeesFieldsPostal_code,
                              child: TextFormField(
                                controller: _postalCodeController,
                                onFieldSubmitted: submitOnEnter(_submit),
                                enabled: !_submitting,
                                decoration: _decoration(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.employeesFieldsCountry,
                              child: TextFormField(
                                controller: _countryController,
                                onFieldSubmitted: submitOnEnter(_submit),
                                enabled: !_submitting,
                                decoration: _decoration(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      FormFieldShell(
                        label: l10n.employeesFieldsAddress,
                        child: TextFormField(
                          controller: _addressController,
                          enabled: !_submitting,
                          minLines: 2,
                          maxLines: 3,
                          decoration: _decoration(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.employeesFieldsBank_name,
                              child: TextFormField(
                                controller: _bankNameController,
                                onFieldSubmitted: submitOnEnter(_submit),
                                enabled: !_submitting,
                                decoration: _decoration(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.employeesFieldsBank_account_no,
                              child: TextFormField(
                                controller: _bankAccountController,
                                onFieldSubmitted: submitOnEnter(_submit),
                                enabled: !_submitting,
                                decoration: _decoration(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      FormFieldShell(
                        label: l10n.employeesFieldsBank_iban,
                        child: TextFormField(
                          controller: _ibanController,
                          onFieldSubmitted: submitOnEnter(_submit),
                          enabled: !_submitting,
                          decoration: _decoration(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.employeesFieldsEmergency_contact_name,
                              child: TextFormField(
                                controller: _emergencyNameController,
                                onFieldSubmitted: submitOnEnter(_submit),
                                enabled: !_submitting,
                                decoration: _decoration(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.employeesFieldsEmergency_contact_phone,
                              child: TextFormField(
                                controller: _emergencyPhoneController,
                                onFieldSubmitted: submitOnEnter(_submit),
                                enabled: !_submitting,
                                decoration: _decoration(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      FormFieldShell(
                        label: l10n.employeesFieldsNotes,
                        child: TextFormField(
                          controller: _notesController,
                          enabled: !_submitting,
                          minLines: 2,
                          maxLines: 3,
                          decoration: _decoration(),
                        ),
                      ),
                      const SizedBox(height: 6),
                      CheckboxListTile(
                        value: _isActive,
                        onChanged: _submitting
                            ? null
                            : (v) => setState(() => _isActive = v ?? true),
                        title: Text(l10n.employeesFieldsIs_active),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
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
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.error,
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

  List<T> _withCurrent<T>(List<T> loaded, T? current) {
    if (current == null || loaded.contains(current)) return loaded;
    return [...loaded, current];
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
