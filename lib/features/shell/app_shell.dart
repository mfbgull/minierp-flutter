import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_notifier.dart';
import '../../l10n/app_localizations.dart';

/// One module in the shell's navigation. [label] is resolved with the
/// active localization; [path] is the router branch root; [adminOnly]
/// destinations are hidden for non-admin users.
class ShellDestination {
  const ShellDestination({
    required this.path,
    required this.label,
    required this.icon,
    this.adminOnly = false,
    this.title,
  });

  final String path;
  final String Function(AppLocalizations) label;
  final IconData icon;
  final bool adminOnly;

  /// App-bar title; defaults to [label] so modules whose rail label is
  /// branded differently (e.g. "Manufacturing" vs "Production") can keep
  /// the feature name in the app bar.
  final String Function(AppLocalizations)? title;
}

/// Single source of truth for the shell's module list — `app.dart` builds
/// the router branches from this and [AppShell] builds the rail from it,
/// so a module added here appears in both automatically.
final List<ShellDestination> shellDestinations = [
  ShellDestination(
    path: '/',
    label: (l) => l.navDashboard,
    icon: Icons.space_dashboard_outlined,
  ),
  ShellDestination(
    path: '/inventory',
    label: (l) => l.navInventory,
    icon: Icons.inventory_2_outlined,
  ),
  ShellDestination(
    path: '/customers',
    label: (l) => l.navCustomers,
    icon: Icons.people_outline,
  ),
  ShellDestination(
    path: '/sales',
    label: (l) => l.navSales,
    icon: Icons.point_of_sale_outlined,
  ),
  ShellDestination(
    path: '/purchasing',
    label: (l) => l.navPurchases,
    icon: Icons.shopping_cart_outlined,
  ),
  ShellDestination(
    path: '/suppliers',
    label: (l) => l.navSuppliers,
    icon: Icons.local_shipping_outlined,
  ),
  ShellDestination(
    path: '/production',
    // The sidebar link reads "Manufacturing" (product naming) while the
    // module's internal tab keeps the feature name.
    label: (l) => l.navManufacturing,
    title: (l) => l.navProduction,
    icon: Icons.factory_outlined,
  ),
  ShellDestination(
    path: '/payments',
    label: (l) => l.navPayments,
    icon: Icons.account_balance_wallet_outlined,
  ),
  ShellDestination(
    path: '/expenses',
    label: (l) => l.navExpenses,
    icon: Icons.receipt_long_outlined,
  ),
  ShellDestination(
    path: '/hr',
    label: (l) => l.navEmployees,
    icon: Icons.badge_outlined,
  ),
  ShellDestination(
    path: '/reports',
    label: (l) => l.navReports,
    icon: Icons.assessment_outlined,
  ),
  ShellDestination(
    path: '/forecasts',
    label: (l) => l.navForecasts,
    icon: Icons.insights_outlined,
  ),
  ShellDestination(
    path: '/activity-log',
    label: (l) => l.navActivitylog,
    icon: Icons.history,
  ),
  ShellDestination(
    path: '/admin',
    label: (l) => l.navUsers,
    icon: Icons.admin_panel_settings_outlined,
    adminOnly: true,
  ),
  ShellDestination(
    path: '/integrations',
    label: (l) => l.navIntegrations,
    icon: Icons.extension_outlined,
    adminOnly: true,
  ),
  ShellDestination(
    path: '/settings',
    label: (l) => l.navSettings,
    icon: Icons.settings_outlined,
  ),
];

/// Authenticated shell — navigation rail + shared app bar wrapping the
/// current branch (PORTING.md §5). Hosted by `StatefulShellRoute` so each
/// branch keeps its state when switching modules.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final auth = ref.watch(authProvider);
    final isAdmin = auth.user?.isAdmin ?? false;
    final visible = [
      for (final dest in shellDestinations)
        if (!dest.adminOnly || isAdmin) dest,
    ];
    final current = shellDestinations[navigationShell.currentIndex];
    final selectedIndex = visible.indexWhere((d) => identical(d, current));

    return Scaffold(
      appBar: AppBar(
        title: Text((current.title ?? current.label)(l10n)),
        actions: [
          if (auth.user != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  auth.user!.displayName,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ),
          IconButton(
            tooltip: l10n.changePasswordTitle,
            icon: const Icon(Icons.key_outlined),
            onPressed: () => context.push('/change-password'),
          ),
          IconButton(
            tooltip: l10n.commonLogout,
            icon: const Icon(Icons.logout),
            onPressed: () => _confirmLogout(context, ref),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _NavRail(
            destinations: visible,
            selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
            onSelect: (index) {
              final branchIndex = shellDestinations.indexOf(visible[index]);
              navigationShell.goBranch(
                branchIndex,
                initialLocation: branchIndex == navigationShell.currentIndex,
              );
            },
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: navigationShell),
        ],
      ),
    );
  }
}

/// Custom left rail: a scrollable, extended-style navigation with the app
/// mark on top. Scrollable because the module list exceeds typical window
/// heights; keeps Material look with selected-state highlighting.
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
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: 208,
      color: scheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  Icon(Icons.inventory_2, color: scheme.primary),
                  const SizedBox(width: 10),
                  Text('MiniERP', style: textTheme.titleMedium),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (var i = 0; i < destinations.length; i++)
                    _NavItem(
                      label: destinations[i].label(
                        AppLocalizations.of(context)!,
                      ),
                      icon: destinations[i].icon,
                      selected: i == selectedIndex,
                      onTap: () => onSelect(i),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final foreground = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.12)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 22, color: foreground),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style:
                      (selected ? textTheme.titleSmall : textTheme.bodyMedium)
                          ?.copyWith(color: foreground),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (selected)
                Container(
                  width: 3,
                  height: 18,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
