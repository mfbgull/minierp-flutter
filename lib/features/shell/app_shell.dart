import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_notifier.dart';
import '../../core/i18n/locale_provider.dart';
import '../../data/models/auth_user.dart';
import '../../core/router/module_registry.dart'
    show shellDestinations;
import '../../core/router/shell_destination.dart' show ShellDestination;
import '../../core/theme/breakpoints.dart' show Breakpoints;
import '../../core/theme/theme_mode_provider.dart';
import '../../features/search/global_search_dialog.dart'
    show showGlobalSearchDialog;
import '../../l10n/app_localizations.dart';
import '../../widgets/screen_shortcuts.dart';
import '../preferences/preference_providers.dart'
    show userPreferencesProvider;
import 'deferred_branch.dart' show BranchVisibility;
import 'module_refresh.dart' show moduleRefreshOnVisit;


/// Authenticated shell — navigation rail + shared app bar wrapping the
/// current branch (PORTING.md §5). Hosted by `StatefulShellRoute` so each
/// branch keeps its state when switching modules.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final auth = ref.watch(authProvider);
    // Boot the per-user date-range preferences (server = truth): the
    // SharedPreferences cache already seeded the preference
    // StateProviders synchronously; this fetch syncs them with the
    // server when it resolves (date-range-picker-spec.md §6.2). The
    // shell only renders once authenticated, so the JWT is in place.
    ref.watch(userPreferencesProvider);
    final isAdmin = auth.user?.isAdmin ?? false;
    final visible = [
      for (final dest in shellDestinations)
        if ((!dest.adminOnly || isAdmin) && !dest.hideInRail) dest,
    ];
    final current = shellDestinations[navigationShell.currentIndex];
    final selectedIndex = visible.indexWhere((d) => identical(d, current));

    return _GlobalSearchHotkey(
      child: Scaffold(
      appBar: AppBar(
        title: Text((current.title ?? current.label)(l10n)),
        actions: [
          IconButton(
            tooltip: 'Search (Ctrl+K)',
            icon: const Icon(Icons.search),
            onPressed: () => showGlobalSearchDialog(context),
          ),
          if (auth.user != null) _UserMenu(user: auth.user!),
          const SizedBox(width: 4),
        ],
      ),
      // Screen-level keyboard shortcuts (Ctrl+F focus search, Ctrl+N new
      // record): the scope resolves the visible branch's toolbar at
      // keypress time and dispatches the keys from anywhere on screen.
      body: ScreenShortcutScope(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _NavRail(
              destinations: visible,
              selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
              onSelect: (index) {
                final dest = visible[index];
                final branchIndex = shellDestinations.indexOf(dest);
                // Refresh the selected module's data on every visit:
                // the StatefulShellRoute keeps every branch alive, so
                // its providers would otherwise serve data cached at
                // the first visit (module_refresh.dart). Re-clicking
                // the current module refreshes it too.
                moduleRefreshOnVisit[dest.path]?.call(ref);
                navigationShell.goBranch(
                  branchIndex,
                  initialLocation: branchIndex == navigationShell.currentIndex,
                );
              },
            ),
            const VerticalDivider(width: 1, thickness: 1),
            // Expose the visible branch to the DeferredBranch hosts so
            // each module materializes (and fetches) on first visit.
            Expanded(
              child: BranchVisibility(
                currentPath: current.path,
                child: navigationShell,
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}

/// Left navigation rail (spec 3.1/3.2): a Material 3 [NavigationRail]
/// with the M3 indicator + animation, accessibility semantics, and
/// adaptive width — extended (labels) from the medium breakpoint up,
/// icon-only below. Wrapped in a scroll view because the module list
/// exceeds typical window heights.
class _NavRail extends StatelessWidget {
  const _NavRail({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<ShellDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final extended = MediaQuery.sizeOf(context).width >= Breakpoints.medium;
    final l10n = AppLocalizations.of(context)!;

    return NavigationRail(
      // The module list exceeds typical window heights — the rail's
      // built-in scrollable keeps the leading mark pinned and scrolls
      // the destinations.
      scrollable: true,
      backgroundColor: scheme.surface,
      extended: extended,
      selectedIndex: selectedIndex,
      onDestinationSelected: onSelect,
      leading: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: extended
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.inventory_2, color: scheme.primary),
                    const SizedBox(width: 10),
                    Text(
                      'MiniERP',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                )
              : Icon(Icons.inventory_2, color: scheme.primary),
        ),
      destinations: [
        for (final dest in destinations)
          NavigationRailDestination(
            icon: Icon(dest.icon),
            selectedIcon: Icon(dest.icon),
            // Cap the label so the extended rail stays at its theme width
            // (180px, matching the pre-M3 rail); without this the rail
            // grows to fit the longest label and shrinks module grids.
            label: SizedBox(
              width: 100,
              child: Text(
                dest.label(l10n),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
      ],
    );
  }
}

/// Registers a global Ctrl/Cmd+K handler that opens the search palette
/// from anywhere in the app, independent of the screen-level shortcuts
/// (screen_shortcuts.dart).
class _GlobalSearchHotkey extends ConsumerStatefulWidget {
  const _GlobalSearchHotkey({required this.child});

  final Widget child;

  @override
  ConsumerState<_GlobalSearchHotkey> createState() =>
      _GlobalSearchHotkeyState();
}

class _GlobalSearchHotkeyState extends ConsumerState<_GlobalSearchHotkey> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    super.dispose();
  }

  bool _handleKey(KeyEvent event) {
    if (event is KeyDownEvent &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyK) {
      showGlobalSearchDialog(context);
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}


/// Confirmation dialog + logout. Shared by the shell and the user menu
/// (spec 3.3) — both live in this file.
Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context)!;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.commonLogout),
      content: Text(l10n.logoutConfirmMessage),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(l10n.commonLogout),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await ref.read(authProvider.notifier).logout();
  }
}

enum _UserMenuAction { changePassword, settings, logout }

/// User menu (spec 3.3) — avatar + display-name anchor in the app bar;
/// Change Password, Language, theme toggle, Settings and Logout all live
/// inside the dropdown so the bar stays at two actions (search + menu)
/// and never overflows on narrow screens.
class _UserMenu extends ConsumerWidget {
  const _UserMenu({required this.user});

  final AuthUser user;

  Future<void> _showLanguageDialog(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final current = ref.read(localeProvider);
    final selected = await showDialog<Locale>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(l10n.commonLanguage),
        children: [
          for (final locale in supportedLocales)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, locale),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      locale.languageCode == 'en' ? 'English' : 'اردو',
                    ),
                  ),
                  if (locale == current)
                    Icon(
                      Icons.check,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
    if (selected != null) {
      ref.read(localeProvider.notifier).setLocale(selected);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final mode = ref.watch(themeModeProvider);
    final effective = Theme.of(context).brightness == Brightness.dark;
    // System mode follows the OS; picking a mode in the menu pins an
    // explicit choice so the toggle has immediate effect.
    final isDark = mode == ThemeMode.dark ||
        (mode == ThemeMode.system && effective);
    final scheme = Theme.of(context).colorScheme;

    return PopupMenuButton<_UserMenuAction>(
      tooltip: l10n.commonUserMenu,
      onSelected: (action) {
        switch (action) {
          case _UserMenuAction.changePassword:
            context.push('/change-password');
          case _UserMenuAction.settings:
            context.go('/settings');
          case _UserMenuAction.logout:
            _confirmLogout(context, ref);
        }
      },
      itemBuilder: (menuContext) => [
        PopupMenuItem(
          value: _UserMenuAction.changePassword,
          child: Row(
            children: [
              const Icon(Icons.key_outlined),
              const SizedBox(width: 12),
              Text(l10n.changePasswordTitle),
            ],
          ),
        ),
        PopupMenuItem(
          // The framework pops the menu before onTap runs, so the
          // language picker opens as a fresh dialog on top of the shell.
          onTap: () => _showLanguageDialog(context, ref),
          child: Row(
            children: [
              const Icon(Icons.language),
              const SizedBox(width: 12),
              Text(l10n.commonLanguage),
            ],
          ),
        ),
        PopupMenuItem(
          // Toggles the *effective* brightness and persists the choice
          // (light / dark / system) via themeModeProvider.
          onTap: () => ref
              .read(themeModeProvider.notifier)
              .setMode(isDark ? ThemeMode.light : ThemeMode.dark),
          child: Row(
            children: [
              Icon(isDark ? Icons.dark_mode : Icons.light_mode),
              const SizedBox(width: 12),
              Text(l10n.commonThemeMode),
            ],
          ),
        ),
        PopupMenuItem(
          value: _UserMenuAction.settings,
          child: Row(
            children: [
              const Icon(Icons.settings_outlined),
              const SizedBox(width: 12),
              Text(l10n.navSettings),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _UserMenuAction.logout,
          child: Row(
            children: [
              Icon(Icons.logout, color: scheme.error),
              const SizedBox(width: 12),
              Text(l10n.commonLogout, style: TextStyle(color: scheme.error)),
            ],
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_circle_outlined),
            const SizedBox(width: 4),
            Text(user.displayName, style: Theme.of(context).textTheme.titleSmall),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}
