import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider_linux/path_provider_linux.dart';
import 'package:shared_preferences_linux/shared_preferences_linux.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// Shared-preferences storage locations on Linux.
///
/// `path_provider_linux` derives the app-support directory from the
/// application id, so shared_preferences used to live in
/// `$XDG_DATA_HOME/com.example.minierp_app/shared_preferences.json` — a
/// folder named after the build id, separate from every other per-user file.
/// This module parks the store in the minierp data family instead:
///
///   ~/.local/share/minierp/shared_preferences.json   (preferences)
///   ~/.local/share/minierp/data/database/erp.db      (BackendPaths)
///
/// and migrates the legacy app-id file in one idempotent boot step.
class AppSupportPaths {
  const AppSupportPaths._();

  static const String _legacyAppId = 'com.example.minierp_app';
  static const String _prefsFileName = 'shared_preferences.json';

  /// XDG user data home: `$XDG_DATA_HOME` or `~/.local/share`.
  static String dataHome(Map<String, String> environment) {
    final xdg = environment['XDG_DATA_HOME'];
    if (xdg != null && xdg.isNotEmpty) return xdg;
    final home = environment['HOME'] ?? '';
    if (home.isEmpty) {
      throw StateError('Neither XDG_DATA_HOME nor HOME is set');
    }
    return p.join(home, '.local', 'share');
  }

  /// The minierp data-family root the preferences store lives in.
  static String baseDir(Map<String, String> environment) =>
      p.join(dataHome(environment), 'minierp');

  /// Where shared_preferences stores its key/value file after the override.
  static String preferencesFile(Map<String, String> environment) =>
      p.join(baseDir(environment), _prefsFileName);

  /// Where shared_preferences stored the file before the override
  /// (`<data home>/<application id>/shared_preferences.json`).
  static String legacyPreferencesFile(Map<String, String> environment) =>
      p.join(dataHome(environment), _legacyAppId, _prefsFileName);

  /// Moves the legacy app-id preferences file into the minierp folder.
  ///
  /// Runs on every Linux boot, before the first SharedPreferences access.
  /// Idempotent and tolerant:
  ///   - no legacy file -> nothing happens (the target folder is not even
  ///     created; the store creates it lazily);
  ///   - legacy file and target file both exist -> the legacy file is stale
  ///     (the store only ever reads the new location), so it is removed and
  ///     the new file is kept;
  ///   - the legacy folder is only deleted when the migration leaves it empty,
  ///     so unrelated files are never touched.
  static void migratePreferences({Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    final legacy = File(legacyPreferencesFile(env));
    if (!legacy.existsSync()) return;

    try {
      final target = File(preferencesFile(env));
      if (!target.existsSync()) {
        target.parent.createSync(recursive: true);
        legacy.copySync(target.path);
      }
      legacy.deleteSync();
    } on FileSystemException {
      // Migration is best-effort: if the copy or delete fails, keep the
      // legacy file so no preferences are lost; the app still boots with
      // defaults.
      return;
    }

    final legacyDir = legacy.parent;
    try {
      if (legacyDir.existsSync() && legacyDir.listSync().isEmpty) {
        legacyDir.deleteSync();
      }
    } on FileSystemException {
      // Folder cleanup is cosmetic; ignore failures.
    }
  }

  /// Redirects the Linux shared_preferences store to the minierp folder.
  ///
  /// The store builds its own `PathProviderLinux` instance (it does not go
  /// through `PathProviderPlatform.instance`), so the store instance itself
  /// has to be replaced and pointed at a relocated path provider. Must run
  /// before the first SharedPreferences access.
  static void installPreferencesOverride({Map<String, String>? environment}) {
    final store = SharedPreferencesLinux()
      // `pathProvider` is the plugin's sanctioned seam for deciding where the
      // store lives; relocating it app-wide is a legitimate production use.
      // ignore: invalid_use_of_visible_for_testing_member
      ..pathProvider = MiniErpPathProviderLinux(environment: environment);
    SharedPreferencesStorePlatform.instance = store;
  }
}

/// `PathProviderLinux` that parks the app-support directory in the minierp
/// data-family folder instead of `com.example.minierp_app`.
///
/// A custom environment map is accepted directly (the base constructor
/// marked `@visibleForTesting` is not callable across packages) so tests can
/// inject a temporary XDG data home.
class MiniErpPathProviderLinux extends PathProviderLinux {
  MiniErpPathProviderLinux({Map<String, String>? environment})
      : _environment = environment ?? Platform.environment;

  final Map<String, String> _environment;

  @override
  Future<String?> getApplicationSupportPath() async {
    final dir = Directory(AppSupportPaths.baseDir(_environment));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir.path;
  }
}
