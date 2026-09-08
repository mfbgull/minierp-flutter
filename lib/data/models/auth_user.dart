import 'json_helpers.dart';

/// Logged-in user — the `user` from the login body and `GET /auth/me`
/// (server `UserModel.getById` shape: no `password_hash` is ever sent).
class AuthUser {
  const AuthUser({
    required this.id,
    required this.username,
    this.email,
    this.fullName,
    this.role,
    this.isActive = true,
    this.createdAt,
    this.permissions = const [],
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
    id: asInt(json['id']) ?? 0,
    username: asString(json['username']) ?? '',
    email: asString(json['email']),
    fullName: asString(json['full_name']),
    role: asString(json['role']),
    isActive: asBool(json['is_active'], fallback: true),
    createdAt: asString(json['created_at']),
    permissions: (json['permissions'] as List<dynamic>?)
            ?.map((p) => Permission.fromJson(p as Map<String, dynamic>))
            .toList() ??
        const [],
  );

  final int id;
  final String username;
  final String? email;
  final String? fullName;
  final String? role;
  final bool isActive;
  final String? createdAt;
  final List<Permission> permissions;

  bool get isAdmin => role == 'admin';

  /// D12: check if the user has a specific (module, action) permission.
  /// Admin always returns true (server sends all permissions for admin).
  bool hasPermission(String module, String action) {
    if (isAdmin) return true;
    return permissions.any((p) => p.module == module && p.action == action);
  }

  String get displayName =>
      (fullName != null && fullName!.isNotEmpty) ? fullName! : username;

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    if (email != null) 'email': email,
    if (fullName != null) 'full_name': fullName,
    if (role != null) 'role': role,
    'is_active': isActive ? 1 : 0,
    if (createdAt != null) 'created_at': createdAt,
    'permissions': permissions.map((p) => p.toJson()).toList(),
  };
}

/// A single (module, action) permission pair from the server's permissions table.
class Permission {
  const Permission({required this.module, required this.action});

  factory Permission.fromJson(Map<String, dynamic> json) => Permission(
    module: asString(json['module']) ?? '',
    action: asString(json['action']) ?? '',
  );

  final String module;
  final String action;

  Map<String, dynamic> toJson() => {'module': module, 'action': action};
}
