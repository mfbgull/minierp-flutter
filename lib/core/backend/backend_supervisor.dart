import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../api/api_client.dart';
import 'backend_config.dart';
import 'backend_paths.dart';

/// Lifecycle of the local backend from the Flutter app's point of view.
///
/// [external] is the development case: no bundled server was found, so the
/// compile-time `API_BASE_URL` (usually the 3011 dev server) is used.
enum BackendStatus { idle, needsSetup, starting, ready, external, failed }

class BackendState {
  const BackendState({
    required this.status,
    this.port,
    this.dataDir,
    this.serverDir,
    this.logPath,
    this.message,
    this.detail,
  });

  final BackendStatus status;
  final int? port;
  final String? dataDir;
  final String? serverDir;
  final String? logPath;

  /// Short, user-facing reason (also a stable code the splash screen maps to
  /// a localized message).
  final String? message;

  /// Technical detail for the failure screen. Never rendered raw to end
  /// users; shown in the copied diagnostics next to the log path.
  final String? detail;

  bool get isReady =>
      status == BackendStatus.ready || status == BackendStatus.external;
}

/// Minimal process handle so tests can drive the supervisor without spawning
/// Node.
abstract class BackendProcessHandle {
  int get pid;
  Stream<List<int>> get stdout;
  Stream<List<int>> get stderr;
  Future<int> get exitCode;
}

class _NativeProcessHandle implements BackendProcessHandle {
  _NativeProcessHandle(this._process);

  final Process _process;

  @override
  int get pid => _process.pid;

  @override
  Stream<List<int>> get stdout => _process.stdout;

  @override
  Stream<List<int>> get stderr => _process.stderr;

  @override
  Future<int> get exitCode => _process.exitCode;
}

typedef BackendProcessStarter =
    Future<BackendProcessHandle> Function({
      required String executable,
      required List<String> arguments,
      required String workingDirectory,
      required Map<String, String> environment,
    });

typedef BackendHealthProbe = Future<bool> Function(String url);
typedef BackendPidCheck = bool Function(int pid);
typedef BackendFileExists = bool Function(String path);
typedef BackendProcessKiller = void Function(int pid, {bool force});

Future<BackendProcessHandle> _startNativeProcess({
  required String executable,
  required List<String> arguments,
  required String workingDirectory,
  required Map<String, String> environment,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
  );
  return _NativeProcessHandle(process);
}

Future<bool> _defaultHealthProbe(String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close().timeout(const Duration(seconds: 3));
    await response.drain<void>();
    return response.statusCode == 200;
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}

void _defaultKill(int pidValue, {bool force = false}) {
  try {
    if (Platform.isWindows) {
      Process.killPid(pidValue);
    } else {
      Process.killPid(
        pidValue,
        force ? ProcessSignal.sigkill : ProcessSignal.sigterm,
      );
    }
  } on ProcessException {
    // Already gone.
  }
}

