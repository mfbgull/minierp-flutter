// KPI card catalog — the single source of truth for every configurable
// dashboard stat card (spec §4.1). Each card is identified by a stable
// block `id` (persisted in the user's dashboard layout), maps to a
// `/dashboard/kpi?metric=` value, and carries its own label (l10n key),
// icon, and display format.
//
// The catalog drives both the KPI strip (visible cards, in layout
// order) and the customizer dialog (all cards, searchable). The
// curated default (§3) shows Stock Value · Sales Revenue · Gross
// Profit · PO's — the four cards below with `defaultVisible: true`.

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// How a card's raw KPI value should be displayed.
enum KpiCardFormat { currency, number, percent, ratio }

/// One configurable KPI card definition.
class KpiCardDefinition {
  const KpiCardDefinition({
    required this.id,
    required this.metric,
    required this.labelKey,
    required this.icon,
    required this.format,
    this.defaultVisible = false,
    this.hintKey,
  });

  /// Stable block id — persisted in the dashboard layout (e.g.
  /// `kpi_stock_value`). Never change after release; unknown ids in a
  /// saved layout are ignored (forward-compat, spec §8).
  final String id;

  /// The `/dashboard/kpi?metric=` value this card fetches.
  final String metric;

  /// AppLocalizations getter name — the card label (spec: titles come
  /// from l10n keys, never user text).
  final String labelKey;

  final IconData icon;

  final KpiCardFormat format;

  /// On in the curated default layout (§3).
  final bool defaultVisible;

  /// Optional tooltip (l10n key), e.g. explaining what the value means.
  final String? hintKey;
}

/// All 11 configurable KPI cards — catalog order is the dialog order
/// and the fallback strip order when a user's layout doesn't specify one.
const List<KpiCardDefinition> kpiCardCatalog = [
  KpiCardDefinition(
    id: 'kpi_total_items',
    metric: 'total_active_items',
    labelKey: 'dashboardcardTotalitems',
    icon: Icons.inventory_2_outlined,
    format: KpiCardFormat.number,
  ),
  KpiCardDefinition(
    id: 'kpi_stock_value',
    metric: 'stock_value',
    labelKey: 'dashboardcardStockvalue',
    icon: Icons.paid_outlined,
    format: KpiCardFormat.currency,
    defaultVisible: true,
  ),
  KpiCardDefinition(
    id: 'kpi_sales_revenue',
    metric: 'sales_revenue',
    labelKey: 'dashboardcardSalesrevenue',
    icon: Icons.trending_up,
    format: KpiCardFormat.currency,
    defaultVisible: true,
  ),
  KpiCardDefinition(
    id: 'kpi_gross_profit',
    metric: 'gross_profit',
    labelKey: 'dashboardcardGrossprofit',
    icon: Icons.monetization_on_outlined,
    format: KpiCardFormat.currency,
    defaultVisible: true,
  ),
  KpiCardDefinition(
    id: 'kpi_purchase_orders',
    metric: 'purchase_orders',
    labelKey: 'dashboardcardPurchases',
    icon: Icons.shopping_cart_outlined,
    format: KpiCardFormat.currency,
    defaultVisible: true,
    hintKey: 'dashboardPurchaseOrdersHint',
  ),
  KpiCardDefinition(
    id: 'kpi_wh_stock',
    metric: 'warehouse_stock',
    labelKey: 'dashboardcardWarehousestock',
    icon: Icons.warehouse_outlined,
    format: KpiCardFormat.number,
  ),
  KpiCardDefinition(
    id: 'kpi_ar',
    metric: 'outstanding_receivables',
    labelKey: 'dashboardcardAr',
    // Not account_balance_wallet_outlined — that's the Payments rail
    // icon the tests tap to navigate; the AR card must keep a distinct
    // glyph or the strip duplicates the rail icon on screen.
    icon: Icons.account_balance,
    format: KpiCardFormat.currency,
    hintKey: 'dashboardArHint',
  ),
  KpiCardDefinition(
    id: 'kpi_inventory_turnover',
    metric: 'inventory_turnover',
    labelKey: 'dashboardcardInventoryturnover',
    icon: Icons.autorenew,
    format: KpiCardFormat.ratio,
  ),
  KpiCardDefinition(
    id: 'kpi_avg_days_to_pay',
    metric: 'avg_days_to_pay',
    labelKey: 'dashboardcardAvgtodayspay',
    icon: Icons.schedule_outlined,
    format: KpiCardFormat.number,
  ),
  KpiCardDefinition(
    id: 'kpi_stock_health',
    metric: 'stock_health',
    labelKey: 'dashboardcardStockhealth',
    icon: Icons.health_and_safety_outlined,
    format: KpiCardFormat.percent,
  ),
  KpiCardDefinition(
    id: 'kpi_monthly_revenue',
    metric: 'monthly_revenue',
    labelKey: 'dashboardcardMonthlyrevenue',
    icon: Icons.calendar_month_outlined,
    format: KpiCardFormat.currency,
  ),
  KpiCardDefinition(
    id: 'kpi_net_profit',
    metric: 'net_profit',
    labelKey: 'dashboardcardNetprofit',
    // Not account_balance_wallet_outlined (Payments rail) — the P&L
    // icon stays distinct for navigation.
    icon: Icons.trending_down,
    format: KpiCardFormat.currency,
  ),
  KpiCardDefinition(
    id: 'kpi_expenses',
    metric: 'expenses',
    labelKey: 'dashboardcardExpenses',
    icon: Icons.payments_outlined,
    format: KpiCardFormat.currency,
  ),
  KpiCardDefinition(
    id: 'kpi_payables',
    metric: 'outstanding_payables',
    labelKey: 'dashboardcardPayables',
    icon: Icons.assignment_outlined,
    format: KpiCardFormat.currency,
  ),
  KpiCardDefinition(
    id: 'kpi_customers',
    metric: 'total_customers',
    labelKey: 'dashboardcardCustomers',
    icon: Icons.group_outlined,
    format: KpiCardFormat.number,
  ),
  KpiCardDefinition(
    id: 'kpi_low_stock',
    metric: 'low_stock_count',
    labelKey: 'dashboardcardLowstockcount',
    icon: Icons.warning_amber_outlined,
    format: KpiCardFormat.number,
  ),
];

