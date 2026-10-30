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
import 'package:minierp_app/widgets/app_logo.dart';
import 'package:path/path.dart' as p;

/// Supervisor fixture that ends in `needsSetup` without ever spawning a
/// process (bundle files absent, health probe fails, pid check fails).
BackendSupervisor needsSetupSupervisor(Directory root) {
  final serverDir = p.join(root.path, 'server');
  final bundles = {
    p.join(serverDir, 'dist', 'server.js'),
    p.join(serverDir, 'runtime', 'node'),
  };

  return BackendSupervisor(
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
}

Future<void> pumpSplash(WidgetTester tester, Directory root) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        backendSupervisorProvider.overrideWith((ref) => needsSetupSupervisor(root)),
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
}

Future<Directory> makeTempRoot() async =>
    Directory.systemTemp.createTempSync('minierp_splash_');

void main() {
  testWidgets('first launch shows the admin-password setup screen', (
    tester,
  ) async {
    final root = await makeTempRoot();
    addTearDown(() => root.deleteSync(recursive: true));
    await pumpSplash(tester, root);
    await tester.pumpAndSettle();

    expect(find.byType(FirstRunScreen), findsOneWidget);
    expect(find.text('Set up MiniERP'), findsOneWidget);
    expect(find.text('Start MiniERP'), findsOneWidget);
    // Branding: the setup screen must show the app logo, not a generic
    // Material glyph (app_logo regression net for the first-run brand slot).
    expect(
      find.descendant(
        of: find.byType(FirstRunScreen),
        matching: find.byType(AppLogo),
      ),
      findsOneWidget,
    );
  });

  testWidgets('splash shows the app logo while the backend boots', (
    tester,
  ) async {
    final root = await makeTempRoot();
    addTearDown(() => root.deleteSync(recursive: true));
    await pumpSplash(tester, root);

    // One frame: BackendStatus.idle renders the splash body before
    // initialize() reports `needsSetup` and the first-run screen takes over.
    await tester.pump();
    expect(find.byType(AppLogo), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byType(FirstRunScreen), findsOneWidget);
  });
}