/// Cross-platform "is this pid alive" without sending a signal.
bool _defaultPidCheck(int pidValue) {
  if (pidValue <= 0) return false;
  try {
    if (Platform.isWindows) {
      final result = Process.runSync('tasklist', [
        '/FI',
        'PID eq $pidValue',
        '/NH',
      ]);
      return result.exitCode == 0 && '${result.stdout}'.contains('$pidValue');
    }
    return Process.runSync('kill', ['-0', '$pidValue']).exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// Owns the bundled Node backend for a packaged install.
///
/// State machine: `idle → needsSetup → starting → ready`, or `failed`.
/// In development no bundled server exists and the state becomes `external`.
///
/// The server binds an ephemeral port (`PORT=0`) and writes it to
/// `PORT_FILE`; [initialize] waits for that file, probes `/health`, then sets
/// the shared [ApiClient] base URL before the first auth request runs.
class BackendSupervisor extends StateNotifier<BackendState> {
  BackendSupervisor({
    BackendProcessStarter? processStarter,
    BackendHealthProbe? healthProbe,
    BackendPidCheck? pidCheck,
    BackendFileExists? fileExists,
    BackendProcessKiller? processKiller,
    BackendPlatform? platform,
    Map<String, String>? environment,
    String? executablePath,
    this.serverDirOverride,
    this.dataDirOverride,
    this.hiddenWindowsLaunch = true,
    this.startupTimeout = const Duration(seconds: 25),
    this.pollInterval = const Duration(milliseconds: 250),
    this.shutdownTimeout = const Duration(seconds: 8),
  }) : _processStarter = processStarter ?? _startNativeProcess,
       _healthProbe = healthProbe ?? _defaultHealthProbe,
       _pidCheck = pidCheck ?? _defaultPidCheck,
       _fileExists = fileExists ?? ((path) => File(path).existsSync()),
       _processKiller = processKiller ?? _defaultKill,
       _platform = platform ?? BackendPlatform.current,
       _environment = environment ?? Platform.environment,
       _executablePath = executablePath ?? Platform.resolvedExecutable,
       super(const BackendState(status: BackendStatus.idle));

  final BackendProcessStarter _processStarter;
  final BackendHealthProbe _healthProbe;
  final BackendPidCheck _pidCheck;
  final BackendFileExists _fileExists;
  final BackendProcessKiller _processKiller;
  final BackendPlatform _platform;
  final Map<String, String> _environment;
  final String _executablePath;
  final String? serverDirOverride;
  final String? dataDirOverride;
  final bool hiddenWindowsLaunch;

  final Duration startupTimeout;
  final Duration pollInterval;
  final Duration shutdownTimeout;

  Future<void>? _inFlight;
  String? _pendingAdminPassword;
  int? _serverPid;
  bool _ownsServer = false;
  bool _lockHeld = false;
  bool _shuttingDown = false;
  bool _monitorExit = false;
  bool _processExited = false;
  Timer? _livenessTimer;
  IOSink? _consoleSink;

  /// Boots (or adopts) the backend. Safe to call repeatedly.
  Future<void> initialize() {
    final running = _inFlight;
    if (running != null) return running;
    if (state.isReady) return Future<void>.value();
    final future = _initialize();
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
  }

  /// First-run path: the password travels to the server only through this
  /// process's environment and is never written to disk.
  Future<void> submitAdminPassword(String password) async {
    final error = BackendConfig.passwordPolicyError(password);
    if (error != null) throw ArgumentError(error);
    _pendingAdminPassword = password;
    await initialize();
  }

  Future<void> _initialize() async {
    final String? serverDir;
    try {
      serverDir =
          serverDirOverride ??
          BackendPaths.findServerDir(
            executablePath: _executablePath,
            platform: _platform,
            exists: _fileExists,
          );
    } catch (error) {
      _fail('paths', error);
      return;
    }

    if (serverDir == null) {
      final base = ApiClient.configuredBaseUrl.isNotEmpty
          ? ApiClient.configuredBaseUrl
          : ApiClient.defaultBaseUrl;
      ApiClient.setBaseUrl(base);
      state = BackendState(
        status: BackendStatus.external,
        port: _portFromBaseUrl(base),
        message: 'external',
      );
      return;
    }

    final String dataDir;
    try {
      dataDir =
          dataDirOverride ??
          BackendPaths.resolveDataDir(
            platform: _platform,
            environment: _environment,
          );
      _prepareDataDirs(dataDir);
    } catch (error) {
      _fail('paths', error, serverDir: serverDir);
      return;
    }

    final String secret;
    try {
      secret = BackendConfig.readOrCreateJwtSecret(
        BackendPaths.jwtSecretFile(dataDir),
        legacyEnvFile: BackendPaths.envFile(dataDir),
      );
    } catch (error) {
      _fail('secret', error, serverDir: serverDir, dataDir: dataDir);
      return;
    }
    _writeEnvFile(dataDir, secret);

    final consoleLog = BackendPaths.consoleLogFile(dataDir);
    final databaseExists = _fileExists(
      p.join(BackendPaths.databaseDir(dataDir), 'erp.db'),
    );
    if (!databaseExists && _pendingAdminPassword == null) {
      state = BackendState(
        status: BackendStatus.needsSetup,
        dataDir: dataDir,
        serverDir: serverDir,
        logPath: consoleLog,
      );
      return;
    }

    if (!await _claimLock(dataDir)) {
      if (await _tryAdopt(dataDir, serverDir, consoleLog)) return;
      _setFailed(
        'alreadyRunning',
        'Another MiniERP instance holds ${BackendPaths.lockFile(dataDir)}',
        serverDir: serverDir,
        dataDir: dataDir,
        logPath: consoleLog,
      );
      return;
    }

    // A previous app process may have left a healthy server behind.
    if (await _tryAdopt(dataDir, serverDir, consoleLog)) return;

    _removeRuntimeFiles(dataDir);
    _processExited = false;
    state = BackendState(
      status: BackendStatus.starting,
      dataDir: dataDir,
      serverDir: serverDir,
      logPath: consoleLog,
    );

    final environment = _buildEnvironment(
      dataDir: dataDir,
      secret: secret,
      adminPassword: _pendingAdminPassword,
    );
    final runtime = p.join(
      serverDir,
      'runtime',
      BackendPaths.runtimeBinaryName(_platform),
    );
    final serverScript = p.join(serverDir, 'dist', 'server.js');

    final BackendProcessHandle handle;
    try {
      final hiddenWindows =
          _platform == BackendPlatform.windows && hiddenWindowsLaunch;
      if (hiddenWindows) {
        _monitorExit = false;
        handle = await _launchWindowsHidden(
          runtime: runtime,
          serverScript: serverScript,
          dataDir: dataDir,
          consoleLog: consoleLog,
          environment: environment,
        );
      } else {
        _monitorExit = true;
        handle = await _processStarter(
          executable: runtime,
          arguments: [serverScript],
          workingDirectory: dataDir,
          environment: environment,
        );
        _captureConsole(handle, consoleLog);
      }
      if (_monitorExit) {
        _watchExit(handle, dataDir, serverDir, consoleLog);
      }
    } catch (error) {
      _fail(
        'launch',
        error,
        serverDir: serverDir,
        dataDir: dataDir,
        logPath: consoleLog,
      );
      _releaseLock();
      return;
    }

    final port = await _awaitHealthy(
      handle: handle,
      dataDir: dataDir,
      consoleLog: consoleLog,
    );
    if (port == null) return;

    _serverPid = _monitorExit ? handle.pid : _readPid(dataDir);
    _ownsServer = true;
    _pendingAdminPassword = null;
    ApiClient.setBaseUrl(BackendPaths.apiBaseUrl(port));
    state = BackendState(
      status: BackendStatus.ready,
      port: port,
      dataDir: dataDir,
      serverDir: serverDir,
      logPath: consoleLog,
    );
    if (!_monitorExit) _startLivenessMonitor();
  }

  Future<int?> _awaitHealthy({
    required BackendProcessHandle handle,
    required String dataDir,
    required String consoleLog,
  }) async {
    final deadline = DateTime.now().add(startupTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final port = _readPort(dataDir);
      if (port != null && await _healthProbe(BackendPaths.healthUrl(port))) {
        return port;
      }
      if (_monitorExit && _processExited) break;
      await Future<void>.delayed(pollInterval);
    }
    if (state.isReady) return state.port;
    _handleStartupFailure(dataDir: dataDir, consoleLog: consoleLog);
    return null;
  }

  void _watchExit(
    BackendProcessHandle handle,
    String dataDir,
    String serverDir,
    String consoleLog,
  ) {
    unawaited(
      handle.exitCode.then((code) {
        _processExited = true;
        if (_shuttingDown) return;
        if (state.status == BackendStatus.ready) {
          _serverStopped(serverDir, dataDir, consoleLog, code);
          return;
        }
        if (state.status == BackendStatus.starting) {
          _handleStartupFailure(
            dataDir: dataDir,
            consoleLog: consoleLog,
            exitCode: code,
          );
        }
      }),
    );
  }

  void _handleStartupFailure({
    required String dataDir,
    required String consoleLog,
    int? exitCode,
  }) {
    final tail = _readLogTail(consoleLog);
    if (tail.contains('DEFAULT_ADMIN_PASSWORD') &&
        _pendingAdminPassword == null) {
      // The database exists but has no admin row (settings were reset or the
      // DB was replaced): fall back to first-run setup.
      state = BackendState(
        status: BackendStatus.needsSetup,
        dataDir: dataDir,
        serverDir: state.serverDir,
        logPath: consoleLog,
      );
      _releaseLock();
      return;
    }
    final reason = tail.isEmpty
        ? 'The bundled server did not become ready.'
        : tail.split('\n').where((line) => line.trim().isNotEmpty).last;
    _setFailed(
      'startup',
      exitCode == null ? reason : 'Server exited with code $exitCode: $reason',
      serverDir: state.serverDir,
      dataDir: dataDir,
      logPath: consoleLog,
    );
    _releaseLock();
  }

  void _serverStopped(
    String serverDir,
    String dataDir,
    String consoleLog,
    int code,
  ) {
    if (_shuttingDown) return;
    _livenessTimer?.cancel();
    _setFailed(
      'stopped',
      'The bundled server stopped unexpectedly (exit code $code).',
      serverDir: serverDir,
      dataDir: dataDir,
      logPath: consoleLog,
    );
    _releaseLock();
  }

  /// Stops a server this supervisor started. An adopted server is left alone:
  /// its own app instance (or the parent watchdog) owns it.
  Future<void> shutdown() async {
    if (_shuttingDown) return;
    _shuttingDown = true;
    _livenessTimer?.cancel();
    try {
      final serverPid = _serverPid;
      if (_ownsServer && serverPid != null && _pidCheck(serverPid)) {
        _processKiller(serverPid, force: false);
        final deadline = DateTime.now().add(shutdownTimeout);
        while (DateTime.now().isBefore(deadline) && _pidCheck(serverPid)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        if (_pidCheck(serverPid)) _processKiller(serverPid, force: true);
      }
      final dataDir = state.dataDir;
      if (dataDir != null) _removeRuntimeFiles(dataDir);
      await _consoleSink?.flush();
      await _consoleSink?.close();
      _consoleSink = null;
      _releaseLock();
      _serverPid = null;
      _ownsServer = false;
      _monitorExit = false;
      state = BackendState(status: BackendStatus.idle, dataDir: dataDir);
    } finally {
      _shuttingDown = false;
    }
  }

  // --- instance lock -------------------------------------------------------

  /// Exclusive file claim (`createSync(exclusive: true)` is atomic). A stale
  /// claim from a crashed process is removed once its pid is gone.
  Future<bool> _claimLock(String dataDir) async {
    if (_lockHeld) return true;
    final lockFile = File(BackendPaths.lockFile(dataDir));
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        lockFile.createSync(exclusive: true);
        lockFile.writeAsStringSync('$pid', flush: true);
        _lockHeld = true;
        return true;
      } on FileSystemException {
        var holder = _readLockPid(lockFile.path);
        if (holder == pid) {
          _lockHeld = true;
          return true;
        }
        if (holder == null) {
          // The winner may have created the file but not written its pid
          // yet; give it a moment before deciding the claim is stale.
          await Future<void>.delayed(const Duration(milliseconds: 100));
          holder = _readLockPid(lockFile.path);
          if (holder != null && holder != pid && _pidCheck(holder)) {
            return false;
          }
          if (holder == pid) {
            _lockHeld = true;
            return true;
          }
        } else if (_pidCheck(holder)) {
          return false;
        }
        try {
          lockFile.deleteSync();
        } catch (_) {
          return false;
        }
      }
    }
    return false;
  }

  int? _readLockPid(String lockPath) {
    try {
      return int.tryParse(File(lockPath).readAsStringSync().trim());
    } catch (_) {
      return null;
    }
  }

  void _releaseLock() {
    if (!_lockHeld) return;
    _lockHeld = false;
    final dataDir = state.dataDir;
    if (dataDir == null) return;
    try {
      File(BackendPaths.lockFile(dataDir)).deleteSync();
    } catch (_) {
      // Already gone.
    }
  }

  // --- adoption ------------------------------------------------------------

  Future<bool> _tryAdopt(
    String dataDir,
    String serverDir,
    String consoleLog,
  ) async {
    final serverPid = _readPid(dataDir);
    final port = _readPort(dataDir);
    if (serverPid == null || port == null) return false;
    if (!_pidCheck(serverPid)) return false;
    if (!await _healthProbe(BackendPaths.healthUrl(port))) return false;

    _serverPid = serverPid;
    _ownsServer = false;
    ApiClient.setBaseUrl(BackendPaths.apiBaseUrl(port));
    state = BackendState(
      status: BackendStatus.ready,
      port: port,
      dataDir: dataDir,
      serverDir: serverDir,
      logPath: consoleLog,
      message: 'adopted',
    );
    _startLivenessMonitor();
    return true;
  }

  void _startLivenessMonitor() {
    _livenessTimer?.cancel();
    _livenessTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final serverPid = _serverPid;
      if (_shuttingDown || serverPid == null || !state.isReady) return;
      if (_pidCheck(serverPid)) return;
      _livenessTimer?.cancel();
      final dataDir = state.dataDir;
      final serverDir = state.serverDir;
      final logPath = state.logPath;
      _setFailed(
        'stopped',
        'The bundled server is no longer running.',
        serverDir: serverDir,
        dataDir: dataDir,
        logPath: logPath,
      );
      _releaseLock();
    });
  }

  // --- helpers -------------------------------------------------------------

  void _prepareDataDirs(String dataDir) {
    Directory(BackendPaths.databaseDir(dataDir)).createSync(recursive: true);
    Directory(BackendPaths.uploadsDir(dataDir)).createSync(recursive: true);
    Directory(BackendPaths.logsDir(dataDir)).createSync(recursive: true);
    Directory(BackendPaths.serverStateDir(dataDir)).createSync(recursive: true);
  }

  /// Written once (later user edits are preserved). The child also receives
  /// every value through its environment, so this file is only a fallback for
  /// running the staged server by hand from the data directory.
  void _writeEnvFile(String dataDir, String secret) {
    final file = File(BackendPaths.envFile(dataDir));
    if (file.existsSync()) return;
    final contents = [
      'NODE_ENV=production',
      'PORT=0',
      'BIND_ADDRESS=127.0.0.1',
      'JWT_SECRET=$secret',
      'DATABASE_PATH=${BackendPaths.databaseDir(dataDir)}',
      'UPLOADS_DIR=${BackendPaths.uploadsDir(dataDir)}',
      'LOG_DIR=${BackendPaths.logsDir(dataDir)}',
      'SERVE_CLIENT=false',
      'ALLOWED_ORIGINS=http://127.0.0.1',
      '',
    ].join('\n');
    file.writeAsStringSync(contents, flush: true);
    if (_platform != BackendPlatform.windows) {
      try {
        Process.runSync('chmod', ['600', file.path]);
      } catch (_) {
        // Best effort; the data directory is already user-scoped.
      }
    }
  }

  Map<String, String> _buildEnvironment({
    required String dataDir,
    required String secret,
    String? adminPassword,
  }) {
    return {
      'NODE_ENV': 'production',
      'PORT': '0',
      'BIND_ADDRESS': '127.0.0.1',
      'JWT_SECRET': secret,
      'DATABASE_PATH': BackendPaths.databaseDir(dataDir),
      'UPLOADS_DIR': BackendPaths.uploadsDir(dataDir),
      'LOG_DIR': BackendPaths.logsDir(dataDir),
      'SERVE_CLIENT': 'false',
      'PORT_FILE': BackendPaths.portFile(dataDir),
      'PID_FILE': BackendPaths.pidFile(dataDir),
      'MINIERP_PARENT_PID': '$pid',
      'ALLOWED_ORIGINS': 'http://127.0.0.1',
      'LOG_LEVEL': 'info',
      'DEFAULT_ADMIN_PASSWORD': ?adminPassword,
    };
  }

  void _captureConsole(BackendProcessHandle handle, String consoleLog) {
    try {
      // Owned for the supervisor's lifetime; closed in shutdown()/dispose().
      // ignore: close_sinks
      _consoleSink ??= File(consoleLog).openWrite(mode: FileMode.append);
      handle.stdout.listen(_consoleSink!.add, onError: (_) {});
      handle.stderr.listen(_consoleSink!.add, onError: (_) {});
    } catch (_) {
      // Log capture is diagnostic only; the server's winston logs still
      // land in LOG_DIR.
    }
  }

  /// Windows: `node.exe` is a console binary, so a direct spawn flashes a
  /// console window. A throwaway VBS launched through `wscript.exe` starts it
  /// hidden and redirects both streams to the console log.
  Future<BackendProcessHandle> _launchWindowsHidden({
    required String runtime,
    required String serverScript,
    required String dataDir,
    required String consoleLog,
    required Map<String, String> environment,
  }) async {
    final vbsPath = p.join(
      BackendPaths.serverStateDir(dataDir),
      'launch-hidden.vbs',
    );
    final command = 'cmd /c ""$runtime" "$serverScript" >> "$consoleLog" 2>&1"';
    final buffer = StringBuffer()
      ..writeln('Set sh = CreateObject("WScript.Shell")')
      ..writeln('sh.CurrentDirectory = "${_vbsEscape(dataDir)}"');
    for (final entry in environment.entries) {
      buffer.writeln(
        'sh.Environment("PROCESS")("${_vbsEscape(entry.key)}") = '
        '"${_vbsEscape(entry.value)}"',
      );
    }
    buffer.writeln('sh.Run "${_vbsEscape(command)}", 0, False');
    File(vbsPath).writeAsStringSync(buffer.toString(), flush: true);

    try {
      final process = await Process.start(
        'wscript.exe',
        ['//nologo', vbsPath],
        workingDirectory: dataDir,
        environment: environment,
      );
      return _NativeProcessHandle(process);
    } on ProcessException {
      // Policy-blocked wscript (rare): fall back to a direct spawn. A console
      // flash is cosmetic compared to a server that never starts.
      final process = await _processStarter(
        executable: runtime,
        arguments: [serverScript],
        workingDirectory: dataDir,
        environment: environment,
      );
      _monitorExit = true;
      _captureConsole(process, consoleLog);
      return process;
    }
  }

  static String _vbsEscape(String value) => value.replaceAll('"', '""');

  int? _readPort(String dataDir) {
    try {
      return int.tryParse(
        File(BackendPaths.portFile(dataDir)).readAsStringSync().trim(),
      );
    } catch (_) {
      return null;
    }
  }

  int? _readPid(String dataDir) {
    try {
      return int.tryParse(
        File(BackendPaths.pidFile(dataDir)).readAsStringSync().trim(),
      );
    } catch (_) {
      return null;
    }
  }

  void _removeRuntimeFiles(String dataDir) {
    for (final path in [
      BackendPaths.portFile(dataDir),
      BackendPaths.pidFile(dataDir),
    ]) {
      try {
        File(path).deleteSync();
      } catch (_) {
        // Already gone.
      }
    }
  }

  String _readLogTail(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) return '';
      final length = file.lengthSync();
      final start = length > 8192 ? length - 8192 : 0;
      final bytes = file.readAsBytesSync();
      return String.fromCharCodes(bytes.sublist(start));
    } catch (_) {
      return '';
    }
  }

  static int? _portFromBaseUrl(String baseUrl) => Uri.tryParse(baseUrl)?.port;

  void _fail(
    String message,
    Object error, {
    String? serverDir,
    String? dataDir,
    String? logPath,
  }) {
    _setFailed(
      message,
      '$error',
      serverDir: serverDir ?? state.serverDir,
      dataDir: dataDir ?? state.dataDir,
      logPath: logPath ?? state.logPath,
    );
  }

  void _setFailed(
    String message,
    String detail, {
    String? serverDir,
    String? dataDir,
    String? logPath,
  }) {
    state = BackendState(
      status: BackendStatus.failed,
      serverDir: serverDir,
      dataDir: dataDir,
      logPath: logPath,
      message: message,
      detail: detail,
    );
  }

  @override
  void dispose() {
    _livenessTimer?.cancel();
    unawaited(_consoleSink?.close());
    super.dispose();
  }
}
