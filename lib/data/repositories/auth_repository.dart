// Auth repository — typed against the auth controller (PORTING.md §0/§3).
//
// Envelope variants:
// - `POST /auth/login` → `{success, data: {token, user}}` — the JWT is
//   returned in the body for desktop (PORTING.md §0); the httpOnly cookie
//   stays for the web client.
// - `GET /auth/me` → `{success, data: user}`
// - `POST /auth/logout` → `{success, data: {message}}`

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart' show dioProvider;
import '../../core/api/endpoints.dart' show ApiEndpoints;
import '../models/auth_user.dart' show AuthUser;
import 'api_result.dart';
import 'repository_client.dart';

/// `{token, user}` from the login response body.
class AuthLoginResult {
  const AuthLoginResult({required this.token, required this.user});

  factory AuthLoginResult.fromJson(Map<String, dynamic> json) =>
      AuthLoginResult(
        token: json['token'] as String? ?? '',
        user: AuthUser.fromJson(
          json['user'] is Map<String, dynamic>
              ? json['user'] as Map<String, dynamic>
              : const {},
        ),
      );

  final String token;
  final AuthUser user;
}

class AuthRepository {
  AuthRepository(this._api);

  final RepositoryClient _api;

  Future<ApiResult<AuthLoginResult>> login(String username, String password) =>
      _api.post(
        ApiEndpoints.login,
        body: {'username': username, 'password': password},
        parse: (Object? json) =>
            AuthLoginResult.fromJson(json as Map<String, dynamic>),
      );

  Future<ApiResult<AuthUser>> me() => _api.get(
        ApiEndpoints.me,
        parse: (Object? json) => AuthUser.fromJson(json as Map<String, dynamic>),
      );

  /// Best-effort server-side logout (clears the cookie for the web
  /// client); the native client clears its stored token locally.
  Future<ApiResult<void>> logout() => _api.post(
        ApiEndpoints.logout,
        parse: (_) {},
      );

  /// `POST /auth/change-password` (rate-limited 3/hour). A 401 here means
  /// "wrong current password", not an expired session — the dio interceptor
  /// is told to leave the session alone for this path.
  Future<ApiResult<void>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) =>
      _api.post(
        ApiEndpoints.changePassword,
        body: {
          'currentPassword': currentPassword,
          'newPassword': newPassword,
        },
        parse: (_) {},
      );
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(RepositoryClient(ref.watch(dioProvider))),
);
