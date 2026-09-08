// Roles & Permissions grid — PORTING.md §5. Full-dataset PlutoGrid over
// `GET /roles` (with `permission_count`) — double-tapping a row (or the
// actions menu) opens the permissions editor; the actions menu also
// offers Edit and Delete. System roles (Admin, User) can't be edited or
// deleted — the server guards it too.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:minierp_app/core/theme/status_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/auth/auth_notifier.dart' show authProvider;
import '../../core/utils/csv_export.dart';
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/bulk_operations.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/pluto_grid_screen.dart';
import '../../widgets/screen_toolbar.dart';
import '../../widgets/status_badge.dart';
import 'admin_models.dart';
import 'admin_providers.dart';
import 'admin_repository.dart' show adminRepositoryProvider;
import 'role_form_dialog.dart';
import 'role_permissions_dialog.dart';

class RolesScreen extends ConsumerStatefulWidget {
  const RolesScreen({super.key});

  @override
  ConsumerState<RolesScreen> createState() => _RolesScreenState();
}

class _RolesScreenState extends ConsumerState<RolesScreen>
    with PlutoGridScreen<Role, RolesScreen> {
  Timer? _debounce;
  final TextEditingController _searchController = TextEditingController();
  bool _bulkBusy = false;

  Map<int, Role> get _rolesById => {
    for (final r in ref.read(rolesProvider).valueOrNull ?? const <Role>[])
      r.id: r,
  };

  @override
  bool get enableBulkSelection => true;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      ref.read(rolesSearchProvider.notifier).state = value.trim();
    });
  }

  /// Client-side search over the loaded roles (roles are a small list) —
  /// overrides the mixin's unfiltered clear+append.
  List<Role> _filteredRows(List<Role> roles) {
    final search = ref.read(rolesSearchProvider).toLowerCase();
    if (search.isEmpty) return roles;
    return roles
        .where(
          (r) =>
              r.roleName.toLowerCase().contains(search) ||
              (r.description?.toLowerCase().contains(search) ?? false),
        )
        .toList();
  }

  @override
  void syncGridRows(AsyncValue<Object?> value) {
    final manager = gridStateManager;
    if (manager == null) return;
    manager.setShowLoading(value.isLoading);
    if (value.hasValue) {
      final rows = _filteredRows(value.value as List<Role>);
      manager.removeAllRows();
      manager.appendRows([
        for (final (index, row) in rows.indexed)
          withSerialCell(gridRowFor(row), index),
      ]);
    }
  }

  void _refilter() => syncGridRows(ref.read(rolesProvider));

  @override
  void openRowDetail(int roleId) {
    if (!mounted) return;
    final roles = ref.read(rolesProvider).valueOrNull ?? const <Role>[];
    final matches = roles.where((r) => r.id == roleId);
    if (matches.isEmpty) return;
    showRolePermissionsDialog(context, role: matches.first);
  }

  @override
  PlutoRow gridRowFor(Role role) => PlutoRow(
    cells: {
      'id': PlutoCell(value: role.id),
      'name': PlutoCell(value: role.roleName),
      'description': PlutoCell(value: role.description ?? ''),
      'count': PlutoCell(value: role.permissionCount ?? 0),
      'system': PlutoCell(value: role.isSystemRole),
      'active': PlutoCell(value: role.isActive),
      'actions': PlutoCell(value: ''),
    },
  );

  Future<void> _deleteRole(Role role) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.commonDelete,
      message: '${l10n.usermanagementRoledeleteconfirm}\n\n"${role.roleName}"',
      confirmLabel: l10n.commonDelete,
      cancelLabel: l10n.commonCancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final result = await ref
        .read(adminRepositoryProvider)
        .deleteRole(role.id);
    if (!mounted) return;
    switch (result) {
      case ApiSuccess():
        ref.invalidate(rolesProvider);
        showAppToast(context, l10n.usermanagementRoledeleted);
      case ApiFailure(:final error):
        showAppToast(context, error.message, isError: true);
    }
  }

  /// Bulk hard-delete of the selected roles (no undo — hard delete,
  /// server guards system roles and assigned users).
  Future<void> _bulkDelete(Set<int> ids) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.commonDelete,
      message: '${l10n.bulkDeleteSelected} (${ids.length})?',
      confirmLabel: l10n.commonDelete,
      cancelLabel: l10n.commonCancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    final repo = ref.read(adminRepositoryProvider);
    setState(() => _bulkBusy = true);
    final result = await runBulkOperation(
      ids: ids.toList(),
      labelFor: (id) => _rolesById[id]?.roleName ?? '#$id',
      operation: repo.deleteRole,
    );
    if (!mounted) return;
    setState(() => _bulkBusy = false);
    await finishBulkOperation(
      context,
      bulk: bulkSelection,
      result: result,
      successMessage: l10n.bulkDeleted,
      onComplete: () => ref.invalidate(rolesProvider),
    );
  }

  void _bulkExport(Set<int> ids) {
    final l10n = AppLocalizations.of(context)!;
    final selected = [
      for (final r in _rolesById.values)
        if (ids.contains(r.id)) r,
    ];
    if (selected.isEmpty) return;
    saveCsv(
      context,
      suggestedName: csvSuggestedName('roles'),
      csv: buildRolesCsv(l10n, selected),
      successMessage: l10n.bulkExportSelected,
      errorMessage: l10n.bulkDeleteFailed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final roles = ref.watch(rolesProvider);
    final l10n = AppLocalizations.of(context)!;

    // Keep the grid in sync with provider transitions (loading → data).
    // The mixin listener routes through the overridden syncGridRows, so
    // the client-side search applies on every load/refresh too.
    watchGridProvider(rolesProvider);
    // Client-side search re-runs the filter over the loaded rows without
    // refetching.
    ref.listen(rolesSearchProvider, (previous, next) => _refilter());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            l10n.usermanagementSubtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        // Toolbar: search + refresh + New role.
        ScreenToolbar(
          searchController: _searchController,
          searchHint: l10n.commonSearch,
          onSearchChanged: _onSearchChanged,
          onRefresh: () => ref.invalidate(rolesProvider),
          primaryActions: [
            FilledButton.tonalIcon(
              onPressed: () => showRoleFormDialog(context),
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.usermanagementNewrole),
            ),
          ],
        ),
        ValueListenableBuilder<Set<int>>(
          valueListenable: bulkSelection.selected,
          builder: (context, sel, _) {
            if (sel.isEmpty) return const SizedBox.shrink();
            final user = ref.watch(authProvider).user;
            return BulkActionBar(
              count: sel.length,
              onClearSelection: bulkSelection.clear,
              busy: _bulkBusy,
              actions: [
                if (user?.hasPermission('roles', 'read') ?? false)
                  TextButton.icon(
                    onPressed: () => _bulkExport(sel),
                    icon: const Icon(Icons.file_download_outlined, size: 18),
                    label: Text(l10n.bulkExportSelected),
                  ),
                if (user?.hasPermission('roles', 'delete') ?? false)
                  TextButton.icon(
                    onPressed: () => _bulkDelete(sel),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    label: Text(l10n.bulkDeleteSelected),
                  ),
              ],
            );
          },
        ),
        Expanded(child: gridScreenBody(roles, provider: rolesProvider)),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _rowActions(Role role) {
    final l10n = AppLocalizations.of(context)!;
    return Align(
      alignment: Alignment.center,
      child: PopupMenuButton<String>(
        tooltip: l10n.commonActions,
        icon: const Icon(Icons.more_vert, size: 18),
        onSelected: (action) => switch (action) {
          'permissions' => showRolePermissionsDialog(context, role: role),
          'edit' => showRoleFormDialog(context, role: role),
          'delete' => _deleteRole(role),
          _ => null,
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'permissions',
            child: Row(
              children: [
                const Icon(Icons.shield_outlined, size: 18),
                const SizedBox(width: 8),
                Text(l10n.usermanagementPermissions),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'edit',
            enabled: !role.isSystemRole,
            child: Row(
              children: [
                Icon(
                  Icons.edit_outlined,
                  size: 18,
                  color: role.isSystemRole
                      ? Theme.of(context).disabledColor
                      : null,
                ),
                const SizedBox(width: 8),
                Text(l10n.commonEdit),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'delete',
            enabled: !role.isSystemRole,
            child: Row(
              children: [
                Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: role.isSystemRole
                      ? Theme.of(context).disabledColor
                      : Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 8),
                Text(l10n.commonDelete),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  List<PlutoColumn> buildGridColumns(AppLocalizations l10n) {
    PlutoColumn textColumn(String field, String title, double width) =>
        PlutoColumn(
          title: title,
          field: field,
          type: PlutoColumnType.text(),
          width: width,
          readOnly: true,
          enableContextMenu: false,
        );

    return [
      PlutoColumn(
        title: '',
        field: 'id',
        type: PlutoColumnType.number(),
        width: 80,
        readOnly: true,
        renderer: (ctx) => const SizedBox.shrink(),
        enableContextMenu: false,
        enableFilterMenuItem: false,
        enableHideColumnMenuItem: false,
        enableSetColumnsMenuItem: false,
      ),
      textColumn('name', l10n.usermanagementRolename, 200),
      textColumn('description', l10n.usermanagementDescription, 260),
      textColumn('count', l10n.usermanagementPermissioncount, 130),
      PlutoColumn(
        title: l10n.usermanagementSystemrole,
        field: 'system',
        type: PlutoColumnType.text(),
        width: 110,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) => Builder(
          builder: (cellContext) {
            final isSystem = ctx.cell.value == true;
            final l10n = AppLocalizations.of(cellContext)!;
            return Align(
              alignment: Alignment.centerLeft,
              child: isSystem
                  ? StatusBadge(
                      status: l10n.usermanagementSystemrole,
                      color: Theme.of(context).colorScheme.outline,
                    )
                  : const SizedBox.shrink(),
            );
          },
        ),
      ),
      PlutoColumn(
        title: l10n.commonStatus,
        field: 'active',
        type: PlutoColumnType.text(),
        width: 110,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) => Builder(
          builder: (cellContext) {
            final active = ctx.cell.value == true;
            final l10n = AppLocalizations.of(cellContext)!;
            return Align(
              alignment: Alignment.centerLeft,
              child: StatusBadge(
                status: active ? l10n.statusActive : l10n.statusInactive,
                color: StatusColors.of(context).active(active),
              ),
            );
          },
        ),
      ),
      PlutoColumn(
        title: l10n.commonActions,
        field: 'actions',
        // Pinned to the right edge — stays reachable when the grid scrolls.
        frozen: PlutoColumnFrozen.end,
        type: PlutoColumnType.text(),
        width: 80,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) {
          final id = (ctx.row.cells['id']?.value as num?)?.toInt() ?? 0;
          final rows = ref.read(rolesProvider).valueOrNull ?? const <Role>[];
          final role = rows.where((r) => r.id == id).firstOrNull;
          if (role == null) return const SizedBox.shrink();
          return _rowActions(role);
        },
      ),
    ];
  }
}
