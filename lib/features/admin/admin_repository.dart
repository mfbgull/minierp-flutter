// User management repository — typed against `server/src/routes/users.ts`
// and `server/src/routes/roles.ts` (PORTING.md §5, admin-only).
//
// Endpoint shapes (verified against the live server):
// - `GET /users?role&is_active&search` → `{success, data: [User]}`
//   (no pagination — full dataset, client-side grid sort)
// - `GET /users/:id` → `{success, data: User}`
// - `POST /users` → `{success, data: User}` (201), body `{username,
//   email, password, full_name, role_id, is_active}`
// - `PUT /users/:id` → `{success, data: User}`, body `{username, email,
//   full_name, role_id, is_active}`
// - `DELETE /users/:id` → `{success, message}`
// - `PUT /users/:id/reset-password` → `{success, message}`, body
//   `{newPassword}`
// - `PUT /users/:id/toggle-status` → `{success, message}`, body
//   `{is_active}`
// - `GET /roles` → `{success, data: [Role]}` (with permission_count)
// - `GET /roles/permissions` → `{success, data: {module: [Permission]}}`
// - `GET /roles/:id/permissions` → `{success, data: [Permission+assigned]}`
// - `POST /roles` → `{success, data: Role}` (201), body `{role_name,
//   description, permissions: [ids]}`
// - `PUT /roles/:id` → `{success, data: Role}`, body `{role_name,
//   description, is_active}`
// - `PUT /roles/:id/permissions` → `{success, message}`, body
//   `{permissions: [ids]}`
// - `DELETE /roles/:id` → `{success, message}`

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart' show dioProvider;
import '../../core/api/endpoints.dart' show ApiEndpoints;
import '../../data/repositories/api_result.dart';
import '../../data/repositories/repository_client.dart';
import 'admin_models.dart';

/// Users list filters — mirrors the `getUsers` controller params.
class UserFilters {
  const UserFilters({this.role, this.isActive, this.search});

  final String? role;
  final bool? isActive;
  final String? search;

  Map<String, dynamic> toQuery() => {
    if (role != null && role!.isNotEmpty) 'role': role,
    if (isActive != null) 'is_active': isActive! ? 1 : 0,
    if (search != null && search!.isNotEmpty) 'search': search,
  };
}

class AdminRepository {
  AdminRepository(this._client);

  final RepositoryClient _client;

  /* ── Users ─────────────────────────────────────────────────── */

  /// `GET /users` — full dataset (no pagination).
  Future<ApiResult<List<User>>> users(UserFilters filters) => _client.getList(
    ApiEndpoints.users,
    queryParameters: filters.toQuery(),
    parseItem: (Object? json) => User.fromJson(json! as Map<String, dynamic>),
  );

  Future<ApiResult<User>> user(int id) => _client.get(
    '${ApiEndpoints.users}/$id',
    parse: (Object? json) => User.fromJson(json! as Map<String, dynamic>),
  );

  /// `POST /users` — body per the createUser DTO.
  Future<ApiResult<User>> createUser(Map<String, dynamic> body) =>
      _client.post(
        ApiEndpoints.users,
        body: body,
        parse: (Object? json) =>
            User.fromJson(json! as Map<String, dynamic>),
      );

  Future<ApiResult<User>> updateUser(int id, Map<String, dynamic> body) =>
      _client.put(
        '${ApiEndpoints.users}/$id',
        body: body,
        parse: (Object? json) =>
            User.fromJson(json! as Map<String, dynamic>),
      );

  /// `DELETE /users/:id` — soft delete; `{success, message}`.
  Future<ApiResult<void>> deleteUser(int id) =>
      _client.delete('${ApiEndpoints.users}/$id');

  /// `PUT /users/:id/toggle-status` — body `{is_active}`.
  Future<ApiResult<void>> toggleUserStatus(int id, bool isActive) =>
      _client.put(
        '${ApiEndpoints.users}/$id/toggle-status',
        body: {'is_active': isActive},
        parse: (Object? json) {},
      );

  /// `PUT /users/:id/reset-password` — body `{newPassword}` (camelCase on
  /// the server).
  Future<ApiResult<void>> resetPassword(int id, String newPassword) =>
      _client.put(
        '${ApiEndpoints.users}/$id/reset-password',
        body: {'newPassword': newPassword},
        parse: (Object? json) {},
      );

  /* ── Roles ─────────────────────────────────────────────────── */

  /// `GET /roles` — all roles with `permission_count`.
  Future<ApiResult<List<Role>>> roles() => _client.getList(
    ApiEndpoints.roles,
    parseItem: (Object? json) => Role.fromJson(json! as Map<String, dynamic>),
  );

  /// `GET /roles/:id/permissions` — every permission with its `assigned`
  /// flag for the role.
  Future<ApiResult<List<Permission>>> rolePermissions(int roleId) =>
      _client.getList(
        '${ApiEndpoints.roles}/$roleId/permissions',
        parseItem: (Object? json) =>
            Permission.fromJson(json! as Map<String, dynamic>),
      );

  /// `POST /roles` — body per the createRole DTO (optional permission ids
  /// are assigned at creation).
  Future<ApiResult<Role>> createRole(Map<String, dynamic> body) =>
      _client.post(
        ApiEndpoints.roles,
        body: body,
        parse: (Object? json) => Role.fromJson(json! as Map<String, dynamic>),
      );

  Future<ApiResult<Role>> updateRole(int id, Map<String, dynamic> body) =>
      _client.put(
        '${ApiEndpoints.roles}/$id',
        body: body,
        parse: (Object? json) => Role.fromJson(json! as Map<String, dynamic>),
      );

  /// `PUT /roles/:id/permissions` — body `{permissions: [ids]}`.
  Future<ApiResult<void>> updateRolePermissions(
    int roleId,
    List<int> permissionIds,
  ) => _client.put(
    '${ApiEndpoints.roles}/$roleId/permissions',
    body: {'permissions': permissionIds},
    parse: (Object? json) {},
  );

  /// `DELETE /roles/:id` — `{success, message}`.
  Future<ApiResult<void>> deleteRole(int id) =>
      _client.delete('${ApiEndpoints.roles}/$id');
}

final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => AdminRepository(RepositoryClient(ref.watch(dioProvider))),
);
