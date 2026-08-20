import 'package:flutter/material.dart';

/// Maps an entity result type to its module root path (the shell branch
/// that lists that entity). Used when an action has no explicit override.
const Map<String, String> entityModulePath = {
  'customer': '/customers',
  'supplier': '/suppliers',
  'product': '/inventory',
  'invoice': '/sales',
  'purchase_order': '/purchasing',
  'quotation': '/sales',
  'sales_order': '/sales',
  'payment': '/payments',
  'expense': '/expenses',
  'warehouse': '/inventory',
  'employee': '/hr',
  'production': '/production',
  'bom': '/production',
};

/// Display labels for each result group header.
const Map<String, String> entityGroupLabel = {
  'customer': 'CUSTOMERS',
  'supplier': 'SUPPLIERS',
  'product': 'PRODUCTS',
  'invoice': 'INVOICES',
  'purchase_order': 'PURCHASE ORDERS',
  'quotation': 'QUOTATIONS',
  'sales_order': 'SALES ORDERS',
  'payment': 'PAYMENTS',
  'expense': 'EXPENSES',
  'warehouse': 'WAREHOUSES',
  'employee': 'EMPLOYEES',
  'production': 'PRODUCTIONS',
  'bom': 'BOMS',
  'page': 'PAGES & ACTIONS',
};

/// Per-entity outline icons for the result list + action panel.
const Map<String, IconData> entityIcon = {
  'customer': Icons.people_outline,
  'supplier': Icons.local_shipping_outlined,
  'product': Icons.inventory_2_outlined,
  'invoice': Icons.receipt_long_outlined,
  'purchase_order': Icons.shopping_cart_outlined,
  'quotation': Icons.description_outlined,
  'sales_order': Icons.assignment_outlined,
  'payment': Icons.account_balance_wallet_outlined,
  'expense': Icons.receipt_long_outlined,
  'warehouse': Icons.warehouse_outlined,
  'employee': Icons.badge_outlined,
  'production': Icons.factory_outlined,
  'bom': Icons.schema_outlined,
  'page': Icons.apps_outlined,
};

/// Explicit action → path overrides. Anything not listed falls back to
/// the entity's [entityModulePath].
const Map<String, String> actionPath = {
  'create_invoice': '/sales/form',
  'create_sale': '/sales/form',
  'create_purchase': '/purchasing',
  'receive_payment': '/payments',
  'make_payment': '/payments',
  'add_customer': '/customers',
  'add_supplier': '/suppliers',
};

/// Quick shortcuts shown in the empty state (mirrors the backend's
/// `PAGE_ACTIONS` with `action: true`).
class QuickAction {
  const QuickAction(this.label, this.path, this.icon);

  final String label;
  final String path;
  final IconData icon;
}

const List<QuickAction> quickActions = [
  QuickAction('Create Invoice', '/sales/form', Icons.receipt_long_outlined),
  QuickAction('Create Purchase', '/purchasing', Icons.shopping_cart_outlined),
  QuickAction('Add Customer', '/customers', Icons.person_add_outlined),
  QuickAction('Add Supplier', '/suppliers', Icons.business_outlined),
  QuickAction('Receive Payment', '/payments', Icons.payments_outlined),
  QuickAction('Make Payment', '/payments', Icons.money_off_outlined),
];
