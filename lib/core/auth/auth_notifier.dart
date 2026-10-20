import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/auth_user.dart' show AuthUser;
import '../../data/repositories/api_result.dart'
    show ApiError, ApiFailure, ApiSuccess;
import '../../data/repositories/auth_repository.dart'
    show AuthLoginResult, AuthRepository, authRepositoryProvider;
import 'token_storage.dart' show TokenStorage, tokenStorageProvider;
import '../utils/recoverable_failure.dart';

/// Session state machine — PORTING.md §3.
///
/// Boot: `restoreSession()` reads the stored JWT and calls `GET /auth/me`.
/// The router gates on `AuthStatus` (splash → login or shell), so this
/// notifier is the single source of truth for the whole app.
class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._repo, this._storage)
    : super(const AuthState(status: AuthStatus.unknown)) {
    unawaited(restoreSession());
  }

  final AuthRepository _repo;
  final TokenStorage _storage;

  /// Called at app boot: GET /auth/me with the stored JWT.
  Future<void> restoreSession() async {
    if (state.status != AuthStatus.unknown) return; // already resolved
    final token = await _readToken();
    if (token == null || token.isEmpty) {
      state = const AuthState(status: AuthStatus.unauthenticated);
      return;
    }
    final result = await _repo.me();
    state = switch (result) {
      ApiSuccess(:final data) => AuthState(
        status: AuthStatus.authenticated,
        user: data,
      ),
      ApiFailure() => const AuthState(status: AuthStatus.unauthenticated),
    };
  }

  /// Returns `null` on success (the router redirects to '/'); otherwise the
  /// failure `ApiError` so the login screen can display it.
  Future<ApiError?> login(String username, String password) async {
    final result = await _repo.login(username, password);
    return switch (result) {
      ApiSuccess(:final data) => _applyLogin(data),
      ApiFailure(:final error) => error,
    };
  }

  Future<ApiError?> _applyLogin(AuthLoginResult login) async {
    if (!await _writeToken(login.token) ||
        !await _writeRefreshToken(login.refreshToken)) {
      await _clearToken();
      state = const AuthState(status: AuthStatus.unauthenticated);
      return const ApiError(
        code: 'SESSION_STORAGE_UNAVAILABLE',
        message:
            'Could not save your session. Check secure storage and sign in again.',
      );
    }
    state = AuthState(status: AuthStatus.authenticated, user: login.user);
    return null;
  }

  Future<void> logout() async {
    await _repo.logout(); // best-effort; clears the server cookie
    await _clearToken();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  /// Called when the dio layer observes a 401 mid-session (expired token).
  /// Skips the server logout — that call would 401 too and re-trigger this.
  Future<void> sessionExpired() async {
    await _clearToken();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  /// Stores a fresh access token produced by the dio refresh interceptor
  /// (the user object is unchanged, so the session state stays put).
  Future<void> updateAccessToken(String token) async {
    if (!await _writeToken(token)) await sessionExpired();
  }

  // Storage calls are wrapped so a storage failure (headless keyring,
  // missing plugin) degrades to "no session" instead of crashing.
  Future<String?> _readToken() async {
    try {
      return await _storage.readToken();
    } catch (error) {
      reportRecoverableFailure('session.read_token', error);
      return null;
    }
  }

  Future<bool> _writeToken(String token) async {
    try {
      await _storage.writeToken(token);
      return true;
    } catch (error) {
      reportRecoverableFailure('session.write_token', error);
      return false;
    }
  }

  Future<bool> _writeRefreshToken(String token) async {
    try {
      await _storage.writeRefreshToken(token);
      return true;
    } catch (error) {
      reportRecoverableFailure('session.write_refresh_token', error);
      return false;
    }
  }

  Future<void> _clearToken() async {
    try {
      await _storage.clear();
    } catch (error) {
      reportRecoverableFailure('session.clear_tokens', error);
    }
  }
}

enum AuthStatus { unknown, unauthenticated, authenticated }

class AuthState {
  const AuthState({required this.status, this.user});

  final AuthStatus status;
  final AuthUser? user;

  bool get isAuthenticated => status == AuthStatus.authenticated;

  String? get username => user?.username;
}

/// Riverpod provider (replaces the web app's auth context).
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(
    ref.watch(authRepositoryProvider),
    ref.watch(tokenStorageProvider),
  ),
);
