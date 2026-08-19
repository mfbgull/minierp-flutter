// Expense category manager — a dialog over the server's category CRUD
// (`POST/DELETE /expenses/categories`; both endpoints already exist).
// Opened from the expense form's category field: the top half is the
// add form, the bottom half lists the existing categories with a
// per-row delete (destructive confirm; the server refuses to delete a
// category still used by expenses and the 400 message is surfaced).
//
// The dialog stays open after add/delete so several categories can be
// managed in one go; closing it returns the last created name so the
// expense form can pre-select it (null when nothing was created).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/expense.dart' show ExpenseCategory;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/expense_repository.dart'
    show expenseRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/form_field.dart';
import '../../widgets/form_helpers.dart';
import 'expense_providers.dart';

/// Opens the category manager. Returns the last created category name
/// (so the caller can pre-select it), or null when nothing was created.
Future<String?> showExpenseCategoryDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => const ExpenseCategoryDialog(),
  );
}

class ExpenseCategoryDialog extends ConsumerStatefulWidget {
  const ExpenseCategoryDialog({super.key});

  @override
  ConsumerState<ExpenseCategoryDialog> createState() =>
      _ExpenseCategoryDialogState();
}

class _ExpenseCategoryDialogState extends ConsumerState<ExpenseCategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  bool _submitting = false;
  String? _error;

  /// Id of the category whose DELETE is in flight (spinner on that row,
  /// other deletes disabled meanwhile).
  int? _deletingId;

  /// Last created name — returned to the caller when the dialog closes
  /// so the expense form can select it.
  String? _lastCreated;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  bool get _busy => _submitting || _deletingId != null;

  /// Every exit path returns [_lastCreated] to the caller.
  void _close() => Navigator.of(context).pop(_lastCreated);

  String? _validateName(String? value) {
    final l10n = AppLocalizations.of(context)!;
    if (value == null || value.trim().isEmpty) {
      return l10n.expensesErrorCategorynameRequired;
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

    final name = _nameController.text.trim();
    final description = _descriptionController.text.trim();
    final result = await ref
        .read(expenseRepositoryProvider)
        .createCategory(
          categoryName: name,
          description: description.isEmpty ? null : description,
        );
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        // The form's category dropdown and the screen's filter both
        // watch this provider — one invalidate refreshes both (and the
        // list below). Stay open so more categories can be managed.
        ref.invalidate(expenseCategoriesProvider);
        _nameController.clear();
        _descriptionController.clear();
        _lastCreated = name;
        setState(() => _submitting = false);
        showAppToast(context, l10n.expensesCategorycreated);
      case ApiFailure(:final error):
        setState(() {
          _submitting = false;
          _error = error.message;
        });
    }
  }

  Future<void> _delete(ExpenseCategory category) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.commonDelete,
      message: l10n.expensesDeletecategoryconfirm(category.categoryName),
      confirmLabel: l10n.commonDelete,
      cancelLabel: l10n.commonCancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _deletingId = category.id);
    final result = await ref
        .read(expenseRepositoryProvider)
        .deleteCategory(category.id);
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        ref.invalidate(expenseCategoriesProvider);
        setState(() => _deletingId = null);
        showAppToast(context, l10n.expensesCategorydeleted);
      case ApiFailure(:final error):
        // The server's 400 explains the block ("...being used by
        // existing expenses") — surface it as an error toast.
        setState(() => _deletingId = null);
        showAppToast(context, error.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final categories = ref.watch(expenseCategoriesProvider);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 640),
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
                      l10n.expensesCategories,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.commonClose,
                    icon: const Icon(Icons.close),
                    onPressed: _busy ? null : _close,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Add form.
            Form(
              key: _formKey,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FormFieldShell(
                      label: l10n.expensesCategoryname,
                      required: true,
                      child: TextFormField(
                        controller: _nameController,
                        autofocus: true,
                        enabled: !_submitting,
                        textInputAction: TextInputAction.next,
                        decoration: formInputDecoration(),
                        validator: _validateName,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: FormFieldShell(
                            label: l10n.fieldsDescription,
                            child: TextFormField(
                              controller: _descriptionController,
                              enabled: !_submitting,
                              onFieldSubmitted: (_) => _submit(),
                              decoration: formInputDecoration(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Aligned with the description field's underline.
                        Padding(
                          padding: const EdgeInsets.only(top: 24),
                          child: FilledButton.tonalIcon(
                            onPressed: _busy ? null : _submit,
                            icon: _submitting
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.add, size: 18),
                            label: Text(l10n.commonAdd),
                          ),
                        ),
                      ],
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      ErrorBanner(message: _error!),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            // Existing categories with per-row delete.
            Flexible(
              child: switch (categories) {
                AsyncData(:final value) => value.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(20),
                        child: Center(child: Text(l10n.commonNoresults)),
                      )
                    : ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        children: [
                          for (final category in value)
                            _categoryRow(category),
                        ],
                      ),
                AsyncError() => Padding(
                  padding: const EdgeInsets.all(20),
                  child: Center(child: Text(l10n.commonNoresults)),
                ),
                _ => const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              },
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _busy ? null : _close,
                    child: Text(l10n.commonClose),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryRow(ExpenseCategory category) {
    final deleting = _deletingId == category.id;
    final description = category.description ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.categoryName,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (description.isNotEmpty)
                    Text(
                      description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: AppLocalizations.of(context)!.commonDelete,
            onPressed: _busy ? null : () => _delete(category),
            icon: deleting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: Theme.of(context).colorScheme.error,
                  ),
          ),
        ],
      ),
    );
  }
}
