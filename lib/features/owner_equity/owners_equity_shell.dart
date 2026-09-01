// Owner's equity module shell — hosts the capital and withdrawals grids
// as tabs over `/owner-equity` (the web app's owner-equity module).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../shell/module_refresh.dart' show moduleTabRefreshOnVisit;
import 'owner_capital_tab.dart';
import 'owner_withdrawals_tab.dart';
import 'personal_loan_tab.dart';

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
        NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) {
            setState(() => _index = i);
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
            NavigationDestination(
              icon: const Icon(Icons.handshake_outlined),
              selectedIcon: const Icon(Icons.handshake),
              label: l10n.equityPersonalLoans,
            ),
          ],
        ),
        Expanded(
          child: IndexedStack(
            index: _index,
            children: const [OwnerCapitalTab(), OwnerWithdrawalsTab(), PersonalLoansTab()],
          ),
        ),
      ],
    );
  }
}
