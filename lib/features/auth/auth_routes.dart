import 'package:go_router/go_router.dart';

import '../../core/router/module_routes.dart';
import 'change_password_screen.dart';
import 'login_screen.dart';
import 'splash_screen.dart';

/// Auth screens live outside the authenticated shell (no rail
/// destination): splash → login → shell, plus the standalone
/// change-password page opened from the shell's user menu.
class AuthRoutes extends ModuleRoutes {
  const AuthRoutes();

  @override
  ShellDestination? get destination => null;

  @override
  List<GoRoute> get standaloneRoutes => [
    GoRoute(
      path: '/splash',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    // Auth-module completion (PORTING.md §3): standalone screen outside
    // the shell (no rail) — opened from the shell's app bar. Session
    // stays valid after a change; a wrong current password is a 401 that
    // the dio layer treats as a credential error, not an expired session.
    GoRoute(
      path: '/change-password',
      builder: (context, state) => const ChangePasswordScreen(),
    ),
  ];
}