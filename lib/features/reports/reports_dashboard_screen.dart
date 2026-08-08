// Reports dashboard hub — PORTING.md §11. Port of the web
// `reports/pages/ReportsDashboard.tsx`: one card per report grouped into
// categories, navigating to `/reports/<slug>` sub-routes. Ported report
// screens render in the router's catch-all; the rest show the shared
// [ModulePlaceholderScreen] until they land (same pattern as the rail).
//
// The web page also renders a 6-stat KPI strip on top (sales summary +
// stock level + stock valuation + AR summary); that strip lands with the
// second batch of report endpoints.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';

/// Slug → localized title — the single source of truth for both the hub
/// cards and the router's placeholder title for not-yet-ported reports.
final Map<String, String Function(AppLocalizations)> reportTitles = {
  'sales-summary': (l) => l.reportsSalessummaryreport,
  'sales-by-customer': (l) => l.reportsSalesbycustomerreport,
  'sales-by-item': (l) => l.reportsSalesbyitemreport,
  'stock-level': (l) => l.reportsStocklevelreport,
  'low-stock': (l) => l.reportsLowstockalertreport,
  'stock-valuation': (l) => l.reportsStockvaluationreport,
  'inventory-movement': (l) => l.reportsInventorymovementreport,
  'profit-loss': (l) => l.reportsProfitlossreport,
  'cash-flow': (l) => l.reportsCashflowreport,
  'expenses': (l) => l.reportsExpensesreport,
  'ar-aging': (l) => l.reportsTabsAr_aging,
  'customer-statements': (l) => l.reportsCustomerstatementsreport,
  'top-debtors': (l) => l.reportsTopdebtorsreport,
  'dso': (l) => l.reportsDsoreport,
  'purchase-summary': (l) => l.reportsPurchasesummaryreport,
  'supplier-analysis': (l) => l.reportsSupplieranalysisreport,
  'production-summary': (l) => l.reportsProductionsummaryreport,
  'bom-usage': (l) => l.reportsBomusage,
};

class _ReportEntry {
  const _ReportEntry(this.slug, this.icon);

  final String slug;
  final IconData icon;
}

class _ReportCategory {
  const _ReportCategory(this.titleKey, this.icon, this.reports);

  final String Function(AppLocalizations) titleKey;
  final IconData icon;
  final List<_ReportEntry> reports;
}

/// Category groups mirroring the web dashboard (18 entries; batch
/// traceability is not part of the web hub).
final List<_ReportCategory> _reportCategories = [
  _ReportCategory((l) => l.reportsCategorySales, Icons.trending_up, const [
    _ReportEntry('sales-summary', Icons.receipt_long_outlined),
    _ReportEntry('sales-by-customer', Icons.people_outline),
    _ReportEntry('sales-by-item', Icons.inventory_2_outlined),
  ]),
  _ReportCategory(
    (l) => l.reportsCategoryInventory,
    Icons.inventory_2_outlined,
    const [
      _ReportEntry('stock-level', Icons.shelves),
      _ReportEntry('low-stock', Icons.warning_amber_outlined),
      _ReportEntry('stock-valuation', Icons.paid_outlined),
      _ReportEntry('inventory-movement', Icons.swap_vert),
    ],
  ),
  _ReportCategory(
    (l) => l.reportsCategoryFinancial,
    Icons.payments_outlined,
    const [
      _ReportEntry('profit-loss', Icons.trending_down),
      _ReportEntry('cash-flow', Icons.account_balance_wallet_outlined),
      _ReportEntry('expenses', Icons.credit_card),
    ],
  ),
  _ReportCategory(
    (l) => l.reportsCategoryAr,
    Icons.hourglass_bottom_outlined,
    const [
      _ReportEntry('ar-aging', Icons.schedule_outlined),
      _ReportEntry('customer-statements', Icons.description_outlined),
      _ReportEntry('top-debtors', Icons.people_alt_outlined),
      _ReportEntry('dso', Icons.gps_fixed),
    ],
  ),
  _ReportCategory(
    (l) => l.reportsCategoryPurchase,
    Icons.shopping_cart_outlined,
    const [
      _ReportEntry('purchase-summary', Icons.shopping_cart_checkout_outlined),
      _ReportEntry('supplier-analysis', Icons.local_shipping_outlined),
    ],
  ),
  _ReportCategory(
    (l) => l.reportsCategoryProduction,
    Icons.factory_outlined,
    const [
      _ReportEntry(
        'production-summary',
        Icons.precision_manufacturing_outlined,
      ),
      _ReportEntry('bom-usage', Icons.account_tree_outlined),
    ],
  ),
];

class ReportsDashboardScreen extends StatelessWidget {
  const ReportsDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(l10n.reportsReportsdashboard, style: textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          l10n.reportsDashboardSubtitle,
          style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 18),
        for (final category in _reportCategories) ...[
          Row(
            children: [
              Icon(category.icon, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                category.titleKey(l10n),
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Card row per category — wraps on narrow panes.
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final report in category.reports)
                  SizedBox(
                    width: 260,
                    child: _ReportCard(
                      title: reportTitles[report.slug]!(l10n),
                      icon: report.icon,
                      onTap: () => context.go('/reports/${report.slug}'),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
        ],
      ],
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(icon, size: 22, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
