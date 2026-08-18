// Balance sheet report — GET /reports/balance-sheet. Renders the
// three-section accounting identity (Assets = Liabilities + Equity)
// as labelled metric cards with a balance check indicator.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/csv_export.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/report.dart' show BalanceSheetReport;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/date_range_picker.dart' show DateRangeFilter, DateRangeMode;
import '../../widgets/screen_error_panel.dart';
import '../../widgets/screen_toolbar.dart' show ScreenToolbar;
import 'report_providers.dart';

class BalanceSheetReportScreen extends ConsumerWidget {
  const BalanceSheetReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(balanceSheetProvider);
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            l10n.reportsBalanceSheet,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        ScreenToolbar(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          filters: [
            DateRangeFilter(
              mode: DateRangeMode.singleDate,
              fromProvider: reportBalanceSheetAsOfDateProvider,
              toProvider: reportBalanceSheetAsOfDateProvider,
              dateProvider: reportBalanceSheetAsOfDateProvider,
            ),
          ],
          onRefresh: () => ref.invalidate(balanceSheetProvider),
          actions: [
            TextButton.icon(
              onPressed: report.isLoading || report.valueOrNull == null
                  ? null
                  : () => saveCsv(
                      context,
                      suggestedName: csvSuggestedName('balance-sheet'),
                      csv: buildBalanceSheetCsv(l10n, report.valueOrNull!),
                      successMessage: l10n.reportsExported,
                      errorMessage: l10n.reportsExportfailed,
                    ),
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: Text(l10n.reportsExportcsv),
            ),
          ],
        ),
        Expanded(child: _body(context, report)),
      ],
    );
  }

  Widget _body(BuildContext context, AsyncValue<BalanceSheetReport> report) {
    final l10n = AppLocalizations.of(context)!;
    final errorMessage = switch (report) {
      AsyncError(:final error) => error is ApiError ? error.message : null,
      _ => null,
    };
    if (errorMessage != null) {
      return ScreenErrorPanel(
        message: errorMessage,
        onRetry: () {},
      );
    }
    if (report.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final data = report.valueOrNull;
    if (data == null) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // As-of date
          if (data.asOfDate.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                '${l10n.reportsAsOf} ${Formatters.date(data.asOfDate)}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),

          // ── Assets ──
          _sectionHeader(context, 'Assets', scheme.primary),
          const SizedBox(height: 8),
          _metricCard(
            context,
            'Inventory',
            data.assets.inventory,
            Icons.inventory_2_outlined,
          ),
          _metricCard(
            context,
            l10n.reportsAccountsreceivablereports,
            data.assets.accountsReceivable,
            Icons.receipt_long_outlined,
          ),
          _metricCard(
            context,
            'Cash',
            data.assets.cash,
            Icons.account_balance_wallet_outlined,
          ),
          _totalRow(context, l10n.commonTotal, data.assets.total, scheme.primary),
          const SizedBox(height: 24),

          // ── Liabilities ──
          _sectionHeader(context, 'Liabilities', scheme.error),
          const SizedBox(height: 8),
          _metricCard(
            context,
            'Accounts Payable',
            data.liabilities.accountsPayable,
            Icons.shopping_cart_outlined,
          ),
          _totalRow(
            context,
            l10n.commonTotal,
            data.liabilities.total,
            scheme.error,
          ),
          const SizedBox(height: 24),

          // ── Equity ──
          _sectionHeader(context, 'Equity', scheme.tertiary),
          const SizedBox(height: 8),
          _metricCard(
            context,
            'Opening Retained Earnings',
            data.equity.openingRetainedEarnings,
            Icons.savings_outlined,
          ),
          _metricCard(
            context,
            'Net Income (YTD)',
            data.equity.netIncomeYtd,
            Icons.trending_up,
          ),
          _metricCard(
            context,
            'Revenue (YTD)',
            data.equity.revenueYtd,
            Icons.attach_money,
          ),
          _metricCard(
            context,
            'COGS (YTD)',
            data.equity.cogsYtd,
            Icons.shopping_bag_outlined,
          ),
          _metricCard(
            context,
            'Expenses (YTD)',
            data.equity.expensesYtd,
            Icons.receipt_outlined,
          ),
          _totalRow(
            context,
            l10n.commonTotal,
            data.equity.total,
            scheme.tertiary,
          ),
          const SizedBox(height: 24),

          // ── Grand totals ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              children: [
                _summaryRow(
                  context,
                  'Total Assets',
                  data.totals.totalAssets,
                  scheme.primary,
                ),
                const SizedBox(height: 8),
                _summaryRow(
                  context,
                  'Total Liabilities & Equity',
                  data.totals.totalLiabAndEquity,
                  scheme.primary,
                ),
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      data.totals.balanced
                          ? Icons.check_circle_outline
                          : Icons.error_outline,
                      color: data.totals.balanced
                          ? Colors.green
                          : scheme.error,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      data.totals.balanced ? 'Balanced' : 'Out of Balance',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: data.totals.balanced
                            ? Colors.green
                            : scheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title, Color color) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _metricCard(
    BuildContext context,
    String label,
    num amount,
    IconData icon,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: Icon(icon, color: scheme.onSurfaceVariant, size: 20),
          title: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          trailing: Text(
            Formatters.currency(amount),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _totalRow(
    BuildContext context,
    String label,
    num amount,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          Text(
            Formatters.currency(amount),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(
    BuildContext context,
    String label,
    num amount,
    Color color,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          Formatters.currency(amount),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}
