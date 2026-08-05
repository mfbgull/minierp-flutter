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
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: asInt(json['id']) ?? 0,
        username: asString(json['username']) ?? '',
        email: asString(json['email']),
        fullName: asString(json['full_name']),
        role: asString(json['role']),
        isActive: asBool(json['is_active'], fallback: true),
        createdAt: asString(json['created_at']),
      );

  final int id;
  final String username;
  final String? email;
  final String? fullName;
  final String? role;
  final bool isActive;
  final String? createdAt;

  bool get isAdmin => role == 'admin';

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
      };
}
