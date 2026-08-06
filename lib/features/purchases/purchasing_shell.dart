// Purchasing module shell — hosts the purchase-orders, direct-purchases
// and purchase-returns grids as tabs (the web app pairs `/purchases`,
// `/purchases/returns` and `/purchase-orders` in the same module).
// Purchase orders is the branch root (the pre-shell `/purchasing`
// screen), so it is the default tab.

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../purchase_orders/purchase_orders_screen.dart';
import 'purchase_returns_screen.dart';
import 'purchases_screen.dart';

class PurchasingShell extends StatefulWidget {
  const PurchasingShell({super.key});

  @override
  State<PurchasingShell> createState() => _PurchasingShellState();
}

class _PurchasingShellState extends State<PurchasingShell> {
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
          onDestinationSelected: (i) => setState(() => _index = i),
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
            children: const [
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
