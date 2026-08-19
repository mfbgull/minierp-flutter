// Role create/edit form — modal dialog over POST/PUT /roles.
//
// Field set mirrors the server's createRole/updateRole DTOs: role_name is
// required (400 otherwise); description and is_active are optional. System
// roles can't be edited (the server guards it) — the form opens read-only
// for them. New roles are created active with no permissions (assign them
// in the permissions dialog).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/form_field.dart';
import '../../widgets/form_helpers.dart';
import 'admin_models.dart';
import 'admin_providers.dart';
import 'admin_repository.dart' show adminRepositoryProvider;
import 'package:minierp_app/core/theme/app_border_radius.dart';

/// Opens the create ([role] == null) or edit form dialog.
Future<void> showRoleFormDialog(BuildContext context, {Role? role}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => RoleFormDialog(role: role),
  );
}

class RoleFormDialog extends ConsumerStatefulWidget {
  const RoleFormDialog({super.key, this.role});

  /// Null → create; otherwise pre-fills and PUTs to `roles/:id`.
  final Role? role;

  @override
  ConsumerState<RoleFormDialog> createState() => _RoleFormDialogState();
}

class _RoleFormDialogState extends ConsumerState<RoleFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;

  bool _isActive = true;
  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.role != null;

  /// System roles are read-only (the server refuses to modify them).
  bool get _locked => widget.role?.isSystemRole ?? false;

  @override
  void initState() {
    super.initState();
    final role = widget.role;
    _nameController = TextEditingController(text: role?.roleName ?? '');
    _descriptionController = TextEditingController(text: role?.description ?? '');
    _isActive = role?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  String? _validateName(String? value) {
    final l10n = AppLocalizations.of(context)!;
    if (value == null || value.trim().isEmpty) {
      return l10n.usermanagementRolevalidationname;
    }
    return null;
  }

  Map<String, dynamic> _buildBody() {
    final description = _descriptionController.text.trim();
    return {
      'role_name': _nameController.text.trim(),
      if (description.isNotEmpty) 'description': description,
      'is_active': _isActive,
    };
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_locked) {
      showAppToast(context, l10n.usermanagementCantmodifysystem, isError: true);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final repo = ref.read(adminRepositoryProvider);
    final result = _isEdit
        ? await repo.updateRole(widget.role!.id, _buildBody())
        : await repo.createRole(_buildBody());
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        ref.invalidate(rolesProvider);
        Navigator.of(context).pop();
        showAppToast(
          context,
          _isEdit ? l10n.usermanagementRoleupdated : l10n.usermanagementRolecreated,
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
    final locked = _locked;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
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
                            ? l10n.usermanagementEditrole
                            : l10n.usermanagementNewrole,
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
                      FormFieldShell(
                        label: l10n.usermanagementRolename,
                        required: true,
                        child: TextFormField(
                          controller: _nameController,
                          onFieldSubmitted: submitOnEnter(_submit),
                          autofocus: true,
                          enabled: !_submitting && !locked,
                          decoration: _decoration(),
                          validator: _validateName,
                        ),
                      ),
                      const SizedBox(height: 10),
                      FormFieldShell(
                        label: l10n.usermanagementDescription,
                        child: TextFormField(
                          controller: _descriptionController,
                          enabled: !_submitting && !locked,
                          minLines: 2,
                          maxLines: 4,
                          decoration: _decoration(),
                        ),
                      ),
                      const SizedBox(height: 6),
                      CheckboxListTile(
                        value: _isActive,
                        onChanged: _submitting || locked
                            ? null
                            : (v) => setState(() => _isActive = v ?? true),
                        title: Text(l10n.statusActive),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      if (locked)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            l10n.usermanagementCantmodifysystem,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
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
                        FilledButton(
                          onPressed: locked ? null : (_submitting ? null : _submit),
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

  InputDecoration _decoration() => InputDecoration(
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(borderRadius: AppBorderRadius.smRadius),
  );
}
