// Cash flow report — GET /reports/cash-flow (PORTING.md §11).
// Port of the web `CashFlowReport.tsx`: three stat cards (total inflow,
// total outflow, net cash flow) over a From/To date range, plus the
// analysis note. The web page's chart is a bar chart; the Flutter port
// renders the three metrics as cards with a signed color treatment
// instead (no charting dependency needed).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/csv_export.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/report.dart' show CashFlowReport;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/date_picker_helpers.dart' show ReportDateRangeFilter;
import '../../widgets/screen_error_panel.dart';
import 'report_providers.dart';

class CashFlowReportScreen extends ConsumerWidget {
  const CashFlowReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(cashFlowReportProvider);
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.reportsCashflowreport,
                  style: textTheme.titleLarge,
                ),
              ),
              ReportDateRangeFilter(
                fromProvider: reportCashFlowFromDateProvider,
                toProvider: reportCashFlowToDateProvider,
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: report.isLoading || report.valueOrNull == null
                    ? null
                    : () => saveCsv(
                        context,
                        suggestedName: csvSuggestedName('cash-flow'),
                        csv: buildCashFlowCsv(l10n, report.valueOrNull!),
                        successMessage: l10n.reportsExported,
                        errorMessage: l10n.reportsExportfailed,
                      ),
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: Text(l10n.reportsExportcsv),
              ),
            ],
          ),
        ),
        Expanded(child: _body(context, ref, report)),
      ],
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<CashFlowReport> report,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final errorMessage = switch (report) {
      AsyncError(:final error) => error is ApiError ? error.message : null,
      _ => null,
    };
    if (errorMessage != null) {
      return ScreenErrorPanel(
        message: errorMessage,
        onRetry: () => ref.invalidate(cashFlowReportProvider),
      );
    }
    if (report.isLoading || !report.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }

    final m = report.value!;
    final scheme = Theme.of(context).colorScheme;
    final positive = m.netCashFlow >= 0;

    Widget card(
      String label,
      String value,
      IconData icon, {
      Color? valueColor,
    }) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: scheme.primary),
            const SizedBox(height: 8),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: valueColor ?? scheme.primary,
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
                l10n.reportsTotalinflow,
                Formatters.currency(m.totalInflow),
                Icons.south_west,
              ),
              const SizedBox(width: 8),
              card(
                l10n.reportsTotaloutflow,
                Formatters.currency(m.totalOutflow),
                Icons.north_east,
                valueColor: m.totalOutflow > 0 ? scheme.error : scheme.primary,
              ),
              const SizedBox(width: 8),
              card(
                l10n.reportsNetcashflow,
                Formatters.currency(m.netCashFlow),
                positive ? Icons.trending_up : Icons.trending_down,
                valueColor: positive ? Colors.green.shade700 : scheme.error,
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
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: (positive ? Colors.green : scheme.error).withValues(
                alpha: 0.08,
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: (positive ? Colors.green : scheme.error).withValues(
                  alpha: 0.3,
                ),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  positive ? Icons.trending_up : Icons.trending_down,
                  size: 18,
                  color: positive ? Colors.green.shade700 : scheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    positive
                        ? l10n.reportsCashflowpositive
                        : l10n.reportsCashflownegative,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
