import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/core/api/api_client.dart';
import 'package:minierp_app/core/backend/backend_paths.dart';
import 'package:minierp_app/core/backend/backend_supervisor.dart';
import 'package:path/path.dart' as p;

class _FakeProcess implements BackendProcessHandle {
  _FakeProcess(this.pid);

  final Completer<int> _exit = Completer<int>();

  @override
  final int pid;

  @override
  Stream<List<int>> get stdout => const Stream<List<int>>.empty();

  @override
  Stream<List<int>> get stderr => const Stream<List<int>>.empty();

  @override
  Future<int> get exitCode => _exit.future;

  void exit(int code) {
    if (!_exit.isCompleted) _exit.complete(code);
  }
}

void main() {
  late Directory root;
  late String dataDir;
  late String serverDir;

  setUp(() {
    ApiClient.setBaseUrl(ApiClient.defaultBaseUrl);
    root = Directory.systemTemp.createTempSync('minierp_supervisor_');
    dataDir = p.join(root.path, 'data');
    serverDir = p.join(root.path, 'server');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// Server payload files always "exist"; [withDatabase] controls first run.
  bool Function(String) payloadExists({required bool withDatabase}) {
    final bundles = {
      p.join(serverDir, 'dist', 'server.js'),
      p.join(serverDir, 'runtime', 'node'),
    };
    final database = p.join(BackendPaths.databaseDir(dataDir), 'erp.db');
    return (path) =>
        bundles.contains(path) || (withDatabase && path == database);
  }

  BackendSupervisor buildSupervisor({
    required bool withDatabase,
    required BackendProcessStarter starter,
    BackendHealthProbe? healthProbe,
    BackendPidCheck? pidCheck,
    BackendProcessKiller? processKiller,
    bool Function(String)? exists,
  }) {
    return BackendSupervisor(
      serverDirOverride: serverDir,
      dataDirOverride: dataDir,
      platform: BackendPlatform.linux,
      hiddenWindowsLaunch: false,
      fileExists: exists ?? payloadExists(withDatabase: withDatabase),
      processStarter: starter,
      healthProbe: healthProbe ?? (_) async => false,
      pidCheck: pidCheck ?? (_) => false,
      processKiller: processKiller ?? (_, {force = false}) {},
      startupTimeout: const Duration(seconds: 2),
      pollInterval: const Duration(milliseconds: 5),
      shutdownTimeout: const Duration(milliseconds: 30),
    );
  }

  test('development without a bundled server uses the external backend', () async {
    final supervisor = BackendSupervisor(
      executablePath: '/nonexistent/minierp_app',
      platform: BackendPlatform.linux,
      fileExists: (_) => false,
    );
    await supervisor.initialize();
    expect(supervisor.state.status, BackendStatus.external);
    expect(ApiClient.baseUrl, ApiClient.defaultBaseUrl);
    supervisor.dispose();
  });

  test('first launch asks for the admin password before spawning', () async {
    var starts = 0;
    final supervisor = buildSupervisor(
      withDatabase: false,
      starter: ({
        required executable,
        required arguments,
        required workingDirectory,
        required environment,
      }) async {
        starts += 1;
        return _FakeProcess(1);
      },
    );

    await supervisor.initialize();
    expect(supervisor.state.status, BackendStatus.needsSetup);
    expect(starts, 0);
    expect(File(BackendPaths.lockFile(dataDir)).existsSync(), isFalse);
    supervisor.dispose();
  });

  test('setup boot passes the password once and never persists it', () async {
    var alive = true;
    final fake = _FakeProcess(4242);
    final environments = <Map<String, String>>[];
    final supervisor = buildSupervisor(
      withDatabase: false,
      pidCheck: (_) => alive,
      processKiller: (_, {force = false}) => alive = false,
      starter: ({
        required executable,
        required arguments,
        required workingDirectory,
        required environment,
      }) async {
        environments.add(environment);
        expect(executable, p.join(serverDir, 'runtime', 'node'));
        expect(arguments, [p.join(serverDir, 'dist', 'server.js')]);
        expect(workingDirectory, dataDir);
        File(BackendPaths.portFile(dataDir)).writeAsStringSync('41234');
        return fake;
      },
      healthProbe: (url) async => url == 'http://127.0.0.1:41234/health',
    );

    await supervisor.initialize();
    expect(supervisor.state.status, BackendStatus.needsSetup);

    await supervisor.submitAdminPassword('correct horse battery');
    expect(supervisor.state.status, BackendStatus.ready);
    expect(supervisor.state.port, 41234);
    expect(ApiClient.baseUrl, 'http://127.0.0.1:41234/api');

    final env = environments.single;
    expect(env['DEFAULT_ADMIN_PASSWORD'], 'correct horse battery');
    expect(env['PORT'], '0');
    expect(env['DATABASE_PATH'], BackendPaths.databaseDir(dataDir));
    expect(env['SERVE_CLIENT'], 'false');
    expect(env['PORT_FILE'], BackendPaths.portFile(dataDir));
    expect(env['MINIERP_PARENT_PID'], '$pid');

    final envFile = File(BackendPaths.envFile(dataDir)).readAsStringSync();
    expect(envFile, isNot(contains('DEFAULT_ADMIN_PASSWORD')));
    expect(envFile, contains('JWT_SECRET='));

    await supervisor.shutdown();
    expect(alive, isFalse);
    expect(supervisor.state.status, BackendStatus.idle);
    expect(File(BackendPaths.lockFile(dataDir)).existsSync(), isFalse);
    supervisor.dispose();
  });

  test('relaunch with an existing database starts without a password', () async {
    final fake = _FakeProcess(5252);
    final environments = <Map<String, String>>[];
    final supervisor = buildSupervisor(
      withDatabase: true,
      pidCheck: (_) => false,
      starter: ({
        required executable,
        required arguments,
        required workingDirectory,
        required environment,
      }) async {
        environments.add(environment);
        File(BackendPaths.portFile(dataDir)).writeAsStringSync('42000');
        return fake;
      },
      healthProbe: (url) async => url.contains('42000'),
    );

    await supervisor.initialize();
    expect(supervisor.state.status, BackendStatus.ready);
    expect(environments.single.containsKey('DEFAULT_ADMIN_PASSWORD'), isFalse);
    await supervisor.shutdown();
    supervisor.dispose();
  });

  test('an upgraded install keeps the JWT secret from its migrated .env', () async {
    // The .run installer moves the legacy <dir>/server/.env (and with it the
    // JWT_SECRET that keys ENCRYPTION_KEY) into <dir>/data before replacing
    // the app tree. Regenerating it would orphan encrypted data.
    final legacy = 'b' * 64;
    Directory(BackendPaths.databaseDir(dataDir)).createSync(recursive: true);
    File(p.join(BackendPaths.databaseDir(dataDir), 'erp.db')).writeAsStringSync('');
    File(BackendPaths.envFile(dataDir))
        .writeAsStringSync('JWT_SECRET=$legacy\n');

    final environments = <Map<String, String>>[];
    final supervisor = buildSupervisor(
      withDatabase: true,
      pidCheck: (_) => false,
      starter: ({
        required executable,
        required arguments,
        required workingDirectory,
        required environment,
      }) async {
        environments.add(environment);
        File(BackendPaths.portFile(dataDir)).writeAsStringSync('42100');
        return _FakeProcess(8383);
      },
      healthProbe: (url) async => url.contains('42100'),
    );

    await supervisor.initialize();
    expect(supervisor.state.status, BackendStatus.ready);
    expect(environments.single['JWT_SECRET'], legacy);
    expect(
      File(BackendPaths.jwtSecretFile(dataDir)).readAsStringSync().trim(),
      legacy,
    );
    await supervisor.shutdown();
    supervisor.dispose();
  });

  test('a missing admin row falls back to first-run setup', () async {
    final fake = _FakeProcess(6262);
    final supervisor = buildSupervisor(
      withDatabase: true,
      starter: ({
        required executable,
        required arguments,
        required workingDirectory,
        required environment,
      }) async {
        File(
          BackendPaths.consoleLogFile(dataDir),
        ).writeAsStringSync('FATAL: DEFAULT_ADMIN_PASSWORD environment variable must be set\n');
        unawaited(Future<void>.microtask(() => fake.exit(1)));
        return fake;
      },
    );

    await supervisor.initialize();
    expect(supervisor.state.status, BackendStatus.needsSetup);
    supervisor.dispose();
  });

  test('a server that never becomes healthy fails with the log path', () async {
    final fake = _FakeProcess(7272);
    final supervisor = BackendSupervisor(
      serverDirOverride: serverDir,
      dataDirOverride: dataDir,
      platform: BackendPlatform.linux,
      hiddenWindowsLaunch: false,
      fileExists: payloadExists(withDatabase: true),
      processStarter: ({
        required executable,
        required arguments,
        required workingDirectory,
        required environment,
      }) async => fake,
      healthProbe: (_) async => false,
      pidCheck: (_) => false,
      startupTimeout: const Duration(milliseconds: 120),
      pollInterval: const Duration(milliseconds: 5),
    );

    await supervisor.initialize();
    expect(supervisor.state.status, BackendStatus.failed);
    expect(supervisor.state.message, 'startup');
    expect(supervisor.state.logPath, BackendPaths.consoleLogFile(dataDir));
    expect(
      File(BackendPaths.lockFile(dataDir)).existsSync(),
      isFalse,
      reason: 'a failed boot must release the instance lock for Retry',
    );
    supervisor.dispose();
  });

  test('adopts a healthy server left by a previous app process', () async {
    Directory(BackendPaths.databaseDir(dataDir)).createSync(recursive: true);
    File(p.join(BackendPaths.databaseDir(dataDir), 'erp.db')).writeAsStringSync('');
    File(BackendPaths.pidFile(dataDir)).writeAsStringSync('777');
    File(BackendPaths.portFile(dataDir)).writeAsStringSync('43000');

    var starts = 0;
    final supervisor = buildSupervisor(
      withDatabase: true,
      pidCheck: (value) => value == 777,
      starter: ({
        required executable,
        required arguments,
        required workingDirectory,
        required environment,
      }) async {
        starts += 1;
        return _FakeProcess(1);
      },
      healthProbe: (url) async => url.contains('43000'),
    );

    await supervisor.initialize();
    expect(supervisor.state.status, BackendStatus.ready);
    expect(supervisor.state.port, 43000);
    expect(starts, 0);
    expect(ApiClient.baseUrl, 'http://127.0.0.1:43000/api');

    await supervisor.shutdown();
    expect(supervisor.state.status, BackendStatus.idle);
    supervisor.dispose();
  });

  test('refuses a data directory held by another live instance', () async {
    Directory(BackendPaths.databaseDir(dataDir)).createSync(recursive: true);
    File(p.join(BackendPaths.databaseDir(dataDir), 'erp.db')).writeAsStringSync('');
    File(BackendPaths.lockFile(dataDir)).writeAsStringSync('999');

    final supervisor = buildSupervisor(
      withDatabase: true,
      pidCheck: (value) => value == 999,
      starter: ({
        required executable,
        required arguments,
        required workingDirectory,
        required environment,
      }) async => _FakeProcess(1),
    );

    await supervisor.initialize();
    expect(supervisor.state.status, BackendStatus.failed);
    expect(supervisor.state.message, 'alreadyRunning');
    supervisor.dispose();
  });
}
