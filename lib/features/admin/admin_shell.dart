// User management shell (PORTING.md §5: `/users`, `/roles` → UsersScreen,
// RolesScreen, admin-only) — two tab views over the `/users` and `/roles`
// endpoints, modeled on the forecast shell: Users (grid + CRUD + status/
// password actions) and Roles & Permissions (grid + CRUD + permission
// assignment).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../shell/module_refresh.dart' show moduleTabRefreshOnVisit;
import 'admin_providers.dart' show adminShellTabProvider;
import 'roles_screen.dart';
import 'users_screen.dart';

class AdminShell extends ConsumerStatefulWidget {
  const AdminShell({super.key});

  @override
  ConsumerState<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends ConsumerState<AdminShell> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final index = ref.watch(adminShellTabProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (i) {
            ref.read(adminShellTabProvider.notifier).state = i;
            // Refresh the clicked tab's data (the IndexedStack keeps
            // every tab alive, so its providers would stay cached).
            moduleTabRefreshOnVisit['/admin']?[i].call(ref);
          },
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.people_outline),
              selectedIcon: const Icon(Icons.people),
              label: l10n.navUsers,
            ),
            NavigationDestination(
              icon: const Icon(Icons.admin_panel_settings_outlined),
              selectedIcon: const Icon(Icons.admin_panel_settings),
              label: l10n.navRoles,
            ),
          ],
        ),
        Expanded(
          child: IndexedStack(
            index: index,
            children: const [
              UsersScreen(),
              RolesScreen(),
            ],
          ),
        ),
      ],
    );
  }
}
