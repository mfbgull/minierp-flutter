import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/module_routes.dart';
import '../../data/models/invoice.dart' show Invoice;
import '../sales_orders/sales_shell.dart';
import 'invoice_print_preview_page.dart';
import 'sales_invoice_form_page.dart';

/// Sales module: the shell branch (invoices grid + sales-orders tabs)
/// plus the standalone invoice form and A4 print-preview pages.
class SalesRoutes extends ModuleRoutes {
  const SalesRoutes();

  @override
  ShellDestination get destination => ShellDestination(
    path: '/sales',
    label: (l) => l.navSales,
    icon: Icons.point_of_sale_outlined,
  );

  @override
  List<GoRoute> get branchRoutes => [
    branchRoute(
      destination: destination,
      builder: (context) => const SalesShell(),
    ),
  ];

  @override
  List<GoRoute> get standaloneRoutes => [
    // Invoice create/edit form (PORTING.md §7): standalone page outside
    // the shell (full-width form; back arrow returns to the sales grid).
    // Create when no `extra` is passed, edit when the screen pushes the
    // row's `Invoice` as `extra`.
    GoRoute(
      path: '/sales/form',
      builder: (context, state) =>
          SalesInvoiceFormPage(invoice: state.extra as Invoice?),
    ),
    // Invoice A4 print preview (PORTING.md §12): full-page PDF preview
    // opened by the sales grid's row double-tap (Print + Cancel actions).
    GoRoute(
      path: '/sales/print-preview',
      builder: (context, state) =>
          InvoicePrintPreviewPage(invoice: state.extra as Invoice),
    ),
  ];
}