import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/module_routes.dart';
import '../../l10n/app_localizations.dart';
import '../shell/module_placeholder_screen.dart';
import 'ap_aging_report_screen.dart';
import 'ar_aging_report_screen.dart';
import 'ar_summary_report_screen.dart';
import 'balance_sheet_report_screen.dart';
import 'batch_traceability_report_screen.dart';
import 'cash_flow_report_screen.dart';
import 'cash_reconciliation_screen.dart';
import 'customer_statements_report_screen.dart';
import 'dso_report_screen.dart';
import 'expiry_report_screen.dart';
import 'general_ledger_report_screen.dart';
import 'income_statement_report_screen.dart';
import 'profit_loss_report_screen.dart';
import 'reports_dashboard_screen.dart' show ReportsDashboardScreen, reportTitles;
import 'tax_summary_report_screen.dart';
import 'top_debtors_report_screen.dart';
import 'trial_balance_report_screen.dart';

class ReportsRoutes extends ModuleRoutes {
  const ReportsRoutes();

  @override
  ShellDestination get destination => ShellDestination(
    path: '/reports',
    label: (l) => l.navReports,
    icon: Icons.assessment_outlined,
  );

  @override
  List<GoRoute> get branchRoutes => [
    branchRoute(
      destination: destination,
      builder: (context) => const ReportsDashboardScreen(),
      subRoutes: [
        GoRoute(
          path: ':report',
          builder: (context, state) {
            final slug = state.pathParameters['report'] ?? '';
            return switch (slug) {
              'ar-summary' => const ArSummaryReportScreen(),
              'ap-aging' => const ApAgingReportScreen(),
              'ar-aging' => const ArAgingReportScreen(),
              'balance-sheet' => const BalanceSheetReportScreen(),
              'trial-balance' => const TrialBalanceReportScreen(),
              'general-ledger' => const GeneralLedgerReportScreen(),
              'income-statement' => const IncomeStatementReportScreen(),
              'tax-summary' => const TaxSummaryReportScreen(),
              'batch-traceability' => const BatchTraceabilityReportScreen(),
              'expiry' => const ExpiryReportScreen(),
              'dso' => const DsoReportScreen(),
              'cash-flow' => const CashFlowReportScreen(),
              'cash-reconciliation' => const CashReconciliationScreen(),
              'profit-loss' => const ProfitLossReportScreen(),
              'top-debtors' => const TopDebtorsReportScreen(),
              'customer-statements' => const CustomerStatementsReportScreen(),
              _ => ModulePlaceholderScreen(
                title:
                    reportTitles[slug]?.call(
                      AppLocalizations.of(context)!,
                    ) ??
                    slug,
              ),
            };
          },
        ),
      ],
    ),
  ];
}