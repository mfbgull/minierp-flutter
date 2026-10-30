import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_notifier.dart';
import '../../core/backend/backend_providers.dart';
import '../../core/backend/backend_supervisor.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/app_logo.dart';
import 'first_run_screen.dart';

/// Boot screen. Starts the bundled backend (packaged builds), then resolves
/// the stored session — PORTING.md §3.
///
/// The first auth request must not run before the backend's ephemeral port is
/// known, so `restoreSession()` is triggered here on `ready`, not from the
/// auth notifier's constructor.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _restoreStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    final supervisor = ref.read(backendSupervisorProvider.notifier);
    await supervisor.initialize();
    _restoreWhenReady();
  }

  void _restoreWhenReady() {
    if (_restoreStarted) return;
    if (!ref.read(backendSupervisorProvider).isReady) return;
    _restoreStarted = true;
    unawaited(ref.read(authProvider.notifier).restoreSession());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<BackendState>(backendSupervisorProvider, (previous, next) {
      if (next.isReady) _restoreWhenReady();
    });

    final backend = ref.watch(backendSupervisorProvider);
    return switch (backend.status) {
      BackendStatus.needsSetup => FirstRunScreen(
        onSubmit: (password) async {
          await ref
              .read(backendSupervisorProvider.notifier)
              .submitAdminPassword(password);
          _restoreWhenReady();
        },
      ),
      BackendStatus.failed => _BackendFailureScreen(
        state: backend,
        onRetry: _boot,
      ),
      _ => _SplashBody(backend: backend),
    };
  }
}

class _SplashBody extends StatelessWidget {
  const _SplashBody({required this.backend});

  final BackendState backend;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final starting =
        backend.status == BackendStatus.starting ||
        backend.status == BackendStatus.idle;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppLogo(size: 64),
            const SizedBox(height: 16),
            Text('MiniERP', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              starting ? l10n.backendStarting : l10n.splashLoading,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _BackendFailureScreen extends StatelessWidget {
  const _BackendFailureScreen({required this.state, required this.onRetry});

  final BackendState state;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final message = switch (state.message) {
      'alreadyRunning' => l10n.backendAlreadyRunning,
      'stopped' => l10n.backendStopped,
      _ => l10n.backendFailedBody,
    };
    final logPath = state.logPath;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 56,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.backendFailedTitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(message, textAlign: TextAlign.center),
                if (logPath != null) ...[
                  const SizedBox(height: 16),
                  SelectableText(
                    l10n.backendLogsAt(logPath),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => onRetry(),
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.retry),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
