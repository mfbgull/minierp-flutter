// Sales module shell — hosts the invoices grid, the sales-orders grid,
// the quotations grid and the invoice-returns grid as tabs (the web app
// pairs `/sales/invoice*`, `/sales-orders`, `/quotations` and
// `/sales/returns` in the same module). The invoices grid was the branch
// root (the pre-shell `/sales` screen), so it is the default tab.

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../quotations/quotations_screen.dart';
import '../sales/invoice_returns_screen.dart';
import '../sales/sales_screen.dart';
import 'sales_orders_screen.dart';

class SalesShell extends StatefulWidget {
  const SalesShell({super.key});

  @override
  State<SalesShell> createState() => _SalesShellState();
}

class _SalesShellState extends State<SalesShell> {
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
          onDestinationSelected: (i) => setState(() => _index = i),
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
            ],
          ),
        ),
      ],
    );
  }
}
