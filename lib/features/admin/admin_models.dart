// User management models — shaped after `types/client-types.ts` and the
// server User/Role models (PORTING.md §4). Field names match the API JSON
// keys verbatim.

import '../../data/models/json_helpers.dart';

/// One system user — the shape `GET /users` and `GET /users/:id` return
/// (`UserModel.getPublicById`: no password_hash is ever sent).
class User {
  const User({
    required this.id,
    required this.username,
    this.fullName,
    this.email,
    this.role,
    this.roleId,
    required this.isActive,
    this.createdAt,
    this.updatedAt,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: asInt(json['id']) ?? 0,
    username: asString(json['username']) ?? '',
    fullName: asString(json['full_name']),
    email: asString(json['email']),
    role: asString(json['role']),
    roleId: asInt(json['role_id']),
    isActive: asBool(json['is_active'], fallback: true),
    createdAt: asString(json['created_at']),
    updatedAt: asString(json['updated_at']),
  );

  final int id;
  final String username;
  final String? fullName;
  final String? email;

  /// `admin` | `user` (roles.role_name, lowercased server-side).
  final String? role;
  final int? roleId;
  final bool isActive;
  final String? createdAt;
  final String? updatedAt;

  String get displayName =>
      (fullName != null && fullName!.isNotEmpty) ? fullName! : username;

  Map<String, dynamic> toJson() => {
    'username': username,
    if (email != null) 'email': email,
    if (fullName != null) 'full_name': fullName,
    if (roleId != null) 'role_id': roleId,
    'is_active': isActive,
  };
}

/// One role — `GET /roles` returns these with `permission_count`.
class Role {
  const Role({
    required this.id,
    required this.roleName,
    this.description,
    required this.isSystemRole,
    required this.isActive,
    this.permissionCount,
  });

  factory Role.fromJson(Map<String, dynamic> json) => Role(
    id: asInt(json['id']) ?? 0,
    roleName: asString(json['role_name']) ?? '',
    description: asString(json['description']),
    isSystemRole: asBool(json['is_system_role'], fallback: false),
    isActive: asBool(json['is_active'], fallback: true),
    permissionCount: asInt(json['permission_count']),
  );

  final int id;
  final String roleName;
  final String? description;
  final bool isSystemRole;
  final bool isActive;
  final int? permissionCount;
}

/// One permission row. `GET /roles/permissions` returns them grouped by
/// module; `GET /roles/:id/permissions` adds the `assigned` flag.
class Permission {
  const Permission({
    required this.id,
    required this.action,
    required this.module,
    this.description,
    this.assigned = false,
  });

  factory Permission.fromJson(Map<String, dynamic> json) => Permission(
    id: asInt(json['id']) ?? 0,
    action: asString(json['action']) ?? '',
    module: asString(json['module']) ?? '',
    description: asString(json['description']),
    assigned: asBool(json['assigned'], fallback: false),
  );

  final int id;
  final String action;
  final String module;
  final String? description;
  final bool assigned;

  Map<String, dynamic> toJson() => {
    'id': id,
    'action': action,
    'module': module,
    if (description != null) 'description': description,
    'assigned': assigned,
  };
}
