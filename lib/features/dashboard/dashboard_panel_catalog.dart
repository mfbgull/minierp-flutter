// Panel + cash strip catalog — the definitions behind the dashboard's
// content panels and cash & bank strip (spec §4.2–4.3). Each panel is a
// configurable block in the user's dashboard layout, identified by a
// stable block `id`, carrying a row (1 = Sales vs Purchases + AR,
// 2 = Stock by Category + Top Customers + Low Stock), a flex ratio, and
// an l10n-keyed label.
//
// Like the KPI catalog, this drives both the dashboard (which panels
// render, in what row order, at what width) and the customizer dialog
// (which panels are listed under "Panels" / "Cash & Bank").

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// One configurable dashboard panel definition.
class DashboardPanelDefinition {
  const DashboardPanelDefinition({
    required this.id,
    required this.labelKey,
    required this.row,
    required this.flex,
    required this.icon,
    this.defaultVisible = false,
    this.hintKey,
  });

  /// Stable block id — persisted in the dashboard layout (e.g.
  /// `panel_sales_purchases`). Never change after release.
  final String id;

  /// AppLocalizations getter name — the panel title (spec §9: titles
  /// come from l10n keys, never user text).
  final String labelKey;

  /// Which dashboard row this panel belongs to (1 or 2). Panels reorder
  /// within their own row only (spec §2).
  final int row;

  /// Width ratio within its row (spec §6.3: panel flex 1/2/3).
  final int flex;

  final IconData icon;

  /// On in the curated default layout (§3).
  final bool defaultVisible;

  /// Optional tooltip (l10n key).
  final String? hintKey;
}

/// The 5 configurable content panels — catalog order is the dialog
/// order and the default order within each row.
const List<DashboardPanelDefinition> panelCatalog = [
  DashboardPanelDefinition(
    id: 'panel_sales_purchases',
    labelKey: 'dashboardcardPanelSalespurchases',
    row: 1,
    flex: 3,
    icon: Icons.bar_chart,
    defaultVisible: true,
  ),
  DashboardPanelDefinition(
    id: 'panel_ar_aging',
    labelKey: 'dashboardcardPanelArAging',
    row: 1,
    flex: 2,
    // Not account_balance_wallet_outlined — same reason as the AR KPI
    // card: the Payments rail icon must stay unique for navigation.
    icon: Icons.account_balance,
    defaultVisible: true,
  ),
  DashboardPanelDefinition(
    id: 'panel_stock_by_category',
    labelKey: 'dashboardcardPanelStockbycategory',
    row: 2,
    flex: 2,
    icon: Icons.pie_chart_outline,
  ),
  DashboardPanelDefinition(
    id: 'panel_top_customers',
    labelKey: 'dashboardcardPanelTopcustomers',
    row: 2,
    flex: 3,
    icon: Icons.people_outline,
  ),
  DashboardPanelDefinition(
    id: 'panel_low_stock',
    labelKey: 'dashboardcardPanelLowstock',
    row: 2,
    flex: 2,
    icon: Icons.warning_amber_outlined,
    defaultVisible: true,
  ),
  DashboardPanelDefinition(
    id: 'panel_expiry_alerts',
    labelKey: 'dashboardcardPanelExpiryalerts',
    row: 2,
    flex: 2,
    icon: Icons.event_busy_outlined,
    defaultVisible: true,
  ),
];

/// The cash & bank strip — a single fixed block at the top of the
/// dashboard body. Show/hide only; no reorder (spec §4.3, §6.5).
class DashboardCashStripDefinition {
  const DashboardCashStripDefinition({
    required this.id,
    required this.labelKey,
    this.defaultVisible = true,
  });

  final String id;
  final String labelKey;
  final bool defaultVisible;
}

const DashboardCashStripDefinition cashStripDefinition =
    DashboardCashStripDefinition(
      id: 'cash_strip',
      labelKey: 'dashboardcardCashstrip',
    );

/// Lookup by block id — the dashboard and dialog resolve a saved layout
/// block back to its panel definition.
final Map<String, DashboardPanelDefinition> panelById = {
  for (final def in panelCatalog) def.id: def,
};

/// Resolves a panel [labelKey] to its localized text.
String dashboardPanelLabel(AppLocalizations l10n, String labelKey) {
  switch (labelKey) {
    case 'dashboardcardPanelSalespurchases':
      return l10n.dashboardcardPanelSalespurchases;
    case 'dashboardcardPanelArAging':
      return l10n.dashboardcardPanelArAging;
    case 'dashboardcardPanelStockbycategory':
      return l10n.dashboardcardPanelStockbycategory;
    case 'dashboardcardPanelTopcustomers':
      return l10n.dashboardcardPanelTopcustomers;
    case 'dashboardcardPanelLowstock':
      return l10n.dashboardcardPanelLowstock;
    case 'dashboardcardPanelExpiryalerts':
      return l10n.dashboardcardPanelExpiryalerts;
    case 'dashboardcardCashstrip':
      return l10n.dashboardcardCashstrip;
    default:
      return labelKey;
  }
}

/// Resolves a panel [hintKey] to its localized text (or null).
String? dashboardPanelHint(AppLocalizations l10n, String? hintKey) => null;
