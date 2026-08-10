// User create/edit form — modal dialog over POST/PUT /users.
//
// Field set mirrors the server's createUser/updateUser DTOs: username,
// email, full_name and role are required; create mode additionally
// requires password (min 6 chars, the server's rule). The role dropdown
// loads from `GET /roles` and always includes the current value so an
// edit form never loses a role the loaded list doesn't contain. The
// server rejects changing your own role away from Admin — that error
// surfaces in the banner.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/form_field.dart';
import '../../widgets/searchable_select.dart';
import 'admin_models.dart';
import 'admin_providers.dart';
import 'admin_repository.dart' show adminRepositoryProvider;

/// Opens the create ([user] == null) or edit form dialog.
Future<void> showUserFormDialog(BuildContext context, {User? user}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => UserFormDialog(user: user),
  );
}

class UserFormDialog extends ConsumerStatefulWidget {
  const UserFormDialog({super.key, this.user});

  /// Null → create; otherwise pre-fills and PUTs to `users/:id`.
  final User? user;

  @override
  ConsumerState<UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends ConsumerState<UserFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _usernameController;
  late final TextEditingController _emailController;
  late final TextEditingController _fullNameController;
  late final TextEditingController _passwordController;

  int? _roleId;
  bool _isActive = true;
  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.user != null;

  @override
  void initState() {
    super.initState();
    final user = widget.user;
    _usernameController = TextEditingController(text: user?.username ?? '');
    _emailController = TextEditingController(text: user?.email ?? '');
    _fullNameController = TextEditingController(text: user?.fullName ?? '');
    _passwordController = TextEditingController();
    _roleId = user?.roleId;
    _isActive = user?.isActive ?? true;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _fullNameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validateRequired(String? value) {
    if (value == null || value.trim().isEmpty) {
      return AppLocalizations.of(context)!.messagesRequired;
    }
    return null;
  }

  String? _validateEmail(String? value) {
    final l10n = AppLocalizations.of(context)!;
    final email = value?.trim() ?? '';
    if (email.isEmpty) return l10n.usermanagementValidationEmailrequired;
    final valid = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
    return valid ? null : l10n.usermanagementValidationInvalidemail;
  }

  String? _validatePassword(String? value) {
    final l10n = AppLocalizations.of(context)!;
    if (!_isEdit) {
      if (value == null || value.isEmpty) {
        return l10n.usermanagementValidationPasswordlength;
      }
    }
    if (value != null && value.isNotEmpty && value.length < 6) {
      return l10n.usermanagementValidationPasswordlength;
    }
    return null;
  }

  Map<String, dynamic> _buildBody() {
    return {
      'username': _usernameController.text.trim(),
      'email': _emailController.text.trim(),
      'full_name': _fullNameController.text.trim(),
      'role_id': _roleId,
      'is_active': _isActive,
      if (!_isEdit) 'password': _passwordController.text,
    };
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_roleId == null) {
      setState(() => _error = l10n.usermanagementValidationRolerequired);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final repo = ref.read(adminRepositoryProvider);
    final result = _isEdit
        ? await repo.updateUser(widget.user!.id, _buildBody())
        : await repo.createUser(_buildBody());
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        ref.invalidate(usersProvider);
        Navigator.of(context).pop();
        showAppToast(
          context,
          _isEdit ? l10n.usermanagementUserupdated : l10n.usermanagementUsercreated,
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
    final roles = ref.watch(rolesProvider);

    final roleItems = <Role>[
      ...?roles.valueOrNull,
    ];
    // Keep the stored role when the loaded list lags or omits it.
    final currentRole = roleItems.where((r) => r.id == _roleId).firstOrNull;
    final effectiveRoleItems = (currentRole == null && _roleId != null)
        ? [
            ...roleItems,
            Role(
              id: _roleId!,
              roleName: widget.user?.role ?? '?',
              isSystemRole: false,
              isActive: true,
            ),
          ]
        : roleItems;

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
                            ? l10n.usermanagementEdituser
                            : l10n.usermanagementNewuser,
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
                        label: l10n.usermanagementUsername,
                        required: true,
                        child: TextFormField(
                          controller: _usernameController,
                          enabled: !_submitting,
                          decoration: _decoration(),
                          validator: _validateRequired,
                        ),
                      ),
                      const SizedBox(height: 10),
                      FormFieldShell(
                        label: l10n.usermanagementFullname,
                        required: true,
                        child: TextFormField(
                          controller: _fullNameController,
                          enabled: !_submitting,
                          decoration: _decoration(),
                          validator: _validateRequired,
                        ),
                      ),
                      const SizedBox(height: 10),
                      FormFieldShell(
                        label: l10n.usermanagementEmail,
                        required: true,
                        child: TextFormField(
                          controller: _emailController,
                          enabled: !_submitting,
                          decoration: _decoration(),
                          validator: _validateEmail,
                        ),
                      ),
                      const SizedBox(height: 10),
                      FormFieldShell(
                        label: l10n.usermanagementRole,
                        required: true,
                        child: SearchableSelect<Role>(
                          items: effectiveRoleItems,
                          selected: currentRole,
                          labelBuilder: (r) => r.roleName,
                          isDense: true,
                          onChanged: (r) => setState(() => _roleId = r?.id),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (!_isEdit) ...[
                        FormFieldShell(
                          label: l10n.usermanagementPassword,
                          required: true,
                          child: TextFormField(
                            controller: _passwordController,
                            enabled: !_submitting,
                            obscureText: true,
                            decoration: _decoration(),
                            validator: _validatePassword,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      CheckboxListTile(
                        value: _isActive,
                        onChanged: _submitting
                            ? null
                            : (v) => setState(() => _isActive = v ?? true),
                        title: Text(l10n.statusActive),
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

  InputDecoration _decoration() => InputDecoration(
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
  );
}
