import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_events.dart';
import '../auth/token_storage.dart';
import 'endpoints.dart' show ApiEndpoints;
import '../utils/recoverable_failure.dart';

/// Shared HTTP client for the MiniERP backend — PORTING.md §0/§2.
///
/// - Base URL: `http://localhost:3011/api` (override with
///   `--dart-define=API_BASE_URL=...`). Packaged builds point the client at
///   the bundled backend's ephemeral port at boot via [setBaseUrl].
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
    _instances.add(this.dio);
    _attachInterceptors();
  }

  final Dio dio;
  final TokenStorage tokenStorage;
  final SessionEvents? sessionEvents;

  /// Single-flight refresh: concurrent 401s share one `/auth/refresh`
  /// round-trip instead of stampeding the server.
  Future<bool>? _refreshing;

  /// Compile-time override (`--dart-define=API_BASE_URL=...`), empty when
  /// unset so the boot supervisor can tell the difference.
  static const String configuredBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
  );

  static const String defaultBaseUrl = 'http://localhost:3011/api';

  static String _baseUrl = configuredBaseUrl.isEmpty
      ? defaultBaseUrl
      : configuredBaseUrl;

  /// Every live Dio instance, so a base-URL change made after a provider was
  /// built (the packaged backend's port is only known at boot) still applies.
  static final Set<Dio> _instances = {};

  static String get baseUrl => _baseUrl;

  /// Points every existing and future client at [value]. The supervisor
  /// calls this before the first auth request runs.
  static void setBaseUrl(String value) {
    if (value.isEmpty || value == _baseUrl) return;
    _baseUrl = value;
    for (final dio in _instances) {
      dio.options.baseUrl = value;
    }
  }

  static BaseOptions _baseOptions() => BaseOptions(
    baseUrl: _baseUrl,
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
          } catch (error) {
            reportRecoverableFailure('api.read_token', error);
          }
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
              } catch (error) {
                reportRecoverableFailure('api.retry_after_refresh', error);
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
            } catch (error) {
              reportRecoverableFailure('api.clear_tokens', error);
            }
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
    } catch (error) {
      reportRecoverableFailure('api.read_refresh_token', error);
    }
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
          } catch (error) {
            reportRecoverableFailure('api.save_refreshed_token', error);
            return false;
          }
          return true;
        }
      }
      return false;
    } catch (error) {
      reportRecoverableFailure('api.refresh_session', error);
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
