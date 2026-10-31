import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/core/app_support_paths.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// Temporary fake XDG data home so tests never touch the real user data
/// under ~/.local/share.
Directory _tempDataHome() {
  final dir = Directory.systemTemp.createTempSync('minierp-prefs-test-');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

Map<String, String> _env(Directory dataHome) => <String, String>{
      'XDG_DATA_HOME': dataHome.path,
      'HOME': dataHome.path,
    };

void main() {
  group('AppSupportPaths.baseDir', () {
    test('honors XDG_DATA_HOME', () {
      final home = _tempDataHome();
      final base = AppSupportPaths.baseDir(_env(home));
      expect(base, p.join(home.path, 'minierp'));
    });

    test('falls back to ~/.local/share when XDG_DATA_HOME is unset', () {
      final home = _tempDataHome();
      final env = <String, String>{'HOME': home.path};
      expect(AppSupportPaths.baseDir(env),
          p.join(home.path, '.local', 'share', 'minierp'));
    });

    test('treats an empty XDG_DATA_HOME as unset', () {
      final home = _tempDataHome();
      final env = <String, String>{'XDG_DATA_HOME': '', 'HOME': home.path};
      expect(AppSupportPaths.baseDir(env),
          p.join(home.path, '.local', 'share', 'minierp'));
    });
  });

  group('AppSupportPaths.migratePreferences', () {
    test('is a no-op without a legacy file', () {
      final home = _tempDataHome();
      AppSupportPaths.migratePreferences(environment: _env(home));
      expect(File(p.join(home.path, 'minierp', 'shared_preferences.json'))
          .existsSync(), isFalse);
    });

    test('moves the legacy file into the minierp folder and removes the '
        'legacy folder', () {
      final home = _tempDataHome();
      final legacyDir = p.join(home.path, 'com.example.minierp_app');
      final legacy = File(p.join(legacyDir, 'shared_preferences.json'));
      legacy.parent.createSync(recursive: true);
      const legacyContent = '{"flutter.theme_name":"dark"}';
      legacy.writeAsStringSync(legacyContent);

      AppSupportPaths.migratePreferences(environment: _env(home));

      final moved = File(p.join(home.path, 'minierp', 'shared_preferences.json'));
      expect(moved.existsSync(), isTrue);
      expect(moved.readAsStringSync(), legacyContent);
      expect(legacy.existsSync(), isFalse);
      expect(Directory(legacyDir).existsSync(), isFalse);
    });

    test('migrates the com.example.minierp id folder as well', () {
      final home = _tempDataHome();
      final legacyDir = p.join(home.path, 'com.example.minierp');
      final legacy = File(p.join(legacyDir, 'shared_preferences.json'));
      legacy.parent.createSync(recursive: true);
      legacy.writeAsStringSync('{"flutter.theme_name":"dark"}');

      AppSupportPaths.migratePreferences(environment: _env(home));

      final moved =
          File(p.join(home.path, 'minierp', 'shared_preferences.json'));
      expect(moved.existsSync(), isTrue);
      expect(moved.readAsStringSync(), '{"flutter.theme_name":"dark"}');
      expect(legacy.existsSync(), isFalse);
      expect(Directory(legacyDir).existsSync(), isFalse);
    });

    test('migrates when both legacy id folders exist', () {
      final home = _tempDataHome();
      final oldDir = p.join(home.path, 'com.example.minierp_app');
      File(p.join(oldDir, 'shared_preferences.json'))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('{"flutter.theme_name":"dark"}');
      final newIdDir = p.join(home.path, 'com.example.minierp');
      File(p.join(newIdDir, 'shared_preferences.json'))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('{"flutter.stale":"new-id-default"}');

      AppSupportPaths.migratePreferences(environment: _env(home));

      final moved =
          File(p.join(home.path, 'minierp', 'shared_preferences.json'));
      expect(moved.existsSync(), isTrue);
      expect(moved.readAsStringSync(), '{"flutter.theme_name":"dark"}');
      expect(Directory(oldDir).existsSync(), isFalse);
      expect(Directory(newIdDir).existsSync(), isFalse);
    });

    test('removes a stale legacy file when the minierp file already exists',
        () {
      final home = _tempDataHome();
      final legacyDir = p.join(home.path, 'com.example.minierp_app');
      final legacy = File(p.join(legacyDir, 'shared_preferences.json'));
      legacy.parent.createSync(recursive: true);
      legacy.writeAsStringSync('{"flutter.stale":"legacy"}');

      const targetContent = '{"flutter.theme_name":"light"}';
      final target = File(p.join(home.path, 'minierp', 'shared_preferences.json'));
      target.parent.createSync(recursive: true);
      target.writeAsStringSync(targetContent);

      AppSupportPaths.migratePreferences(environment: _env(home));

      expect(target.readAsStringSync(), targetContent);
      expect(legacy.existsSync(), isFalse);
      expect(Directory(legacyDir).existsSync(), isFalse);
    });

    test('does not delete the legacy folder when it holds other files', () {
      final home = _tempDataHome();
      final legacyDir = Directory(
          p.join(home.path, 'com.example.minierp_app'));
      legacyDir.createSync(recursive: true);
      File(p.join(legacyDir.path, 'shared_preferences.json'))
          .writeAsStringSync('{"flutter.a":"1"}');
      final other = File(p.join(legacyDir.path, 'other.txt'));
      other.writeAsStringSync('keep me');

      AppSupportPaths.migratePreferences(environment: _env(home));

      expect(
          File(p.join(home.path, 'minierp', 'shared_preferences.json'))
              .existsSync(),
          isTrue);
      expect(other.existsSync(), isTrue);
      expect(legacyDir.existsSync(), isTrue);
    });

    test('is idempotent when nothing is left to migrate', () {
      final home = _tempDataHome();
      final migrated = File(
          p.join(home.path, 'minierp', 'shared_preferences.json'));
      migrated.parent.createSync(recursive: true);
      migrated.writeAsStringSync('{"flutter.a":"1"}');

      AppSupportPaths.migratePreferences(environment: _env(home));

      expect(migrated.existsSync(), isTrue);
    });
  });

  group('MiniErpPathProviderLinux', () {
    test('returns and creates the minierp app-support folder', () async {
      final home = _tempDataHome();
      final provider = MiniErpPathProviderLinux(environment: _env(home));
      final support = await provider.getApplicationSupportPath();
      expect(support, p.join(home.path, 'minierp'));
      expect(Directory(support!).existsSync(), isTrue);
    });

    test('shared_preferences writes land in the minierp folder', () async {
      final home = _tempDataHome();
      final previousStore = SharedPreferencesStorePlatform.instance;
      addTearDown(() => SharedPreferencesStorePlatform.instance = previousStore);

      AppSupportPaths.installPreferencesOverride(environment: _env(home));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('theme_name', 'dark');

      final reopened = await SharedPreferences.getInstance();
      expect(reopened.getString('theme_name'), 'dark');

      final file =
          File(p.join(home.path, 'minierp', 'shared_preferences.json'));
      expect(file.existsSync(), isTrue);
      expect(jsonDecode(file.readAsStringSync()),
          containsPair('flutter.theme_name', 'dark'));
    });
  });
}
