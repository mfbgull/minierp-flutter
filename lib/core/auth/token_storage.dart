import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// JWT storage abstraction — PORTING.md §3.
///
/// Desktop Flutter has no cookie jar, so the token from the login response
/// body (PORTING.md §0) is stored here and attached as
/// `Authorization: Bearer <jwt>` by `ApiClient`.
///
/// The concrete [`SecureTokenStorage`] uses flutter_secure_storage (libsecret
/// on Linux). The interface exists so tests can inject an in-memory fake:
/// flutter_secure_storage's Linux FFI blocks waiting for the system keyring
/// daemon, which doesn't exist under `flutter test`.
abstract class TokenStorage {
  Future<String?> readToken();

  Future<void> writeToken(String token);

  Future<void> clear();
}

class SecureTokenStorage implements TokenStorage {
  const SecureTokenStorage();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _tokenKey = 'auth_token';

  @override
  Future<String?> readToken() => _storage.read(key: _tokenKey);

  @override
  Future<void> writeToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  @override
  Future<void> clear() => _storage.delete(key: _tokenKey);
}

/// Riverpod provider — overridden in tests with an in-memory fake.
final tokenStorageProvider = Provider<TokenStorage>(
  (ref) => const SecureTokenStorage(),
);
