import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/auth/auth_notifier.dart';
import 'core/auth/session_events.dart';
import 'core/i18n/locale_provider.dart';
import 'core/router/module_registry.dart' show moduleRegistry, shellDestinations;
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_provider.dart';
import 'core/utils/print_service.dart' show PrintFormatMemory;
import 'features/preferences/preference_providers.dart'
    show resetUserPreferences;
import 'features/shell/app_shell.dart';
import 'l10n/app_localizations.dart';

/// Bumped whenever the auth *status* changes so the router's
/// `refreshListenable` re-evaluates its redirect. A plain counter, kept
/// separate from the router so `StateNotifier` (which doesn't implement
/// Flutter's `Listenable`) can drive it via `ref.listen` in the app widget.
final routerRefreshProvider = Provider<ValueNotifier<int>>((ref) {
  final notifier = ValueNotifier<int>(0);
  ref.onDispose(notifier.dispose);
  return notifier;
});

/// App router — route inventory in PORTING.md §5. Built from
/// [moduleRegistry] (SHORTCOMINGS-FIX 1.1): each module contributes its
/// standalone routes (auth screens, forms) and one authenticated shell
/// branch per [shellDestinations] entry.
///
/// Auth gating (PORTING.md §3): the router is created once and refreshes
/// its redirect when the auth status changes, so navigation state survives
/// login/logout. While the session is being restored (`AuthStatus.unknown`)
/// everything redirects to `/splash`; logged-out users land on `/login`;
/// authenticated users are kept out of `/login` and `/splash`.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: ref.watch(routerRefreshProvider),
    redirect: (context, state) => _authRedirect(ref, state.matchedLocation),
    routes: [
      // Standalone routes outside the shell (auth, forms, previews).
      for (final module in moduleRegistry) ...module.standaloneRoutes,
      // Authenticated shell (PORTING.md §5): one branch per module in
      // [shellDestinations] — each keeps its state while switching.
      //
      // indexedStack builds all branches eagerly (go_router 17.x has no
      // `lazy` option), so each branch root is wrapped in
      // [DeferredBranch] (spec 7.1) inside its module route file: a
      // branch's screen — and therefore its data fetches — only
      // materializes on first visit, keeping login to the dashboard's
      // own calls instead of all 17 modules'.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          for (final dest in shellDestinations)
            StatefulShellBranch(
              routes: moduleRegistry
                  .firstWhere((m) => m.destination?.path == dest.path)
                  .branchRoutes,
            ),
        ],
      ),
    ],
  );
});

/// Resolves where an un-authed/auth'd user may go. Called on every auth
/// status change (via [routerRefreshProvider]) and on every navigation.
String? _authRedirect(Ref ref, String location) {
  final auth = ref.read(authProvider);
  switch (auth.status) {
    case AuthStatus.unknown:
      return location == '/splash' ? null : '/splash';
    case AuthStatus.unauthenticated:
      return location == '/login' ? null : '/login';
    case AuthStatus.authenticated:
      if (location == '/login' || location == '/splash') return '/';
      // Non-admins can type an admin-only URL directly — send them home
      // instead of showing a branch the rail doesn't list (the shell's
      // indexOf fallback would otherwise highlight the wrong rail item).
      final isAdmin = auth.user?.isAdmin ?? false;
      final onAdminPath = shellDestinations
          .where((d) => d.adminOnly)
          .any((d) => location == d.path);
      if (onAdminPath && !isAdmin) return '/';
      return null;
  }
}

class MiniErpApp extends ConsumerWidget {
  const MiniErpApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Re-evaluate the router redirect when the auth status changes.
    ref.listen(authProvider, (previous, next) {
      if (previous?.status != next.status) {
        // Per-user preferences are cached per session; on logout reset
        // the local state + cache to defaults and refetch on the next
        // login so a different user's week start / default range /
        // presets replace the previous user's.
        if (next.status == AuthStatus.unauthenticated) {
          resetUserPreferences(ref);
          // Per-user print-format memory is local-only; clear it on
          // logout so the next user isn't pinned to the previous one's
          // format (SHORTCOMINGS-FIX 4.5).
          PrintFormatMemory.clear();
        }
        ref.read(routerRefreshProvider).value++;
      }
    });

    // PORTING.md §2: a 401 anywhere (expired token mid-session) clears the
    // session and the router redirects to /login.
    ref.listen(unauthorizedEventsProvider, (previous, next) {
      if (next.hasValue) {
        ref.read(authProvider.notifier).sessionExpired();
      }
    });

    return MaterialApp.router(
      title: 'MiniERP',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(routerProvider),
      locale: ref.watch(localeProvider),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('ur')],
    );
  }
}