import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/core/backend/backend_paths.dart';
import 'package:minierp_app/core/backend/backend_providers.dart';
import 'package:minierp_app/core/backend/backend_supervisor.dart';
import 'package:minierp_app/features/auth/first_run_screen.dart';
import 'package:minierp_app/features/auth/splash_screen.dart';
import 'package:minierp_app/l10n/app_localizations.dart';
import 'package:path/path.dart' as p;

void main() {
  testWidgets('first launch shows the admin-password setup screen', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('minierp_splash_');
    addTearDown(() => root.deleteSync(recursive: true));
    final serverDir = p.join(root.path, 'server');
    final bundles = {
      p.join(serverDir, 'dist', 'server.js'),
      p.join(serverDir, 'runtime', 'node'),
    };

    final supervisor = BackendSupervisor(
      serverDirOverride: serverDir,
      dataDirOverride: p.join(root.path, 'data'),
      platform: BackendPlatform.linux,
      hiddenWindowsLaunch: false,
      fileExists: bundles.contains,
      healthProbe: (_) async => false,
      pidCheck: (_) => false,
      processStarter: ({
        required executable,
        required arguments,
        required workingDirectory,
        required environment,
      }) async {
        throw StateError('must not spawn before setup');
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendSupervisorProvider.overrideWith((ref) => supervisor),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: [Locale('en'), Locale('ur')],
          home: SplashScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FirstRunScreen), findsOneWidget);
    expect(find.text('Set up MiniERP'), findsOneWidget);
    expect(find.text('Start MiniERP'), findsOneWidget);
    expect(supervisor.state.status, BackendStatus.needsSetup);
  });
}
