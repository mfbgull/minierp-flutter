// AR aging report — GET /reports/ar-aging (PORTING.md §11). Renders the
// per-customer aging buckets into a read-only PlutoGrid with a summary
// strip of the column totals above it (mirroring the web's
// `ARAgingReport` + `ReceivablesSummary` shapes in one grid).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/csv_export.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/report.dart' show ArAgingBucket, ArAgingReport;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/pluto_grid_screen.dart' show serialGridColumn;
import '../../widgets/screen_error_panel.dart';
import '../../widgets/screen_toolbar.dart' show ScreenToolbar;
import 'report_providers.dart';

class ArAgingReportScreen extends ConsumerStatefulWidget {
  const ArAgingReportScreen({super.key});

  @override
  ConsumerState<ArAgingReportScreen> createState() =>
      _ArAgingReportScreenState();
}

class _ArAgingReportScreenState extends ConsumerState<ArAgingReportScreen> {
  late List<PlutoColumn> _columns;
  bool _columnsReady = false;

  /// Grid manager — rows are fed through the manager (clear + append)
  /// on provider changes, the same pattern as the expenses screen
  /// (PlutoGrid only reads its `rows` prop in initState).
  ///
  /// The grid's `rows:` list must stay **mutable** — PlutoGrid wraps the
  /// passed list and `appendRows` mutates it, so a `const` list throws
  /// "Cannot add to an unmodifiable list".
  PlutoGridStateManager? _manager;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_columnsReady) {
      _columns = _buildColumns(AppLocalizations.of(context)!);
      _columnsReady = true;
    }
  }

  static PlutoColumn _moneyColumn(
    AppLocalizations l10n,
    String field,
    String title,
    double width,
  ) => PlutoColumn(
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
      title: l10n.fieldsCustomer,
      field: 'customer',
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
    _moneyColumn(l10n, 'totalOutstanding', l10n.reportsTotaloutstanding, 150),
    _moneyColumn(l10n, 'current', l10n.reportsCurrent, 120),
    _moneyColumn(l10n, 'days1_30', l10n.reportsDays1_30, 120),
    _moneyColumn(l10n, 'days31_60', l10n.reportsDays31_60, 120),
    _moneyColumn(l10n, 'days61_90', l10n.reportsDays61_90, 120),
    _moneyColumn(l10n, 'daysOver90', l10n.reportsDays90plus, 120),
  ];

  /// Pushes the provider state into the grid manager (clear + append,
  /// with the loading overlay toggled). No-op until `onLoaded`.
  void _applyReport(AsyncValue<ArAgingReport> value) {
    final manager = _manager;
    if (manager == null) return;
    manager.setShowLoading(value.isLoading);
    if (value.hasValue) {
      final buckets = value.value?.buckets ?? const <ArAgingBucket>[];
      manager.removeAllRows();
      manager.appendRows([
        for (final bucket in buckets)
          PlutoRow(
            cells: {
              'serial': PlutoCell(value: 0),
              'customer': PlutoCell(
                value: bucket.customerName.isEmpty
                    ? bucket.customerCode
                    : bucket.customerName,
              ),
              'totalOutstanding': PlutoCell(value: bucket.totalOutstanding),
              'current': PlutoCell(value: bucket.currentAmount),
              'days1_30': PlutoCell(value: bucket.days1_30),
              'days31_60': PlutoCell(value: bucket.days31_60),
              'days61_90': PlutoCell(value: bucket.days61_90),
              'daysOver90': PlutoCell(value: bucket.daysOver90),
            },
          ),
      ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(arAgingProvider);
    final l10n = AppLocalizations.of(context)!;

    ref.listen(arAgingProvider, (previous, next) => _applyReport(next));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(l10n, report),
        Expanded(child: _body(report)),
      ],
    );
  }

  Widget _header(AppLocalizations l10n, AsyncValue<ArAgingReport> report) {
    final scheme = Theme.of(context).colorScheme;
    final value = report.valueOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            l10n.reportsTabsAr_aging,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        ScreenToolbar(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          onRefresh: () => ref.invalidate(arAgingProvider),
          actions: [
            TextButton.icon(
              onPressed: report.isLoading || (value?.buckets.isEmpty ?? true)
                  ? null
                  : () => saveCsv(
                      context,
                      suggestedName: csvSuggestedName('ar-aging'),
                      csv: buildArAgingCsv(l10n, value!),
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
  Widget _totalsStrip(AppLocalizations l10n, ArAgingReport report) {
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
          cell(l10n.reportsTotalreceivables, s.totalReceivables),
        ],
      ),
    );
  }

  Widget _body(AsyncValue<ArAgingReport> report) {
    final l10n = AppLocalizations.of(context)!;
    final errorMessage = switch (report) {
      AsyncError(:final error) => error is ApiError ? error.message : null,
      _ => null,
    };
    if (errorMessage != null) {
      return ScreenErrorPanel(
        message: errorMessage,
        onRetry: () => ref.invalidate(arAgingProvider),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: PlutoGrid(
        columns: _columns,
        rows: <PlutoRow>[],
        onLoaded: (event) {
          _manager = event.stateManager;
          _applyReport(ref.read(arAgingProvider));
        },
        noRowsWidget: Center(
          child: Text(
            l10n.commonNoresults,
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ),
      ),
    );
  }
}
