// Profit & loss report — GET /reports/profit-loss (PORTING.md §11).
// Port of the web `ProfitLossReport.tsx`: metric cards (revenue, COGS,
// gross profit, expenses, net profit, margins) over a From/To date
// range, plus an expenses-by-category breakdown (the web renders a
// chart; the Flutter port renders the same underlying `expenses` array
// as a compact table). Signed values are colored like the web.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/csv_export.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/report.dart' show ProfitLossReport;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/date_range_picker.dart' show DateRangeFilter;
import '../../widgets/screen_error_panel.dart';
import '../../widgets/screen_toolbar.dart' show ScreenToolbar;
import 'report_providers.dart';

class ProfitLossReportScreen extends ConsumerWidget {
  const ProfitLossReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(profitLossReportProvider);
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            l10n.reportsProfitlossreport,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        ScreenToolbar(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          filters: [
            DateRangeFilter(
              fromProvider: reportProfitLossFromDateProvider,
              toProvider: reportProfitLossToDateProvider,
              showAllDates: false,
            ),
          ],
          onRefresh: () => ref.invalidate(profitLossReportProvider),
          actions: [
            TextButton.icon(
              onPressed: report.isLoading || report.valueOrNull == null
                  ? null
                  : () => saveCsv(
                      context,
                      suggestedName: csvSuggestedName('profit-loss'),
                      csv: buildProfitLossCsv(l10n, report.valueOrNull!),
                      successMessage: l10n.reportsExported,
                      errorMessage: l10n.reportsExportfailed,
                    ),
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: Text(l10n.reportsExportcsv),
            ),
          ],
        ),
        Expanded(child: _body(context, ref, report)),
      ],
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<ProfitLossReport> report,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final errorMessage = switch (report) {
      AsyncError(:final error) => error is ApiError ? error.message : null,
      _ => null,
    };
    if (errorMessage != null) {
      return ScreenErrorPanel(
        message: errorMessage,
        onRetry: () => ref.invalidate(profitLossReportProvider),
      );
    }
    if (report.isLoading || !report.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }

    final m = report.value!;
    final scheme = Theme.of(context).colorScheme;
    final negativeColor = scheme.error;

    Widget card(
      String label,
      String value, {
      bool emphasize = false,
      Color? valueColor,
    }) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: valueColor ?? (emphasize ? scheme.primary : null),
              ),
            ),
          ],
        ),
      ),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              card(
                l10n.reportsTotalrevenue,
                Formatters.currency(m.totalRevenue),
                emphasize: true,
              ),
              const SizedBox(width: 8),
              card(
                l10n.reportsTotalcogs,
                Formatters.currency(m.totalCogs),
                valueColor: m.totalCogs > 0 ? negativeColor : null,
              ),
              const SizedBox(width: 8),
              card(
                l10n.reportsGrossprofit,
                Formatters.currency(m.grossProfit),
                valueColor: m.grossProfit < 0 ? negativeColor : null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              card(
                l10n.reportsTotalexpenses,
                Formatters.currency(m.totalExpenses),
                valueColor: m.totalExpenses > 0 ? negativeColor : null,
              ),
              const SizedBox(width: 8),
              card(
                l10n.reportsNetprofit,
                Formatters.currency(m.netProfit),
                emphasize: true,
                valueColor: m.netProfit < 0 ? negativeColor : null,
              ),
              const SizedBox(width: 8),
              card(
                '${l10n.reportsGrossprofitmargin} / ${l10n.reportsNetprofitmargin}',
                '${Formatters.number(m.grossProfitMargin)}% / ${Formatters.number(m.netProfitMargin)}%',
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (m.startDate.isNotEmpty)
            Text(
              '${l10n.reportsPeriod}: ${Formatters.date(m.startDate)} ${l10n.commonTo} ${Formatters.date(m.endDate)}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          if (m.expenses.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              l10n.reportsExpensesbycategory,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Column(
                children: [
                  for (final (index, e) in m.expenses.indexed) ...[
                    if (index > 0)
                      Divider(height: 1, color: scheme.outlineVariant),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              e.category,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                          Text(
                            Formatters.currency(e.total),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
