// Users grid — PORTING.md §5/§6. Full-dataset PlutoGrid over
// `GET /users` (no pagination block, so the grid sorts/filters
// client-side like the items screen) with server-side search + role/
// status filters. Double-tapping a row opens the edit form; the per-row
// actions menu offers Edit, Reset Password, Activate/Deactivate and
// Delete (the server guards self-actions and the last-admin rule).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:minierp_app/core/theme/status_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/auth/auth_notifier.dart' show authProvider;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/pluto_grid_screen.dart';
import '../../widgets/screen_toolbar.dart';
import '../../widgets/status_badge.dart';
import 'admin_models.dart';
import 'admin_providers.dart';
import 'admin_repository.dart' show adminRepositoryProvider;
import 'user_form_dialog.dart';

class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen>
    with PlutoGridScreen<User, UsersScreen> {
  Timer? _debounce;
  final TextEditingController _searchController = TextEditingController();

  @override
  void openRowDetail(int userId) {
    if (!mounted) return;
    final rows = ref.read(usersProvider).valueOrNull ?? const <User>[];
    final matches = rows.where((u) => u.id == userId);
    if (matches.isEmpty) return;
    showUserFormDialog(context, user: matches.first);
  }

  @override
  PlutoRow gridRowFor(User user) => PlutoRow(
    cells: {
      'id': PlutoCell(value: user.id),
      'username': PlutoCell(value: user.username),
      'full_name': PlutoCell(value: user.displayName),
      'email': PlutoCell(value: user.email ?? ''),
      'role': PlutoCell(value: user.role ?? ''),
      'active': PlutoCell(value: user.isActive),
      'actions': PlutoCell(value: ''),
    },
  );

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
      ref.read(usersSearchProvider.notifier).state = value.trim();
    });
  }

  bool get _hasActiveFilters =>
      ref.read(usersRoleFilterProvider) != null ||
      ref.read(usersStatusFilterProvider) != null;

  void _clearFilters() {
    ref.read(usersRoleFilterProvider.notifier).state = null;
    ref.read(usersStatusFilterProvider.notifier).state = null;
  }

  Future<void> _toggleStatus(User user) async {
    final l10n = AppLocalizations.of(context)!;
    final activating = !user.isActive;
    final confirmed = await showConfirmDialog(
      context,
      title: activating ? l10n.usermanagementActivate : l10n.usermanagementDeactivate,
      message: activating
          ? '${l10n.usermanagementActivate} "${user.username}"?'
          : '${l10n.usermanagementDeactivate} "${user.username}"?',
      confirmLabel: activating
          ? l10n.usermanagementActivate
          : l10n.usermanagementDeactivate,
      cancelLabel: l10n.commonCancel,
      destructive: !activating,
    );
    if (!confirmed || !mounted) return;
    final result = await ref
        .read(adminRepositoryProvider)
        .toggleUserStatus(user.id, activating);
    if (!mounted) return;
    switch (result) {
      case ApiSuccess():
        ref.invalidate(usersProvider);
        showAppToast(
          context,
          activating ? l10n.usermanagementActivated : l10n.usermanagementDeactivated,
        );
      case ApiFailure(:final error):
        showAppToast(context, error.message, isError: true);
    }
  }

  Future<void> _resetPassword(User user) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.usermanagementResetpassword,
      message: '${l10n.usermanagementResetconfirm} (${user.username})',
      confirmLabel: l10n.commonConfirm,
      cancelLabel: l10n.commonCancel,
    );
    if (!confirmed || !mounted) return;
    // The reset dialog posts with the server's default flow — the user
    // must supply the new password (at least 6 chars).
    final newPassword = await _promptNewPassword(l10n);
    if (newPassword == null || !mounted) return;
    final result = await ref
        .read(adminRepositoryProvider)
        .resetPassword(user.id, newPassword);
    if (!mounted) return;
    switch (result) {
      case ApiSuccess():
        showAppToast(context, l10n.usermanagementResetdone);
      case ApiFailure(:final error):
        showAppToast(context, error.message, isError: true);
    }
  }

  Future<String?> _promptNewPassword(AppLocalizations l10n) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.usermanagementResetpassword),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l10n.usermanagementNewpassword,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(l10n.commonConfirm),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteUser(User user) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.commonDelete,
      message: '${l10n.usermanagementDeleteconfirm}\n\n"${user.username}"',
      confirmLabel: l10n.commonDelete,
      cancelLabel: l10n.commonCancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final result = await ref
        .read(adminRepositoryProvider)
        .deleteUser(user.id);
    if (!mounted) return;
    switch (result) {
      case ApiSuccess():
        ref.invalidate(usersProvider);
        showAppToast(context, l10n.usermanagementUserdeleted);
      case ApiFailure(:final error):
        showAppToast(context, error.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(usersProvider);
    final l10n = AppLocalizations.of(context)!;

    watchGridProvider(usersProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScreenToolbar(
          searchController: _searchController,
          searchHint: l10n.usermanagementSearchusers,
          onSearchChanged: _onSearchChanged,
          onClearSearch: () {
            _debounce?.cancel();
            _searchController.clear();
            ref.read(usersSearchProvider.notifier).state = '';
          },
          filters: [
            ScreenToolbarDropdown<String?>(
              key: const ValueKey('user-role-filter'),
              value: ref.watch(usersRoleFilterProvider),
              items: [null, for (final role in _allRoleNames) role],
              labelBuilder: (v) => v ?? l10n.usermanagementAllroles,
              width: 140,
              onChanged: (v) =>
                  ref.read(usersRoleFilterProvider.notifier).state = v,
            ),
            ScreenToolbarDropdown<bool?>(
              key: const ValueKey('user-status-filter'),
              value: ref.watch(usersStatusFilterProvider),
              items: const [null, true, false],
              labelBuilder: (v) => switch (v) {
                null => l10n.usermanagementAllstatus,
                true => l10n.statusActive,
                _ => l10n.statusInactive,
              },
              width: 140,
              onChanged: (v) =>
                  ref.read(usersStatusFilterProvider.notifier).state = v,
            ),
          ],
          onRefresh: () => ref.invalidate(usersProvider),
          onClearAll: _clearFilters,
          hasActiveFilters: _hasActiveFilters,
          primaryActions: [
            FilledButton.tonalIcon(
              onPressed: () => showUserFormDialog(context),
              icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
              label: Text(l10n.usermanagementNewuser),
            ),
          ],
        ),
        Expanded(child: gridScreenBody(users, provider: usersProvider)),
        const SizedBox(height: 16),
      ],
    );
  }

  List<String> get _allRoleNames {
    final roles = ref.watch(rolesProvider).valueOrNull ?? const [];
    return roles.map((r) => r.roleName).toList()..sort();
  }

  Widget _rowActions(User user) {
    final l10n = AppLocalizations.of(context)!;
    final currentUserId = ref.watch(authProvider).user?.id;
    final isSelf = currentUserId == user.id;
    return Align(
      alignment: Alignment.center,
      child: PopupMenuButton<String>(
        tooltip: l10n.commonActions,
        icon: const Icon(Icons.more_vert, size: 18),
        onSelected: (action) => switch (action) {
          'edit' => showUserFormDialog(context, user: user),
          'reset' => _resetPassword(user),
          'status' => _toggleStatus(user),
          'delete' => _deleteUser(user),
          _ => null,
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'edit',
            child: Row(
              children: [
                const Icon(Icons.edit_outlined, size: 18),
                const SizedBox(width: 8),
                Text(l10n.commonEdit),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'reset',
            child: Row(
              children: [
                const Icon(Icons.password_outlined, size: 18),
                const SizedBox(width: 8),
                Text(l10n.usermanagementResetpassword),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'status',
            enabled: !isSelf,
            child: Row(
              children: [
                Icon(
                  user.isActive
                      ? Icons.block_outlined
                      : Icons.check_circle_outline,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  user.isActive
                      ? l10n.usermanagementDeactivate
                      : l10n.usermanagementActivate,
                ),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'delete',
            enabled: !isSelf,
            child: Row(
              children: [
                Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: isSelf
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
      textColumn('username', l10n.usermanagementUsername, 150),
      textColumn('full_name', l10n.usermanagementFullname, 200),
      textColumn('email', l10n.usermanagementEmail, 200),
      textColumn('role', l10n.usermanagementRole, 120),
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
          final rows = ref.read(usersProvider).valueOrNull ?? const <User>[];
          final user = rows.where((u) => u.id == id).firstOrNull;
          if (user == null) return const SizedBox.shrink();
          return _rowActions(user);
        },
      ),
    ];
  }
}
