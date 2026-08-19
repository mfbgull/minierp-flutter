// Role permissions editor — loads `GET /roles/:id/permissions` (every
// permission with its `assigned` flag), renders them grouped by module as
// checkbox tiles with per-module Select All / Clear All, and saves the
// checked ids via `PUT /roles/:id/permissions`. System roles keep their
// permissions (the dialog opens read-only for them).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/api_result.dart' show ApiError, ApiFailure, ApiSuccess;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/detail_error.dart';
import 'admin_models.dart';
import 'admin_providers.dart';
import 'admin_repository.dart' show adminRepositoryProvider;
import 'package:minierp_app/core/theme/app_border_radius.dart';

/// Opens the permissions editor for one role.
Future<void> showRolePermissionsDialog(
  BuildContext context, {
  required Role role,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => RolePermissionsDialog(role: role),
  );
}

class RolePermissionsDialog extends ConsumerStatefulWidget {
  const RolePermissionsDialog({super.key, required this.role});

  final Role role;

  @override
  ConsumerState<RolePermissionsDialog> createState() =>
      _RolePermissionsDialogState();
}

class _RolePermissionsDialogState extends ConsumerState<RolePermissionsDialog> {
  late final Set<int> _selected = {};
  bool _loaded = false;
  bool _saving = false;
  String? _error;

  bool get _locked => widget.role.isSystemRole;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final permissions = ref.watch(rolePermissionsProvider(widget.role.id));

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 620),
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
                    l10n.usermanagementPermissionstitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.usermanagementPermissionsubtitle(
                      widget.role.roleName,
                    ),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: permissions.when(
                data: (rows) {
                  if (!_loaded) {
                    _selected
                      ..clear()
                      ..addAll(rows.where((p) => p.assigned).map((p) => p.id));
                    _loaded = true;
                  }
                  return _permissionList(rows);
                },
                loading: () => const SizedBox(
                  height: 320,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => DetailError(
                  message: error is ApiError ? error.message : '$error',
                  onRetry: () => ref.invalidate(
                    rolePermissionsProvider(widget.role.id),
                  ),
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
                    children: [
                      Text(
                        '${_selected.length} / ${permissions.valueOrNull?.length ?? 0}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _locked || _saving
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: Text(l10n.commonCancel),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _locked || _saving
                            ? null
                            : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save_outlined, size: 16),
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

  Widget _permissionList(List<Permission> rows) {
    // Group by module, preserving the server's module/action ordering.
    final byModule = <String, List<Permission>>{};
    for (final p in rows) {
      byModule.putIfAbsent(p.module, () => []).add(p);
    }
    final modules = byModule.keys.toList();

    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        for (final module in modules) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    module.toUpperCase(),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _locked
                      ? null
                      : () => _setModule(byModule[module]!, true),
                  child: Text(
                    '${l10n.actionsSelect} ${l10n.commonAll}',
                  ),
                ),
                TextButton(
                  onPressed: _locked
                      ? null
                      : () => _setModule(byModule[module]!, false),
                  child: Text(l10n.commonClear),
                ),
              ],
            ),
          ),
          for (final permission in byModule[module]!)
            CheckboxListTile(
              value: _selected.contains(permission.id),
              onChanged: _locked
                  ? null
                  : (v) => setState(() {
                        if (v == true) {
                          _selected.add(permission.id);
                        } else {
                          _selected.remove(permission.id);
                        }
                      }),
              title: Text(
                '${permission.action}${permission.description == null ? '' : ' — ${permission.description}'}',
                style: const TextStyle(fontSize: 13),
              ),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: const EdgeInsets.only(left: 8),
            ),
          const Divider(height: 16),
        ],
      ],
    );
  }

  void _setModule(List<Permission> module, bool checked) {
    setState(() {
      if (checked) {
        _selected.addAll(module.map((p) => p.id));
      } else {
        _selected.removeAll(module.map((p) => p.id));
      }
    });
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _saving = true;
      _error = null;
    });
    final result = await ref
        .read(adminRepositoryProvider)
        .updateRolePermissions(widget.role.id, _selected.toList());
    if (!mounted) return;
    switch (result) {
      case ApiSuccess():
        ref.invalidate(rolesProvider);
        Navigator.of(context).pop();
        showAppToast(context, l10n.usermanagementPermissionsaved);
      case ApiFailure(:final error):
        setState(() {
          _saving = false;
          _error = error.message;
        });
    }
  }
}
