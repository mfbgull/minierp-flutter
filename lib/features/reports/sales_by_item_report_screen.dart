// Sales by item report — GET /reports/sales-by-item (PORTING.md §11).
// Port of the web `SalesByItemReport.tsx`: a read-only grid of per-item
// sales over a date range (the endpoint requires both dates and returns
// a bare array). From/To date buttons refetch via the providers,
// mirroring the sales-by-customer screen; a double-tap opens the item
// detail dialog with the sales stats.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/csv_export.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/report.dart' show SalesByItemRow;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/date_range_picker.dart' show DateRangeFilter;
import '../../widgets/pluto_grid_screen.dart' show serialGridColumn;
import '../../widgets/screen_error_panel.dart';
import '../../widgets/screen_toolbar.dart' show ScreenToolbar;
import 'report_providers.dart';
import 'sales_by_item_detail_dialog.dart';

class SalesByItemReportScreen extends ConsumerStatefulWidget {
  const SalesByItemReportScreen({super.key});

  @override
  ConsumerState<SalesByItemReportScreen> createState() =>
      _SalesByItemReportScreenState();
}

class _SalesByItemReportScreenState
    extends ConsumerState<SalesByItemReportScreen> {
  /// Row key → model for the double-tap detail dialog (the report has no
  /// per-row endpoint — the dialog renders from the grid's own row data).
  /// Keyed by item code when present, else the row index.
  final Map<String, SalesByItemRow> _rowsByKey = {};

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

  void _applyRows(AsyncValue<List<SalesByItemRow>> value) {
    final manager = _manager;
    if (manager == null) return;
    manager.setShowLoading(value.isLoading);
    if (value.hasValue) {
      final loaded = value.value ?? const <SalesByItemRow>[];
      _rowsByKey.clear();
      manager.removeAllRows();
      manager.appendRows([
        for (var i = 0; i < loaded.length; i++) _rowFor(loaded[i], i),
      ]);
    }
  }

  PlutoRow _rowFor(SalesByItemRow row, int index) {
    final key = row.itemCode.isEmpty ? 'row-$index' : row.itemCode;
    _rowsByKey[key] = row;
    return PlutoRow(
      cells: {
        'serial': PlutoCell(value: index + 1),
        'key': PlutoCell(value: key),
        'itemName': PlutoCell(value: row.itemName),
        'itemCode': PlutoCell(value: row.itemCode),
        'itemCategory': PlutoCell(value: row.itemCategory),
        'totalQuantitySold': PlutoCell(value: row.totalQuantitySold),
        'totalSales': PlutoCell(value: row.totalSales),
        'averageSellingPrice': PlutoCell(value: row.averageSellingPrice),
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
      field: 'itemCategory',
      type: PlutoColumnType.text(),
      width: 150,
      readOnly: true,
      enableContextMenu: false,
    ),
    _numberColumn('totalQuantitySold', l10n.reportsTotalquantitysold, 150),
    _moneyColumn('totalSales', l10n.reportsTotalsales, 140),
    _moneyColumn('averageSellingPrice', l10n.reportsAvgsellingprice, 150),
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
    final report = ref.watch(salesByItemReportProvider);
    final l10n = AppLocalizations.of(context)!;

    ref.listen(salesByItemReportProvider, (previous, next) => _applyRows(next));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            l10n.reportsSalesbyitemreport,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        ScreenToolbar(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          filters: [
            DateRangeFilter(
              fromProvider: reportSalesByItemFromDateProvider,
              toProvider: reportSalesByItemToDateProvider,
              showAllDates: false,
            ),
          ],
          onRefresh: () => ref.invalidate(salesByItemReportProvider),
          actions: [
            TextButton.icon(
              onPressed:
                  report.isLoading || (report.valueOrNull?.isEmpty ?? true)
                  ? null
                  : () => saveCsv(
                      context,
                      suggestedName: csvSuggestedName('sales-by-item'),
                      csv: buildSalesByItemCsv(l10n, report.valueOrNull!),
                      successMessage: l10n.reportsExported,
                      errorMessage: l10n.reportsExportfailed,
                    ),
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: Text(l10n.reportsExportcsv),
            ),
          ],
        ),
        Expanded(child: _body(report)),
      ],
    );
  }

  Widget _body(AsyncValue<List<SalesByItemRow>> report) {
    final l10n = AppLocalizations.of(context)!;
    final errorMessage = switch (report) {
      AsyncError(:final error) => error is ApiError ? error.message : null,
      _ => null,
    };
    if (errorMessage != null) {
      return ScreenErrorPanel(
        message: errorMessage,
        onRetry: () => ref.invalidate(salesByItemReportProvider),
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
          _applyRows(ref.read(salesByItemReportProvider));
        },
        onRowDoubleTap: (event) {
          final key = event.row.cells['key']?.value as String?;
          if (key == null || key.isEmpty) return;
          final item = _rowsByKey[key];
          if (item == null) return;
          showSalesByItemDetailDialog(context, item: item);
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
