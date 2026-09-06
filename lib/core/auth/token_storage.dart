import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// JWT storage abstraction — PORTING.md §3.
///
/// Desktop Flutter has no cookie jar, so the tokens from the login response
/// body (PORTING.md §0) are stored here and attached as
/// `Authorization: Bearer <jwt>` by `ApiClient`.
///
/// Two tokens are kept (SHORTCOMINGS-FIX 6.1): the short-lived access token
/// and a 7-day refresh token used to transparently re-authenticate after
/// the access token expires.
///
/// The concrete [`SecureTokenStorage`] uses flutter_secure_storage (libsecret
/// on Linux). The interface exists so tests can inject an in-memory fake:
/// flutter_secure_storage's Linux FFI blocks waiting for the system keyring
/// daemon, which doesn't exist under `flutter test`.
abstract class TokenStorage {
  Future<String?> readToken();

  Future<void> writeToken(String token);

  Future<String?> readRefreshToken();

  Future<void> writeRefreshToken(String token);

  Future<void> clear();
}

class SecureTokenStorage implements TokenStorage {
  const SecureTokenStorage();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _tokenKey = 'auth_token';
  static const String _refreshTokenKey = 'auth_refresh_token';

  @override
  Future<String?> readToken() => _storage.read(key: _tokenKey);

  @override
  Future<void> writeToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  @override
  Future<String?> readRefreshToken() => _storage.read(key: _refreshTokenKey);

  @override
  Future<void> writeRefreshToken(String token) =>
      _storage.write(key: _refreshTokenKey, value: token);

  @override
  Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }
}

/// Riverpod provider — overridden in tests with an in-memory fake.
final tokenStorageProvider = Provider<TokenStorage>(
  (ref) => const SecureTokenStorage(),
);