// Owner's equity module shell — hosts the capital and withdrawals grids
// as tabs over `/owner-equity` (the web app's owner-equity module), with
// summary cards above: Total Capital In / Total Withdrawn / Net
// Contributions (= In − Out; NOT total owner equity — retained earnings
// and profit live outside this module).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import 'package:minierp_app/core/theme/app_border_radius.dart';
import '../../l10n/app_localizations.dart';
import '../shell/module_refresh.dart' show moduleTabRefreshOnVisit;
import 'owner_capital_tab.dart';
import 'owner_equity_providers.dart';
import 'owner_withdrawals_tab.dart';

class OwnersEquityShell extends ConsumerStatefulWidget {
  const OwnersEquityShell({super.key});

  @override
  ConsumerState<OwnersEquityShell> createState() => _OwnersEquityShellState();
}

class _OwnersEquityShellState extends ConsumerState<OwnersEquityShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _summaryCards(l10n),
        ),
        NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) {
            setState(() => _index = i);
            // Refresh the clicked tab's data (the IndexedStack keeps
            // every tab alive, so its providers would stay cached).
            moduleTabRefreshOnVisit['/owners-equity']?[i].call(ref);
          },
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.savings_outlined),
              selectedIcon: const Icon(Icons.savings),
              label: l10n.equityCapital,
            ),
            NavigationDestination(
              icon: const Icon(Icons.call_made_outlined),
              selectedIcon: const Icon(Icons.call_made),
              label: l10n.equityWithdrawals,
            ),
          ],
        ),
        Expanded(
          child: IndexedStack(
            index: _index,
            children: const [OwnerCapitalTab(), OwnerWithdrawalsTab()],
          ),
        ),
      ],
    );
  }

  Widget _summaryCards(AppLocalizations l10n) {
    final summary = ref.watch(equitySummaryProvider);
    final scheme = Theme.of(context).colorScheme;
    final data = summary.valueOrNull;

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: AppBorderRadius.smRadius,
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: _Stat(
                icon: Icons.savings_outlined,
                label: l10n.equityTotalcapitalin,
                value:
                    Formatters.currency(data?.totalCapitalIn ?? 0),
                color: scheme.primary,
              ),
            ),
            _statDivider(scheme),
            Expanded(
              child: _Stat(
                icon: Icons.call_made_outlined,
                label: l10n.equityTotalwithdrawn,
                value: Formatters.currency(
                  (data?.totalWithdrawnCash ?? 0) +
                      (data?.totalWithdrawnGoods ?? 0),
                ),
                color: scheme.error,
              ),
            ),
            _statDivider(scheme),
            Expanded(
              child: _Stat(
                icon: Icons.account_balance_outlined,
                label: l10n.equityNetcontributions,
                value: Formatters.currency(data?.netContributions ?? 0),
                color: scheme.tertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statDivider(ColorScheme scheme) => Container(
    width: 1,
    height: 36,
    color: scheme.outlineVariant,
  );
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
