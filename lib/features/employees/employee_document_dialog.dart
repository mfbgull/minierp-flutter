// Employee document upload dialog — `POST /employees/:id/documents` as a
// multipart FormData (the route's `uploadEmployeeDoc.single('file')`
// middleware). Metadata fields (name/type/number/issue/expiry/notes) plus
// the picked file travel as the `file` part; the server stores the file
// under uploads/employees and records its filename in file_path. The file
// picker mirrors the server's allowed MIME list and 10MB limit.

import 'package:file_picker/file_picker.dart';
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
import 'employee_providers.dart';
import 'employee_repository.dart' show employeeRepositoryProvider;
import '../../widgets/movable_dialog.dart';
import 'package:minierp_app/core/theme/app_border_radius.dart';

/// Extensions the server's upload filter accepts (`documentFilter` in
/// `server/src/middleware/upload.ts`).
const List<String> kDocumentExtensions = [
  'pdf',
  'jpg',
  'jpeg',
  'png',
  'gif',
  'doc',
  'docx',
  'xls',
  'xlsx',
  'txt',
];

/// Server upload cap — `limits.fileSize` in the same middleware.
const int kDocumentMaxBytes = 10 * 1024 * 1024;

/// Opens the document upload modal for one employee.
Future<void> showEmployeeDocumentDialog(
  BuildContext context, {
  required int employeeId,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) =>
        EmployeeDocumentDialog(employeeId: employeeId),
  );
}

class EmployeeDocumentDialog extends ConsumerStatefulWidget {
  const EmployeeDocumentDialog({super.key, required this.employeeId});

  final int employeeId;

  @override
  ConsumerState<EmployeeDocumentDialog> createState() =>
      _EmployeeDocumentDialogState();
}

class _EmployeeDocumentDialogState
    extends ConsumerState<EmployeeDocumentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _typeController = TextEditingController();
  final _numberController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime? _issueDate;
  DateTime? _expiryDate;

  /// The picked file — null until the user selects one.
  PlatformFile? _file;

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _typeController.dispose();
    _numberController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: kDocumentExtensions,
      withData: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final picked = result.files.single;
    if (picked.size > kDocumentMaxBytes) {
      // Drop any previously-selected file so the dialog can't silently
      // upload it while showing the size error.
      setState(() {
        _file = null;
        _error = AppLocalizations.of(context)!
            .employeesDocumentsFiletoolarge;
      });
      return;
    }
    setState(() {
      _file = picked;
      _error = null;
    });
  }

  Future<void> _pickDate({required bool isIssue}) async {
    final picked = await pickDate(
      context,
      initialDate: isIssue ? (_issueDate ?? DateTime.now()) : (_expiryDate ?? DateTime.now()),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isIssue) {
        _issueDate = picked;
      } else {
        _expiryDate = picked;
      }
    });
  }

  String? _validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return AppLocalizations.of(context)!.employeesDocumentsNamerequired;
    }
    return null;
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
        .addDocument(
          widget.employeeId,
          documentName: _nameController.text.trim(),
          documentType: _typeController.text.trim().isEmpty
              ? null
              : _typeController.text.trim(),
          documentNumber: _numberController.text.trim().isEmpty
              ? null
              : _numberController.text.trim(),
          issueDate: _issueDate == null ? null : isoDate(_issueDate!),
          expiryDate: _expiryDate == null ? null : isoDate(_expiryDate!),
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
          fileBytes: _file?.bytes,
          filePath: _file?.path,
          fileName: _file?.name,
        );
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        ref.invalidate(employeeDocumentsProvider(widget.employeeId));
        Navigator.of(context).pop();
        showAppToast(context, l10n.employeesDocumentsCreated);
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
    final scheme = Theme.of(context).colorScheme;

    return MovableDialog(
      dialogId: 'employee_document',
      maxWidth: 480,
      // The form (4 text rows + dates + notes + file row) is ~680px tall;
      // MovableDialog's 480 default clips it so the footer overlaps the
      // file row. Match the other form dialogs (supplier_form etc.).
      maxHeight: 680,
      child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  l10n.employeesDocumentsAdd,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const Divider(height: 1),
              Flexible(
                // primary: false so this view owns its scroll position
                // instead of attaching to the app-wide PrimaryScrollController
                // (shared with the screen/detail dialog behind it) — that
                // sharing made ensureVisible/scrolls act on the wrong list.
                child: SingleChildScrollView(
                  primary: false,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FormFieldShell(
                        label: l10n.employeesDocumentsName,
                        required: true,
                        child: TextFormField(
                          controller: _nameController,
                          autofocus: true,
                          onFieldSubmitted: submitOnEnter(_submit),
                          enabled: !_submitting,
                          decoration: _decoration(),
                          validator: _validateName,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.employeesDocumentsType,
                              child: TextFormField(
                                controller: _typeController,
                                onFieldSubmitted: submitOnEnter(_submit),
                                enabled: !_submitting,
                                decoration: _decoration(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.employeesDocumentsNumber,
                              child: TextFormField(
                                controller: _numberController,
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
                            child: _dateField(
                              label: l10n.employeesDocumentsIssuedate,
                              value: _issueDate,
                              onTap: () => _pickDate(isIssue: true),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _dateField(
                              label: l10n.employeesDocumentsExpirydate,
                              value: _expiryDate,
                              onTap: () => _pickDate(isIssue: false),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      FormFieldShell(
                        label: l10n.employeesDocumentsNotes,
                        child: TextFormField(
                          controller: _notesController,
                          enabled: !_submitting,
                          minLines: 2,
                          maxLines: 3,
                          decoration: _decoration(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // File picker — mirrors the server's allowed types.
                      OutlinedButton.icon(
                        onPressed: _submitting ? null : _pickFile,
                        icon: const Icon(Icons.attach_file, size: 18),
                        label: Text(
                          _file == null
                              ? l10n.employeesDocumentsSelectfile
                              : _file!.name,
                        ),
                      ),
                      if (_file != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          Formatters.bytes(_file!.size),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        l10n.employeesDocumentsFiletypes,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
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
                          color: scheme.errorContainer,
                          borderRadius: AppBorderRadius.smRadius,
                        ),
                        child: Text(
                          _error!,
                          style: TextStyle(color: scheme.onErrorContainer),
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
                              : const Icon(Icons.upload_file, size: 16),
                          label: Text(l10n.commonSave),
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

  Widget _dateField({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
  }) {
    return FormFieldShell(
      label: label,
      child: SizedBox(
        height: 44,
        child: OutlinedButton.icon(
          onPressed: _submitting ? null : onTap,
          icon: const Icon(Icons.calendar_today_outlined, size: 16),
          label: Text(
            value == null ? '—' : Formatters.date(isoDate(value)),
          ),
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
