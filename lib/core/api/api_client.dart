import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_events.dart';
import '../auth/token_storage.dart';
import 'endpoints.dart' show ApiEndpoints;

/// Shared HTTP client for the MiniERP backend — PORTING.md §0/§2.
///
/// - Base URL: `http://localhost:3011/api` (override with
///   `--dart-define=API_BASE_URL=...`).
/// - 10s timeouts (matches the web client).
/// - Request interceptor attaches `Authorization: Bearer <jwt>` from the
///   injected [TokenStorage].
/// - On 401 (and the stored refresh token is usable) the request is
///   transparently retried once after exchanging the refresh token
///   (SHORTCOMINGS-FIX 6.1); only when refresh fails is the session
///   cleared so the UI can route to login.
class ApiClient {
  ApiClient({Dio? dio, TokenStorage? tokenStorage, this.sessionEvents})
    : tokenStorage = tokenStorage ?? const SecureTokenStorage(),
      dio = dio ?? Dio(_baseOptions()) {
    _attachInterceptors();
  }

  final Dio dio;
  final TokenStorage tokenStorage;
  final SessionEvents? sessionEvents;

  /// Single-flight refresh: concurrent 401s share one `/auth/refresh`
  /// round-trip instead of stampeding the server.
  Future<bool>? _refreshing;

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3011/api',
  );

  static BaseOptions _baseOptions() => BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    sendTimeout: const Duration(seconds: 10),
    responseType: ResponseType.json,
    headers: const {'Accept': 'application/json'},
  );

  void _attachInterceptors() {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Secure storage can be unavailable (tests, keyring missing) —
          // degrade to an anonymous request instead of throwing.
          String? token;
          try {
            token = await tokenStorage.readToken();
          } catch (_) {}
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final is401 = error.response?.statusCode == 401;
          final canRefresh =
              is401 &&
              !_isCredential401(error) &&
              error.requestOptions.path != ApiEndpoints.refresh;
          if (canRefresh) {
            final refreshed = await _refreshAccessToken();
            if (refreshed && error.requestOptions.extra['_retried'] != true) {
              // Re-send the original request; the request interceptor
              // re-attaches the fresh access token.
              error.requestOptions.extra['_retried'] = true;
              try {
                final retried = await dio.fetch(error.requestOptions);
                handler.resolve(retried);
                return;
              } catch (_) {
                // Fall through: the retry also failed → expire the session.
              }
            }
          }
          // The refresh endpoint's own 401 is expected (bad/expired
          // refresh token) — the original request's handler below fires
          // the expiry event once, so skip it here to avoid double-firing.
          if (is401 &&
              !_isCredential401(error) &&
              error.requestOptions.path != ApiEndpoints.refresh) {
            try {
              await tokenStorage.clear();
            } catch (_) {}
            // PORTING.md §2: 401 → clear session → login screen. The app
            // listens on [SessionEvents.unauthorized] and expires the
            // session (avoids a dioProvider → authProvider cycle).
            sessionEvents?.notifyUnauthorized();
          }
          handler.next(error);
        },
      ),
    );
  }

  /// Tries to exchange the stored refresh token for a fresh access token.
  /// Returns `true` when a new access token was stored. Concurrent callers
  /// await the same in-flight exchange.
  Future<bool> _refreshAccessToken() {
    final inFlight = _refreshing;
    if (inFlight != null) return inFlight;
    final future = _doRefresh();
    _refreshing = future;
    return future.whenComplete(() => _refreshing = null);
  }

  Future<bool> _doRefresh() async {
    String? refreshToken;
    try {
      refreshToken = await tokenStorage.readRefreshToken();
    } catch (_) {}
    if (refreshToken == null || refreshToken.isEmpty) return false;
    try {
      final response = await dio.post(
        ApiEndpoints.refresh,
        data: {'refreshToken': refreshToken},
      );
      final body = response.data;
      if (body is Map<String, dynamic> && body['success'] == true) {
        final data = body['data'];
        final token = data is Map<String, dynamic>
            ? data['token'] as String?
            : null;
        if (token != null && token.isNotEmpty) {
          try {
            await tokenStorage.writeToken(token);
          } catch (_) {}
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Whether a 401 means "bad credentials for this request" (the stored
  /// JWT is still valid) instead of "expired session". Those must NOT
  /// clear the token or log the user out:
  ///
  /// - `/auth/login`: no token is involved — a 401 is always bad
  ///   credentials.
  /// - `/auth/change-password`: the handler's wrong-current-password 401
  ///   (`sendError` envelope: `error` is a map with `message`) keeps the
  ///   session, while the auth middleware's expired/invalid-token 401s
  ///   (`error` is a string, e.g. `{error: 'Token expired'}`) still expire
  ///   it.
  bool _isCredential401(DioException error) {
    final path = error.requestOptions.path;
    if (path == ApiEndpoints.login) return true;
    if (path != ApiEndpoints.changePassword) return false;
    final body = error.response?.data;
    if (body is Map<String, dynamic>) {
      final err = body['error'];
      return err is Map<String, dynamic> && err['message'] is String;
    }
    return false;
  }
}

/// Riverpod provider for the shared Dio instance (PORTING.md §1: dio
/// replaces axios; 401 → login redirection is handled by the auth feature).
final dioProvider = Provider<Dio>(
  (ref) => ApiClient(
    tokenStorage: ref.watch(tokenStorageProvider),
    sessionEvents: ref.watch(sessionEventsProvider),
  ).dio,
);
