// Production summary report — GET /reports/production-summary (PORTING.md
// §11). Port of the web `ProductionSummaryReport.tsx`: a 4-stat summary
// strip (orders / output / completed / scrapped) over a read-only grid of
// production runs. The endpoint requires both dates. From/To date buttons
// refetch via the providers; a double-tap opens the run detail dialog.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/csv_export.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/report.dart'
    show ProductionSummaryReport, ProductionSummaryRow, ProductionSummaryStats;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/date_picker_helpers.dart' show DateRangeFilter;
import '../../widgets/pluto_grid_screen.dart' show serialGridColumn;
import '../../widgets/screen_error_panel.dart';
import '../../widgets/screen_toolbar.dart' show ScreenToolbar;
import 'production_summary_detail_dialog.dart';
import 'report_providers.dart';

class ProductionSummaryReportScreen extends ConsumerStatefulWidget {
  const ProductionSummaryReportScreen({super.key});

  @override
  ConsumerState<ProductionSummaryReportScreen> createState() =>
      _ProductionSummaryReportScreenState();
}

class _ProductionSummaryReportScreenState
    extends ConsumerState<ProductionSummaryReportScreen> {
  /// Row key → model for the double-tap detail dialog (the report has no
  /// per-row endpoint — the dialog renders from the grid's own row data).
  /// Keyed by work order number when present, else the row index.
  final Map<String, ProductionSummaryRow> _rowsByKey = {};

  /// Grid manager — rows are fed through the manager (clear + append) on
  /// provider changes (PlutoGrid only reads its `rows` prop in initState).
  PlutoGridStateManager? _manager;

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

  void _applyReport(AsyncValue<ProductionSummaryReport> value) {
    final manager = _manager;
    if (manager == null) return;
    manager.setShowLoading(value.isLoading);
    if (value.hasValue) {
      final loaded = value.value?.rows ?? const <ProductionSummaryRow>[];
      _rowsByKey.clear();
      manager.removeAllRows();
      manager.appendRows([
        for (var i = 0; i < loaded.length; i++) _rowFor(loaded[i], i),
      ]);
    }
  }

  PlutoRow _rowFor(ProductionSummaryRow row, int index) {
    final key = row.workOrderNumber.isEmpty
        ? 'row-$index'
        : row.workOrderNumber;
    _rowsByKey[key] = row;
    return PlutoRow(
      cells: {
        'serial': PlutoCell(value: index + 1),
        'key': PlutoCell(value: key),
        'productionDate': PlutoCell(value: row.productionDate),
        'productionOrderNumber': PlutoCell(value: row.productionOrderNumber),
        'outputItemName': PlutoCell(value: row.outputItemName),
        'outputQuantity': PlutoCell(value: row.outputQuantity),
        'completedQuantity': PlutoCell(value: row.completedQuantity),
        'scrappedQuantity': PlutoCell(value: row.scrappedQuantity),
        'status': PlutoCell(value: row.status),
      },
    );
  }

  static PlutoColumn _numberColumn(String field, String title, double width) =>
      PlutoColumn(
        title: title,
        field: field,
        type: PlutoColumnType.number(format: '#,###.##'),
        width: width,
        readOnly: true,
        textAlign: PlutoColumnTextAlign.end,
        titleTextAlign: PlutoColumnTextAlign.end,
        enableContextMenu: false,
        renderer: (ctx) => Align(
          alignment: Alignment.centerRight,
          child: Text(Formatters.number(ctx.cell.value as num? ?? 0)),
        ),
      );

  static List<PlutoColumn> _buildColumns(AppLocalizations l10n) => [
    serialGridColumn(),
    PlutoColumn(
      title: l10n.reportsProductiondate,
      field: 'productionDate',
      type: PlutoColumnType.text(),
      width: 120,
      readOnly: true,
      enableContextMenu: false,
      renderer: (ctx) => Align(
        alignment: Alignment.centerLeft,
        child: Text(Formatters.date(ctx.cell.value as String? ?? '')),
      ),
    ),
    PlutoColumn(
      title: l10n.reportsProductionorder,
      field: 'productionOrderNumber',
      type: PlutoColumnType.text(),
      width: 150,
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
    PlutoColumn(
      title: l10n.reportsOutputitem,
      field: 'outputItemName',
      type: PlutoColumnType.text(),
      width: 220,
      readOnly: true,
      enableContextMenu: false,
    ),
    _numberColumn('outputQuantity', l10n.reportsOutputquantity, 130),
    _numberColumn('completedQuantity', l10n.reportsCompletedquantity, 140),
    _numberColumn('scrappedQuantity', l10n.reportsScrappedquantity, 140),
    PlutoColumn(
      title: l10n.fieldsStatus,
      field: 'status',
      type: PlutoColumnType.text(),
      width: 120,
      readOnly: true,
      enableContextMenu: false,
    ),
    // Hidden key column — carries the row's lookup key to the double-tap
    // handler (same pattern as the other read-only grids' id columns).
    PlutoColumn(
      title: '',
      field: 'key',
      type: PlutoColumnType.text(),
      width: 80,
      readOnly: true,
      renderer: (ctx) => const SizedBox.shrink(),
      enableContextMenu: false,
      enableFilterMenuItem: false,
      enableHideColumnMenuItem: false,
      enableSetColumnsMenuItem: false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(productionSummaryReportProvider);
    final l10n = AppLocalizations.of(context)!;

    ref.listen(
      productionSummaryReportProvider,
      (previous, next) => _applyReport(next),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(l10n, report),
        Expanded(child: _body(report)),
      ],
    );
  }

  Widget _header(
    AppLocalizations l10n,
    AsyncValue<ProductionSummaryReport> report,
  ) {
    final loaded = report.valueOrNull?.summary;
    final value = report.valueOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            l10n.reportsProductionsummaryreport,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        ScreenToolbar(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          filters: [
            DateRangeFilter(
              fromProvider: reportProductionFromDateProvider,
              toProvider: reportProductionToDateProvider,
            ),
          ],
          onRefresh: () => ref.invalidate(productionSummaryReportProvider),
          actions: [
            TextButton.icon(
              onPressed: report.isLoading || (value?.rows.isEmpty ?? true)
                  ? null
                  : () => saveCsv(
                      context,
                      suggestedName: csvSuggestedName('production-summary'),
                      csv: buildProductionSummaryCsv(l10n, value!),
                      successMessage: l10n.reportsExported,
                      errorMessage: l10n.reportsExportfailed,
                    ),
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: Text(l10n.reportsExportcsv),
            ),
          ],
        ),
        if (loaded != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: _summaryStrip(l10n, loaded),
          ),
        ],
      ],
    );
  }

  /// Orders | Output | Completed | Scrapped.
  Widget _summaryStrip(AppLocalizations l10n, ProductionSummaryStats summary) {
    final scheme = Theme.of(context).colorScheme;
    Widget cell(String label, String value, {Color? valueColor}) => Container(
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
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: valueColor ?? scheme.primary,
            ),
          ),
        ],
      ),
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          cell(
            l10n.reportsTotalproductionorders,
            Formatters.number(summary.totalProductionOrders),
          ),
          const SizedBox(width: 8),
          cell(
            l10n.reportsTotaloutputquantity,
            Formatters.number(summary.totalOutput),
          ),
          const SizedBox(width: 8),
          cell(
            l10n.reportsCompletedquantity,
            Formatters.number(summary.totalCompleted),
            valueColor: Colors.green.shade700,
          ),
          const SizedBox(width: 8),
          cell(
            l10n.reportsScrappedquantity,
            Formatters.number(summary.totalScrapped),
            valueColor: Colors.red.shade700,
          ),
        ],
      ),
    );
  }

  Widget _body(AsyncValue<ProductionSummaryReport> report) {
    final l10n = AppLocalizations.of(context)!;
    final errorMessage = switch (report) {
      AsyncError(:final error) => error is ApiError ? error.message : null,
      _ => null,
    };
    if (errorMessage != null) {
      return ScreenErrorPanel(
        message: errorMessage,
        onRetry: () => ref.invalidate(productionSummaryReportProvider),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: PlutoGrid(
        columns: _columns,
        rows: <PlutoRow>[],
        onLoaded: (event) {
          _manager = event.stateManager;
          _manager?.hideColumn(
            _columns.firstWhere((c) => c.field == 'key'),
            true,
            notify: false,
          );
          _applyReport(ref.read(productionSummaryReportProvider));
        },
        onRowDoubleTap: (event) {
          final key = event.row.cells['key']?.value as String?;
          if (key == null || key.isEmpty) return;
          final row = _rowsByKey[key];
          if (row == null) return;
          showProductionSummaryDetailDialog(context, row: row);
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
