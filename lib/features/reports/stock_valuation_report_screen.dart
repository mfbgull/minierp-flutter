// Stock valuation report — GET /reports/stock-valuation (PORTING.md
// §11). Port of the web `StockValuationReport.tsx`: a read-only grid of
// per-item inventory value (batch tracked or standard-cost fallback),
// with a summary strip (total value / item counts) and a double-tap
// detail dialog. The web page's warehouse/category/valuation-method
// filters are no-ops server-side (getStockValuationReport takes no
// params), so they are omitted here.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/csv_export.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/report.dart'
    show StockValuationReport, StockValuationRow, StockValuationSummary;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/pluto_grid_screen.dart' show serialGridColumn;
import '../../widgets/screen_error_panel.dart';
import '../../widgets/screen_toolbar.dart' show ScreenToolbar;
import 'report_providers.dart';
import 'stock_valuation_detail_dialog.dart';

class StockValuationReportScreen extends ConsumerStatefulWidget {
  const StockValuationReportScreen({super.key});

  @override
  ConsumerState<StockValuationReportScreen> createState() =>
      _StockValuationReportScreenState();
}

class _StockValuationReportScreenState
    extends ConsumerState<StockValuationReportScreen> {
  /// Row id → model for the double-tap detail dialog (the report has no
  /// per-row endpoint — the dialog renders from the grid's own row data).
  final Map<int, StockValuationRow> _rowsById = {};

  /// Grid manager — rows are fed through the manager (clear + append) on
  /// provider changes, the same pattern as the expenses screen (PlutoGrid
  /// only reads its `rows` prop in initState). The `rows:` list must stay
  /// **mutable** — PlutoGrid wraps the passed list and `appendRows`
  /// mutates it, so a `const` list throws "Cannot add to an unmodifiable
  /// list".
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

  /// Pushes the provider state into the grid manager (clear + append,
  /// with the loading overlay toggled). No-op until `onLoaded`.
  void _applyReport(AsyncValue<StockValuationReport> value) {
    final manager = _manager;
    if (manager == null) return;
    manager.setShowLoading(value.isLoading);
    if (value.hasValue) {
      final loaded = value.value?.rows ?? const <StockValuationRow>[];
      // Drop stale entries from earlier fetches before repopulating.
      _rowsById.clear();
      manager.removeAllRows();
      manager.appendRows([for (final row in loaded) _rowFor(row)]);
    }
  }

  PlutoRow _rowFor(StockValuationRow row) {
    _rowsById[row.id] = row;
    return PlutoRow(
      cells: {
        'serial': PlutoCell(value: 0),
        'id': PlutoCell(value: row.id),
        'itemName': PlutoCell(value: row.itemName),
        'itemCode': PlutoCell(value: row.itemCode),
        'category': PlutoCell(value: row.itemCategory),
        'uom': PlutoCell(value: row.unitOfMeasure),
        'currentStock': PlutoCell(value: row.currentStock),
        'unitCost': PlutoCell(value: row.unitCost),
        'totalValue': PlutoCell(value: row.totalValue),
        'valuationMethod': PlutoCell(value: row.valuationMethod),
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

  static PlutoColumn _moneyColumn(String field, String title, double width) =>
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
          child: Text(
            Formatters.currency(ctx.cell.value as num? ?? 0),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      );

  static List<PlutoColumn> _buildColumns(AppLocalizations l10n) => [
    serialGridColumn(),
    PlutoColumn(
      title: l10n.inventoryItemname,
      field: 'itemName',
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
    PlutoColumn(
      title: l10n.inventoryItemcode,
      field: 'itemCode',
      type: PlutoColumnType.text(),
      width: 130,
      readOnly: true,
      enableContextMenu: false,
    ),
    PlutoColumn(
      title: l10n.fieldsCategory,
      field: 'category',
      type: PlutoColumnType.text(),
      width: 130,
      readOnly: true,
      enableContextMenu: false,
    ),
    PlutoColumn(
      title: l10n.commonUom,
      field: 'uom',
      type: PlutoColumnType.text(),
      width: 90,
      readOnly: true,
      enableContextMenu: false,
    ),
    _numberColumn('currentStock', l10n.inventoryCurrentstock, 120),
    _moneyColumn('unitCost', l10n.reportsUnitcost, 130),
    _moneyColumn('totalValue', l10n.reportsTotalvalue, 140),
    PlutoColumn(
      title: l10n.reportsValuationmethod,
      field: 'valuationMethod',
      type: PlutoColumnType.text(),
      width: 160,
      readOnly: true,
      enableContextMenu: false,
    ),
    // Hidden id column — carries the row's record id to the double-tap
    // handler (same pattern as the other read-only grids).
    PlutoColumn(
      title: '',
      field: 'id',
      type: PlutoColumnType.number(),
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
    final report = ref.watch(stockValuationReportProvider);
    final l10n = AppLocalizations.of(context)!;

    ref.listen(
      stockValuationReportProvider,
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
    AsyncValue<StockValuationReport> report,
  ) {
    final loaded = report.valueOrNull?.summary;
    final value = report.valueOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            l10n.reportsStockvaluationreport,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        ScreenToolbar(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          onRefresh: () => ref.invalidate(stockValuationReportProvider),
          actions: [
            TextButton.icon(
              onPressed: report.isLoading || (value?.rows.isEmpty ?? true)
                  ? null
                  : () => saveCsv(
                      context,
                      suggestedName: csvSuggestedName('stock-valuation'),
                      csv: buildStockValuationCsv(l10n, value!),
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

  /// Total Items | Total Value | Batch Tracked | Legacy Items.
  Widget _summaryStrip(AppLocalizations l10n, StockValuationSummary summary) {
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
          cell(l10n.reportsTotalitems, Formatters.number(summary.totalItems)),
          const SizedBox(width: 8),
          cell(
            l10n.reportsTotalinventoryvalue,
            Formatters.currency(summary.totalValue),
            valueColor: Colors.green.shade700,
          ),
          const SizedBox(width: 8),
          cell(
            l10n.reportsBatchtracked,
            Formatters.number(summary.batchTrackedItems),
          ),
          const SizedBox(width: 8),
          cell(
            l10n.reportsLegacyitems,
            Formatters.number(summary.legacyItems),
            valueColor: Colors.amber.shade800,
          ),
        ],
      ),
    );
  }

  Widget _body(AsyncValue<StockValuationReport> report) {
    final l10n = AppLocalizations.of(context)!;
    final errorMessage = switch (report) {
      AsyncError(:final error) => error is ApiError ? error.message : null,
      _ => null,
    };
    if (errorMessage != null) {
      return ScreenErrorPanel(
        message: errorMessage,
        onRetry: () => ref.invalidate(stockValuationReportProvider),
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
            _columns.firstWhere((c) => c.field == 'id'),
            true,
            notify: false,
          );
          _applyReport(ref.read(stockValuationReportProvider));
        },
        onRowDoubleTap: (event) {
          final id = (event.row.cells['id']?.value as num?)?.toInt();
          if (id == null || id <= 0) return;
          final item = _rowsById[id];
          if (item == null) return;
          showStockValuationDetailDialog(context, item: item);
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
