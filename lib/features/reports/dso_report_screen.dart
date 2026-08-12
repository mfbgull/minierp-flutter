// Days Sales Outstanding report — GET /reports/dso (PORTING.md §11).
// Port of the web `DSOReport.tsx`: a metric-card summary (DSO days,
// total sales, total AR, avg invoice value) over a From/To date range.
// The web page's chart is a comparison bar chart; the Flutter port
// renders the same headline metric as a prominent card instead (the
// server does not return the previous-period/industry values the web
// chart assumes, so a chart would be misleading).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/csv_export.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/report.dart' show DSOMetric;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/date_picker_helpers.dart' show DateRangeFilter;
import '../../widgets/screen_error_panel.dart';
import '../../widgets/screen_toolbar.dart' show ScreenToolbar;
import 'report_providers.dart';

class DsoReportScreen extends ConsumerWidget {
  const DsoReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(dsoReportProvider);
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            l10n.reportsDsoreport,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        ScreenToolbar(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          filters: [
            DateRangeFilter(
              fromProvider: reportDsoFromDateProvider,
              toProvider: reportDsoToDateProvider,
            ),
          ],
          onRefresh: () => ref.invalidate(dsoReportProvider),
          actions: [
            TextButton.icon(
              onPressed: report.isLoading || report.valueOrNull == null
                  ? null
                  : () => saveCsv(
                      context,
                      suggestedName: csvSuggestedName('dso'),
                      csv: buildDsoCsv(l10n, report.valueOrNull!),
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
    AsyncValue<DSOMetric> report,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final errorMessage = switch (report) {
      AsyncError(:final error) => error is ApiError ? error.message : null,
      _ => null,
    };
    if (errorMessage != null) {
      return ScreenErrorPanel(
        message: errorMessage,
        onRetry: () => ref.invalidate(dsoReportProvider),
      );
    }
    if (report.isLoading || !report.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }

    final m = report.value!;
    final scheme = Theme.of(context).colorScheme;
    Widget card(String label, String value, IconData icon) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: scheme.primary),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ],
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
          // Headline DSO card + period line.
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.reportsDsodays,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${Formatters.number(m.dso)} ${l10n.reportsDsounit}',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.primary,
                  ),
                ),
                if (m.startDate.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${l10n.reportsPeriod}: ${Formatters.date(m.startDate)} ${l10n.commonTo} ${Formatters.date(m.endDate)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              card(
                l10n.reportsTotalsales,
                Formatters.currency(m.totalSales),
                Icons.trending_up,
              ),
              const SizedBox(width: 8),
              card(
                l10n.reportsTotalar,
                Formatters.currency(m.totalAR),
                Icons.account_balance_wallet_outlined,
              ),
              const SizedBox(width: 8),
              card(
                l10n.reportsAvginvoicevalue,
                Formatters.currency(m.avgInvoiceValue),
                Icons.pie_chart_outline,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Methodology note, mirroring the web page's subtitle.
          Text(
            l10n.reportsDsosubtitle,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
