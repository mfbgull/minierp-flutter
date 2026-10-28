import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Client-side counterpart of server/src/utils/passwordPolicy.ts and the
/// persisted secrets a packaged install needs.
class BackendConfig {
  const BackendConfig._();

  static const int minPasswordCharacters = 12;
  static const int maxPasswordBytes = 72;

  static String? passwordPolicyError(String password) {
    if (password.runes.length < minPasswordCharacters) {
      return 'Password must be at least $minPasswordCharacters characters long';
    }
    if (utf8.encode(password).length > maxPasswordBytes) {
      return 'Password must not exceed $maxPasswordBytes UTF-8 bytes';
    }
    return null;
  }

  /// 32 random bytes as lowercase hex (64 characters).
  static String generateJwtSecret() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Reads the persisted signing secret or creates it on first launch.
  ///
  /// The secret must stay stable: tokens and settings encrypted with
  /// ENCRYPTION_KEY (which falls back to JWT_SECRET) stop working if it
  /// changes. A corrupt short value is surfaced instead of silently replaced.
  ///
  /// [legacyEnvFile] is consulted only while no secret file exists, so an
  /// upgraded install keeps the JWT_SECRET it migrated from its old layout.
  static String readOrCreateJwtSecret(String path, {String? legacyEnvFile}) {
    final file = File(path);
    if (file.existsSync()) {
      final value = file.readAsStringSync().trim();
      if (value.length < 32) {
        throw FormatException('JWT secret file is corrupt: $path');
      }
      return value;
    }

    final legacy =
        legacyEnvFile == null ? null : _jwtSecretFromEnv(legacyEnvFile);
    final secret = legacy ?? generateJwtSecret();
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(secret, flush: true);
    _restrictPermissions(path);
    return secret;
  }

  static String? _jwtSecretFromEnv(String path) {
    final file = File(path);
    if (!file.existsSync()) return null;
    for (final line in file.readAsLinesSync()) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('JWT_SECRET=')) continue;
      var value = trimmed.substring('JWT_SECRET='.length).trim();
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      return value.length >= 32 ? value : null;
    }
    return null;
  }

  static void _restrictPermissions(String path) {
    if (Platform.isWindows) return;
    try {
      Process.runSync('chmod', ['600', path]);
    } catch (_) {
      // Best effort; the data directory is already user-scoped.
    }
  }
}
