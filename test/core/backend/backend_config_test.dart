import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/core/backend/backend_config.dart';
import 'package:path/path.dart' as p;

void main() {
  group('password policy', () {
    test('rejects passwords shorter than 12 characters', () {
      expect(BackendConfig.passwordPolicyError('short'), isNotNull);
      expect(BackendConfig.passwordPolicyError('elevenchars'), isNotNull);
    });

    test('accepts a 12-character password', () {
      expect(BackendConfig.passwordPolicyError('twelvechars!'), isNull);
    });

    test('rejects values over 72 UTF-8 bytes', () {
      // 25 three-byte characters: 25 * 3 = 75 bytes.
      final password = '€' * 25;
      expect(BackendConfig.passwordPolicyError(password), isNotNull);
    });
  });

  group('JWT secret', () {
    late Directory temp;

    setUp(() => temp = Directory.systemTemp.createTempSync('minierp_secret_'));
    tearDown(() => temp.deleteSync(recursive: true));

    test('generates 64 hex characters', () {
      final secret = BackendConfig.generateJwtSecret();
      expect(secret, hasLength(64));
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(secret), isTrue);
    });

    test('creates the secret once and reuses it', () {
      final path = p.join(temp.path, 'server', 'jwt.secret');
      final first = BackendConfig.readOrCreateJwtSecret(path);
      final second = BackendConfig.readOrCreateJwtSecret(path);
      expect(second, first);
      expect(File(path).readAsStringSync().trim(), first);
    });

    test('surfaces a corrupt secret instead of silently replacing it', () {
      final path = p.join(temp.path, 'jwt.secret');
      File(path).writeAsStringSync('too-short');
      expect(
        () => BackendConfig.readOrCreateJwtSecret(path),
        throwsFormatException,
      );
    });

    test('adopts the migrated .env secret so encryption keys survive upgrade', () {
      // Upgrading a legacy .run install migrates <dir>/server/.env into
      // <dir>/data/.env. Regenerating the secret would orphan everything
      // encrypted with the JWT_SECRET-derived ENCRYPTION_KEY.
      final legacy = 'a' * 64;
      final envFile = p.join(temp.path, '.env');
      File(envFile).writeAsStringSync(
        'NODE_ENV=production\nJWT_SECRET=$legacy\nDATABASE_PATH=/x\n',
      );
      final path = p.join(temp.path, 'server', 'jwt.secret');

      final secret = BackendConfig.readOrCreateJwtSecret(
        path,
        legacyEnvFile: envFile,
      );

      expect(secret, legacy);
      expect(File(path).readAsStringSync().trim(), legacy);
    });

    test('ignores a short legacy env secret and generates a fresh one', () {
      final envFile = p.join(temp.path, '.env');
      File(envFile).writeAsStringSync('JWT_SECRET=short\n');
      final path = p.join(temp.path, 'server', 'jwt.secret');

      final secret = BackendConfig.readOrCreateJwtSecret(
        path,
        legacyEnvFile: envFile,
      );

      expect(secret, isNot('short'));
      expect(secret, hasLength(64));
    });
  });
}
