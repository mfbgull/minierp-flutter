/// End-to-end check of [BackendSupervisor] against the real Node server.
///
/// Opt-in (CI is hermetic): run with a built `server/dist` and installed
/// `server/node_modules`:
///
/// ```
/// MINIERP_LIVE_SERVER=1 flutter test test/core/backend/backend_live_test.dart
/// ```
///
/// The staged payload is faked with symlinks to the repo's build output, so
/// this exercises the supervisor, the server's runtime contract (PORT_FILE,
/// PID_FILE, data dirs, first-boot password) and graceful shutdown without a
/// full `tool/stage-server.mjs` run.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/core/backend/backend_paths.dart';
import 'package:minierp_app/core/backend/backend_supervisor.dart';
import 'package:path/path.dart' as p;

void main() {
  final repoRoot = Directory.current.path;
  final serverRoot = p.join(repoRoot, 'server');
  final distServer = p.join(serverRoot, 'dist', 'server.js');
  final nodeModules = p.join(serverRoot, 'node_modules');
  final enabled =
      Platform.environment['MINIERP_LIVE_SERVER'] == '1' &&
      File(distServer).existsSync() &&
      Directory(nodeModules).existsSync();

  test(
    'boots the real bundled server on an ephemeral port and stops it',
    () async {
      final root = Directory.systemTemp.createTempSync('minierp_live_');
      final dataDir = p.join(root.path, 'data');
      final payload = p.join(root.path, 'server');
      final node = '${Process.runSync('which', ['node']).stdout}'.trim();
      expect(node, isNotEmpty);

      Directory(p.join(payload, 'runtime')).createSync(recursive: true);
      File(p.join(payload, 'package.json')).writeAsStringSync(
        File(p.join(serverRoot, 'package.json')).readAsStringSync(),
      );
      Link(p.join(payload, 'dist')).createSync(p.join(serverRoot, 'dist'));
      Link(p.join(payload, 'node_modules')).createSync(nodeModules);
      Link(p.join(payload, 'runtime', 'node')).createSync(node);

      final supervisor = BackendSupervisor(
        serverDirOverride: payload,
        dataDirOverride: dataDir,
        hiddenWindowsLaunch: false,
        startupTimeout: const Duration(seconds: 40),
        pollInterval: const Duration(milliseconds: 250),
        shutdownTimeout: const Duration(seconds: 10),
      );

      try {
        await supervisor.initialize();
        expect(supervisor.state.status, BackendStatus.needsSetup);

        await supervisor.submitAdminPassword('Live-Test-Password-2026!');
        expect(
          supervisor.state.status,
          BackendStatus.ready,
          reason: 'detail: ${supervisor.state.detail}',
        );
        final port = supervisor.state.port!;
        expect(port, greaterThan(0));

        final client = HttpClient();
        final request = await client.getUrl(
          Uri.parse(BackendPaths.healthUrl(port)),
        );
        final response = await request.close();
        final body = await utf8.decodeStream(response);
        client.close(force: true);
        expect(response.statusCode, 200, reason: body);
        expect(body, contains('"status"'));

        final dbPath = p.join(BackendPaths.databaseDir(dataDir), 'erp.db');
        expect(File(dbPath).existsSync(), isTrue);

        final pidFile = File(BackendPaths.pidFile(dataDir));
        final serverPid = int.parse(pidFile.readAsStringSync().trim());
        expect(Process.runSync('kill', ['-0', '$serverPid']).exitCode, 0);

        await supervisor.shutdown();
        expect(supervisor.state.status, BackendStatus.idle);
        expect(File(BackendPaths.portFile(dataDir)).existsSync(), isFalse);
        expect(pidFile.existsSync(), isFalse);
        expect(
          File(BackendPaths.lockFile(dataDir)).existsSync(),
          isFalse,
          reason: 'the instance lock must be released on quit',
        );
        expect(
          Process.runSync('kill', ['-0', '$serverPid']).exitCode,
          isNot(0),
          reason: 'no orphaned server may survive the app',
        );

        final consoleLog = File(
          BackendPaths.consoleLogFile(dataDir),
        ).readAsStringSync();
        expect(consoleLog, contains('Mini ERP Server Started'));
      } finally {
        await supervisor.shutdown();
        if (root.existsSync()) root.deleteSync(recursive: true);
      }
    },
    skip: enabled
        ? false
        : 'set MINIERP_LIVE_SERVER=1 after `cd server && npm run build`',
  );
}
