// Purchasing module shell — hosts the purchase-orders, direct-purchases
// and purchase-returns grids as tabs (the web app pairs `/purchases`,
// `/purchase-returns` and `/purchase-orders` in the same module).
// Purchase orders is the branch root (the pre-shell `/purchasing`
// screen), so it is the default tab.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../purchase_orders/purchase_orders_screen.dart';
import '../shell/module_refresh.dart' show moduleTabRefreshOnVisit;
import 'purchase_returns_screen.dart';
import 'purchases_screen.dart';

class PurchasingShell extends ConsumerStatefulWidget {
  const PurchasingShell({super.key});

  @override
  ConsumerState<PurchasingShell> createState() => _PurchasingShellState();
}

class _PurchasingShellState extends ConsumerState<PurchasingShell> {
  // Purchase orders is the branch root (the pre-shell `/purchasing`
  // screen) — the returns view is reachable via the tabs.
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
            // Refresh the clicked tab's data (the IndexedStack keeps
            // every tab alive, so its providers would stay cached).
            moduleTabRefreshOnVisit['/purchasing']?[i].call(ref);
          },
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.receipt_long_outlined),
              selectedIcon: const Icon(Icons.receipt_long),
              label: l10n.navPurchaseorders,
            ),
            NavigationDestination(
              icon: const Icon(Icons.shopping_cart_outlined),
              selectedIcon: const Icon(Icons.shopping_cart),
              label: l10n.navPurchases,
            ),
            NavigationDestination(
              icon: const Icon(Icons.assignment_return_outlined),
              selectedIcon: const Icon(Icons.assignment_return),
              label: l10n.navPurchasereturns,
            ),
          ],
        ),
        Expanded(
          child: IndexedStack(
            index: _index,
            children: [
              PurchaseOrdersScreen(),
              PurchasesScreen(),
              PurchaseReturnsScreen(),
            ],
          ),
        ),
      ],
    );
  }
}
