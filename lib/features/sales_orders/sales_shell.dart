// Sales module shell — hosts the invoices grid, the sales-orders grid,
// the quotations grid and the invoice-returns grid as tabs (the web app
// pairs `/sales/invoice*`, `/sales-orders`, `/quotations` and
// `/sales/returns` in the same module). The invoices grid was the branch
// root (the pre-shell `/sales` screen), so it is the default tab.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../shell/module_refresh.dart' show moduleTabRefreshOnVisit;
import '../quotations/quotations_screen.dart';
import '../sales/invoice_returns_screen.dart';
import '../sales/pos_screen.dart';
import '../sales/sales_screen.dart';
import 'sales_orders_screen.dart';

class SalesShell extends ConsumerStatefulWidget {
  const SalesShell({super.key});

  @override
  ConsumerState<SalesShell> createState() => _SalesShellState();
}

class _SalesShellState extends ConsumerState<SalesShell> {
  // Invoices is the branch root (the pre-shell `/sales` screen) — the
  // sales-orders view is reachable via the tabs.
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
            moduleTabRefreshOnVisit['/sales']?[i].call(ref);
          },
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.receipt_long_outlined),
              selectedIcon: const Icon(Icons.receipt_long),
              label: l10n.navInvoices,
            ),
            NavigationDestination(
              icon: const Icon(Icons.assignment_outlined),
              selectedIcon: const Icon(Icons.assignment),
              label: l10n.navSalesorders,
            ),
            NavigationDestination(
              icon: const Icon(Icons.request_quote_outlined),
              selectedIcon: const Icon(Icons.request_quote),
              label: l10n.navQuotations,
            ),
            NavigationDestination(
              icon: const Icon(Icons.assignment_return_outlined),
              selectedIcon: const Icon(Icons.assignment_return),
              label: l10n.navInvoicereturns,
            ),
            const NavigationDestination(
              icon: Icon(Icons.point_of_sale_outlined),
              selectedIcon: Icon(Icons.point_of_sale),
              label: 'POS',
            ),
          ],
        ),
        Expanded(
          child: IndexedStack(
            index: _index,
            children: const [
              SalesScreen(),
              SalesOrdersScreen(),
              QuotationsScreen(),
              InvoiceReturnsScreen(),
              PosScreen(),
            ],
          ),
        ),
      ],
    );
  }
}
