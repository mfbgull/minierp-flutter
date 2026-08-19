import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/report.dart' show IncomeStatementReport;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/date_range_picker.dart' show DateRangeFilter;
import '../../widgets/screen_error_panel.dart';
import '../../widgets/screen_toolbar.dart' show ScreenToolbar;
import 'report_providers.dart';

class IncomeStatementReportScreen extends ConsumerWidget {
  const IncomeStatementReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(incomeStatementProvider);
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            l10n.reportsIncomestatement,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        ScreenToolbar(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          filters: [
            DateRangeFilter(
              fromProvider: reportIncomeStatementFromDateProvider,
              toProvider: reportIncomeStatementToDateProvider,
              showAllDates: false,
            ),
          ],
          onRefresh: () => ref.invalidate(incomeStatementProvider),
        ),
        Expanded(child: _body(context, ref, report)),
      ],
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<IncomeStatementReport> report,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final errorMessage = switch (report) {
      AsyncError(:final error) => error is ApiError ? error.message : null,
      _ => null,
    };
    if (errorMessage != null) {
      return ScreenErrorPanel(
        message: errorMessage,
        onRetry: () => ref.invalidate(incomeStatementProvider),
      );
    }
    if (report.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final data = report.valueOrNull;
    if (data == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Revenue
          _MetricCard(
            label: l10n.reportsRevenue,
            value: Formatters.currency(data.revenue),
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 12),
          // COGS
          _MetricCard(
            label: l10n.reportsCogs,
            value: Formatters.currency(data.cogs),
            color: theme.colorScheme.tertiary,
          ),
          const SizedBox(height: 12),
          // Gross Profit
          _MetricCard(
            label: l10n.reportsGrossprofit,
            value: Formatters.currency(data.grossProfit),
            color: data.grossProfit >= 0 ? theme.colorScheme.primary : theme.colorScheme.error,
            bold: true,
          ),
          const SizedBox(height: 24),
          Divider(color: theme.dividerColor),
          const SizedBox(height: 12),
          // Expenses
          _MetricCard(
            label: l10n.reportsExpenses,
            value: Formatters.currency(data.expenses),
            color: theme.colorScheme.tertiary,
          ),
          const SizedBox(height: 12),
          // Net Income
          _MetricCard(
            label: l10n.reportsNetincome,
            value: Formatters.currency(data.netIncome),
            color: data.netIncome >= 0 ? theme.colorScheme.primary : theme.colorScheme.error,
            bold: true,
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.color,
    this.bold = false,
  });

  final String label;
  final String value;
  final Color color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
