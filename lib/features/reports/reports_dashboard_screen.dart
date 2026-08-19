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
  'profit-loss': (l) => l.reportsProfitlossreport,
  'cash-flow': (l) => l.reportsCashflowreport,
  'cash-reconciliation': (l) => l.reportsCashreconciliation,
  'ar-aging': (l) => l.reportsTabsAr_aging,
  'ar-summary': (l) => l.reportsTabsReceivables_summary,
  'customer-statements': (l) => l.reportsCustomerstatementsreport,
  'top-debtors': (l) => l.reportsTopdebtorsreport,
  'dso': (l) => l.reportsDsoreport,
  'ap-aging': (l) => l.reportsTabsAp_aging,
  'balance-sheet': (l) => l.reportsBalanceSheet,
  'trial-balance': (l) => l.reportsTabsTrial_balance,
  'general-ledger': (l) => l.reportsTabsGeneral_ledger,
  'income-statement': (l) => l.reportsTabsIncome_statement,
  'tax-summary': (l) => l.reportsTabsTax_summary,
  'batch-traceability': (l) => l.reportsTabsBatch_traceability,
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
  _ReportCategory(
    (l) => l.reportsCategoryFinancial,
    Icons.payments_outlined,
    const [
      _ReportEntry('profit-loss', Icons.trending_down),
      _ReportEntry('balance-sheet', Icons.account_balance_outlined),
      _ReportEntry('cash-flow', Icons.account_balance_wallet_outlined),
      _ReportEntry('cash-reconciliation', Icons.fact_check_outlined),
    ],
  ),
  _ReportCategory(
    (l) => l.reportsCategoryAr,
    Icons.hourglass_bottom_outlined,
    const [
      _ReportEntry('ar-summary', Icons.account_balance_wallet_outlined),
      _ReportEntry('ar-aging', Icons.schedule_outlined),
      _ReportEntry('customer-statements', Icons.description_outlined),
      _ReportEntry('top-debtors', Icons.people_alt_outlined),
      _ReportEntry('dso', Icons.gps_fixed),
    ],
  ),
  _ReportCategory(
    (l) => l.reportsCategoryAp,
    Icons.hourglass_bottom_outlined,
    const [
      _ReportEntry('ap-aging', Icons.schedule_outlined),
    ],
  ),
  _ReportCategory(
    (l) => l.reportsCategoryInventory,
    Icons.inventory_2_outlined,
    const [
      _ReportEntry('batch-traceability', Icons.bug_report_outlined),
    ],
  ),
  _ReportCategory(
    (l) => l.reportsCategoryAccounting,
    Icons.account_balance_outlined,
    const [
      _ReportEntry('trial-balance', Icons.balance_outlined),
      _ReportEntry('general-ledger', Icons.list_alt_outlined),
      _ReportEntry('income-statement', Icons.assessment_outlined),
      _ReportEntry('tax-summary', Icons.receipt_long_outlined),
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
