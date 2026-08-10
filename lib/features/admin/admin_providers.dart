// User management providers — full-dataset lists (`GET /users` and
// `GET /roles` return no pagination, so the grids sort/filter client-side
// like the items screen), plus per-role permission fetches. The screens
// invalidate these after create/edit/delete/status mutations.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import 'admin_models.dart';
import 'admin_repository.dart' show UserFilters, adminRepositoryProvider;

/// Active tab index of the admin shell (0 users, 1 roles). A provider
/// (not local state) so screens can switch tabs programmatically.
final adminShellTabProvider = StateProvider<int>((ref) => 0);

/// Debounced search term for the users grid (username/email/full_name on
/// the server). Empty value omits the param.
final usersSearchProvider = StateProvider<String>((ref) => '');

/// Active role filter — null means "all roles". Values are the role names
/// the server matches (`admin`, `user`, …).
final usersRoleFilterProvider = StateProvider<String?>((ref) => null);

/// Active status filter — null means "all statuses".
final usersStatusFilterProvider = StateProvider<bool?>((ref) => null);

/// All system users (`GET /users`). Re-runs when any filter changes; the
/// screen invalidates it on refresh and after mutations.
final usersProvider = FutureProvider<List<User>>((ref) async {
  final search = ref.watch(usersSearchProvider);
  final role = ref.watch(usersRoleFilterProvider);
  final status = ref.watch(usersStatusFilterProvider);
  final result = await ref
      .watch(adminRepositoryProvider)
      .users(
        UserFilters(
          search: search.isEmpty ? null : search,
          role: role,
          isActive: status,
        ),
      );
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// All roles with permission counts (`GET /roles`).
/// Client-side search term for the roles grid (roles are a small list —
/// the screen filters the loaded rows by name).
final rolesSearchProvider = StateProvider<String>((ref) => '');

final rolesProvider = FutureProvider<List<Role>>((ref) async {
  final result = await ref.watch(adminRepositoryProvider).roles();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// One role's permission rows with the `assigned` flag
/// (`GET /roles/:id/permissions`). autoDispose: each permissions dialog
/// owns its fetch.
final rolePermissionsProvider = FutureProvider.autoDispose
    .family<List<Permission>, int>((ref, roleId) async {
      final result = await ref
          .watch(adminRepositoryProvider)
          .rolePermissions(roleId);
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });

/// Role-name → roles lookup used by the user form's role dropdown.
final rolesByProvider = Provider.autoDispose<Map<int, Role>>(
  (ref) => {
    for (final role in ref.watch(rolesProvider).valueOrNull ?? const [])
      role.id: role,
  },
);
