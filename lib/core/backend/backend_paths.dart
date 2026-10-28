import 'dart:io';

import 'package:path/path.dart' as p;

/// Desktop OS the packaged backend runs on. Injectable so the path rules are
/// unit-testable off their host platform.
enum BackendPlatform {
  linux,
  macos,
  windows;

  static BackendPlatform get current {
    if (Platform.isWindows) return BackendPlatform.windows;
    if (Platform.isMacOS) return BackendPlatform.macos;
    return BackendPlatform.linux;
  }
}

/// Locations of the bundled server, its runtime, and writable user data.
///
/// The install tree is read-only on every packaged platform (Program Files,
/// /usr/lib, an AppImage mount, an .app bundle), so the database, uploads,
/// logs and secrets all live under a per-user data directory.
class BackendPaths {
  const BackendPaths._();

  static String runtimeBinaryName(BackendPlatform platform) =>
      platform == BackendPlatform.windows ? 'node.exe' : 'node';

  /// Finds the bundled server next to the client executable.
  ///
  /// Supported layouts:
  ///   Linux .deb / AppImage  `<exeDir>/server`
  ///   Linux .run             `<exeDir>/../server`
  ///   Windows                `<exeDir>/server`
  ///   macOS                  `Contents/Resources/server`
  /// Returns null in development, where the server is started externally.
  /// Path separator context of the target OS (not the host running the
  /// test), so the Windows layout is verifiable from Linux CI.
  static p.Context _context(BackendPlatform platform) =>
      platform == BackendPlatform.windows ? p.windows : p.posix;

  static String? findServerDir({
    required String executablePath,
    required BackendPlatform platform,
    bool Function(String path)? exists,
  }) {
    final check = exists ?? (path) => File(path).existsSync();
    final paths = _context(platform);
    final exeDir = paths.dirname(executablePath);
    final candidates = <String>[
      if (platform == BackendPlatform.macos)
        paths.normalize(paths.join(exeDir, '..', 'Resources', 'server')),
      paths.join(exeDir, 'server'),
      paths.normalize(paths.join(exeDir, '..', 'server')),
    ];
    final runtime = runtimeBinaryName(platform);

    for (final dir in candidates) {
      if (check(paths.join(dir, 'dist', 'server.js')) &&
          check(paths.join(dir, 'runtime', runtime))) {
        return dir;
      }
    }
    return null;
  }

  static String resolveDataDir({
    required BackendPlatform platform,
    required Map<String, String> environment,
  }) {
    // The .run launcher installs under a user-chosen directory and exports
    // this so data lives beside (not inside) the replaced app tree.
    final override = environment['MINIERP_DATA_DIR'];
    if (override != null && override.isNotEmpty) return override;

    final paths = _context(platform);
    switch (platform) {
      case BackendPlatform.windows:
        final base = environment['LOCALAPPDATA'] ?? environment['APPDATA'];
        if (base == null || base.isEmpty) {
          throw StateError('LOCALAPPDATA is not set');
        }
        return paths.join(base, 'MiniERP', 'data');
      case BackendPlatform.macos:
        final home = environment['HOME'];
        if (home == null || home.isEmpty) throw StateError('HOME is not set');
        return paths.join(
          home,
          'Library',
          'Application Support',
          'MiniERP',
          'data',
        );
      case BackendPlatform.linux:
        final xdg = environment['XDG_DATA_HOME'];
        if (xdg != null && xdg.isNotEmpty) {
          return paths.join(xdg, 'minierp', 'data');
        }
        final home = environment['HOME'];
        if (home == null || home.isEmpty) throw StateError('HOME is not set');
        return paths.join(home, '.local', 'share', 'minierp', 'data');
    }
  }

  static String databaseDir(String dataDir) => p.join(dataDir, 'database');
  static String uploadsDir(String dataDir) => p.join(dataDir, 'uploads');
  static String logsDir(String dataDir) => p.join(dataDir, 'logs');
  static String backupsDir(String dataDir) => p.join(dataDir, 'backups');
  static String serverStateDir(String dataDir) => p.join(dataDir, 'server');
  static String envFile(String dataDir) => p.join(dataDir, '.env');
  static String portFile(String dataDir) => p.join(dataDir, 'server.port');
  static String pidFile(String dataDir) => p.join(dataDir, 'server.pid');
  static String lockFile(String dataDir) => p.join(dataDir, 'instance.lock');
  static String jwtSecretFile(String dataDir) =>
      p.join(serverStateDir(dataDir), 'jwt.secret');
  static String consoleLogFile(String dataDir) =>
      p.join(logsDir(dataDir), 'server-console.log');

  static String apiBaseUrl(int port) => 'http://127.0.0.1:$port/api';
  static String healthUrl(int port) => 'http://127.0.0.1:$port/health';
}