/// Lookup by block id — the strip and dialog resolve a saved layout
/// block back to its catalog definition.
final Map<String, KpiCardDefinition> kpiCardById = {
  for (final def in kpiCardCatalog) def.id: def,
};

/// Resolves a catalog [labelKey] to its localized text.
String kpiCardLabel(AppLocalizations l10n, String labelKey) {
  switch (labelKey) {
    case 'dashboardcardTotalitems':
      return l10n.dashboardcardTotalitems;
    case 'dashboardcardStockvalue':
      return l10n.dashboardcardStockvalue;
    case 'dashboardcardSalesrevenue':
      return l10n.dashboardcardSalesrevenue;
    case 'dashboardcardGrossprofit':
      return l10n.dashboardcardGrossprofit;
    case 'dashboardcardPurchases':
      return l10n.dashboardcardPurchases;
    case 'dashboardcardWarehousestock':
      return l10n.dashboardcardWarehousestock;
    case 'dashboardcardAr':
      return l10n.dashboardcardAr;
    case 'dashboardcardInventoryturnover':
      return l10n.dashboardcardInventoryturnover;
    case 'dashboardcardAvgtodayspay':
      return l10n.dashboardcardAvgtodayspay;
    case 'dashboardcardStockhealth':
      return l10n.dashboardcardStockhealth;
    case 'dashboardcardMonthlyrevenue':
      return l10n.dashboardcardMonthlyrevenue;
    case 'dashboardcardNetprofit':
      return l10n.dashboardcardNetprofit;
    case 'dashboardcardExpenses':
      return l10n.dashboardcardExpenses;
    case 'dashboardcardPayables':
      return l10n.dashboardcardPayables;
    case 'dashboardcardCustomers':
      return l10n.dashboardcardCustomers;
    case 'dashboardcardLowstockcount':
      return l10n.dashboardcardLowstockcount;
    default:
      return labelKey;
  }
}

/// Resolves a catalog [hintKey] to its localized text (or null when the
/// card has no tooltip).
String? kpiCardHint(AppLocalizations l10n, String? hintKey) {
  switch (hintKey) {
    case 'dashboardPurchaseOrdersHint':
      return l10n.dashboardPurchaseOrdersHint;
    case 'dashboardArHint':
      return l10n.dashboardArHint;
    default:
      return null;
  }
}
