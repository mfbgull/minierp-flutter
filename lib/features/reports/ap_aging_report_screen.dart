// AP aging report — GET /reports/ap-aging. Mirrors the AR aging report
// for supplier payables: per-supplier aging buckets in a read-only
// PlutoGrid with a summary strip above it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/csv_export.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/report.dart' show ApAgingBucket, ApAgingReport;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/client_paged_grid.dart';
import '../../widgets/date_range_picker.dart' show DateRangeFilter, DateRangeMode;
import '../../widgets/pluto_grid_screen.dart' show serialGridColumn;
import '../../widgets/screen_error_panel.dart';
import '../../widgets/screen_toolbar.dart' show ScreenToolbar;
import 'report_providers.dart';

class ApAgingReportScreen extends ConsumerStatefulWidget {
  const ApAgingReportScreen({super.key});

  @override
  ConsumerState<ApAgingReportScreen> createState() =>
      _ApAgingReportScreenState();
}

class _ApAgingReportScreenState extends ConsumerState<ApAgingReportScreen> {
  late List<PlutoColumn> _columns;
  bool _columnsReady = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_columnsReady) {
      _columns = _buildColumns(AppLocalizations.of(context)!);
      _columnsReady = true;
    }
  }

  static PlutoColumn _moneyColumn(
    String field,
    String title,
    double width,
  ) =>
      PlutoColumn(
        title: title,
        field: field,
        type: PlutoColumnType.number(format: '#,###.00'),
        width: width,
        readOnly: true,
        textAlign: PlutoColumnTextAlign.end,
        titleTextAlign: PlutoColumnTextAlign.end,
        enableContextMenu: false,
        renderer: (ctx) => Align(
          alignment: Alignment.centerRight,
          child: Text(Formatters.currency(ctx.cell.value as num? ?? 0)),
        ),
      );

  static List<PlutoColumn> _buildColumns(AppLocalizations l10n) => [
    serialGridColumn(),
    PlutoColumn(
      title: l10n.fieldsSupplier,
      field: 'supplier',
      type: PlutoColumnType.text(),
      width: 220,
      readOnly: true,
      enableContextMenu: false,
      renderer: (ctx) => Align(
        alignment: Alignment.centerLeft,
        child: Text(
          ctx.cell.value as String? ?? '',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    ),
    _moneyColumn('totalOutstanding', l10n.reportsTotaloutstanding, 150),
    _moneyColumn('current', l10n.reportsCurrent, 120),
    _moneyColumn('days1_30', l10n.reportsDays1_30, 120),
    _moneyColumn('days31_60', l10n.reportsDays31_60, 120),
    _moneyColumn('days61_90', l10n.reportsDays61_90, 120),
    _moneyColumn('daysOver90', l10n.reportsDays90plus, 120),
  ];

  PlutoRow _rowFor(ApAgingBucket bucket) => PlutoRow(
    cells: {
      'supplier': PlutoCell(
        value: bucket.supplierName.isEmpty
            ? bucket.supplierCode
            : bucket.supplierName,
      ),
      'totalOutstanding': PlutoCell(value: bucket.totalOutstanding),
      'current': PlutoCell(value: bucket.currentAmount),
      'days1_30': PlutoCell(value: bucket.days1_30),
      'days31_60': PlutoCell(value: bucket.days31_60),
      'days61_90': PlutoCell(value: bucket.days61_90),
      'daysOver90': PlutoCell(value: bucket.daysOver90),
    },
  );

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(apAgingProvider);
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(l10n, report),
        Expanded(child: _body(report)),
      ],
    );
  }

  Widget _header(AppLocalizations l10n, AsyncValue<ApAgingReport> report) {
    final scheme = Theme.of(context).colorScheme;
    final value = report.valueOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            l10n.reportsTabsAp_aging,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        ScreenToolbar(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          filters: [
            DateRangeFilter(
              mode: DateRangeMode.singleDate,
              fromProvider: reportApAgingAsOfDateProvider,
              toProvider: reportApAgingAsOfDateProvider,
              dateProvider: reportApAgingAsOfDateProvider,
            ),
          ],
          onRefresh: () => ref.invalidate(apAgingProvider),
          actions: [
            TextButton.icon(
              onPressed: report.isLoading || (value?.buckets.isEmpty ?? true)
                  ? null
                  : () => saveCsv(
                      context,
                      suggestedName: csvSuggestedName('ap-aging'),
                      csv: buildApAgingCsv(l10n, value!),
                      successMessage: l10n.reportsExported,
                      errorMessage: l10n.reportsExportfailed,
                    ),
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: Text(l10n.reportsExportcsv),
            ),
          ],
        ),
        if (value != null && value.asOfDate.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Text(
              '${l10n.reportsAsOf} ${Formatters.date(value.asOfDate)}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        if (value != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: _totalsStrip(l10n, value),
          ),
        ],
      ],
    );
  }

  /// Column totals — Current | 1-30 | 31-60 | 61-90 | 90+ | Total.
  Widget _totalsStrip(AppLocalizations l10n, ApAgingReport report) {
    final scheme = Theme.of(context).colorScheme;
    Widget cell(String label, num amount) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
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
          Text(
            Formatters.currency(amount),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.primary,
            ),
          ),
        ],
      ),
    );

    final s = report.summary;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          cell(l10n.reportsCurrent, s.currentAmount),
          const SizedBox(width: 8),
          cell(l10n.reportsDays1_30, s.total1_30),
          const SizedBox(width: 8),
          cell(l10n.reportsDays31_60, s.total31_60),
          const SizedBox(width: 8),
          cell(l10n.reportsDays61_90, s.total61_90),
          const SizedBox(width: 8),
          cell(l10n.reportsDays90plus, s.totalOver90),
          const SizedBox(width: 8),
          cell(l10n.reportsTotalpayables, s.totalPayables),
        ],
      ),
    );
  }

  Widget _body(AsyncValue<ApAgingReport> report) {
    final l10n = AppLocalizations.of(context)!;
    final errorMessage = switch (report) {
      AsyncError(:final error) => error is ApiError ? error.message : null,
      _ => null,
    };
    if (errorMessage != null) {
      return ScreenErrorPanel(
        message: errorMessage,
        onRetry: () => ref.invalidate(apAgingProvider),
      );
    }

    return ClientPagedGrid<ApAgingBucket>(
      data: report.valueOrNull?.buckets ?? const <ApAgingBucket>[],
      columns: _columns,
      gridRowFor: _rowFor,
      itemLabel: l10n.customreportsRows,
      isLoading: report.isLoading,
    );
  }
}
