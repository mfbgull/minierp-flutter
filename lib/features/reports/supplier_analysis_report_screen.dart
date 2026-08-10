// Supplier analysis report — GET /reports/supplier-analysis (PORTING.md
// §11). Port of the web `SupplierAnalysisReport.tsx`: a read-only grid
// of per-supplier purchasing over a date range (the endpoint requires
// both dates and returns a bare array). From/To date buttons refetch via
// the providers; the on-time delivery column color-codes the value like
// the web's delivery-rate cell class; a double-tap opens the supplier
// detail dialog.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/csv_export.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/report.dart' show SupplierAnalysisRow;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/date_picker_helpers.dart' show ReportDateRangeFilter;
import '../../widgets/pluto_grid_screen.dart' show serialGridColumn;
import '../../widgets/screen_error_panel.dart';
import 'report_providers.dart';
import 'supplier_analysis_detail_dialog.dart';

class SupplierAnalysisReportScreen extends ConsumerStatefulWidget {
  const SupplierAnalysisReportScreen({super.key});

  @override
  ConsumerState<SupplierAnalysisReportScreen> createState() =>
      _SupplierAnalysisReportScreenState();
}

class _SupplierAnalysisReportScreenState
    extends ConsumerState<SupplierAnalysisReportScreen> {
  /// Row key → model for the double-tap detail dialog (the report has no
  /// per-row endpoint — the dialog renders from the grid's own row data).
  /// Keyed by supplier code when present, else the row index.
  final Map<String, SupplierAnalysisRow> _rowsByKey = {};

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

  void _applyRows(AsyncValue<List<SupplierAnalysisRow>> value) {
    final manager = _manager;
    if (manager == null) return;
    manager.setShowLoading(value.isLoading);
    if (value.hasValue) {
      final loaded = value.value ?? const <SupplierAnalysisRow>[];
      _rowsByKey.clear();
      manager.removeAllRows();
      manager.appendRows([
        for (var i = 0; i < loaded.length; i++) _rowFor(loaded[i], i),
      ]);
    }
  }

  PlutoRow _rowFor(SupplierAnalysisRow row, int index) {
    final key = row.supplierCode.isEmpty ? 'row-$index' : row.supplierCode;
    _rowsByKey[key] = row;
    return PlutoRow(
      cells: {
        'serial': PlutoCell(value: index + 1),
        'key': PlutoCell(value: key),
        'supplierName': PlutoCell(value: row.supplierName),
        'supplierCode': PlutoCell(value: row.supplierCode),
        'email': PlutoCell(value: row.email),
        'phone': PlutoCell(value: row.phone),
        'totalOrders': PlutoCell(value: row.totalOrders),
        'totalPurchaseValue': PlutoCell(value: row.totalPurchaseValue),
        'averageOrderValue': PlutoCell(value: row.averageOrderValue),
        'onTimeDeliveryRate': PlutoCell(value: row.onTimeDeliveryRate),
        'lastPurchaseDate': PlutoCell(value: row.lastPurchaseDate),
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

  /// Delivery-rate cell — green ≥ 90, amber ≥ 75, red below (port of the
  /// web's `getDeliveryRateCellClass`).
  static Color _deliveryRateColor(num rate) => rate >= 90
      ? Colors.green.shade700
      : rate >= 75
      ? Colors.orange.shade800
      : Colors.red.shade700;

  static List<PlutoColumn> _buildColumns(AppLocalizations l10n) => [
    serialGridColumn(),
    PlutoColumn(
      title: l10n.suppliersSuppliername,
      field: 'supplierName',
      type: PlutoColumnType.text(),
      width: 200,
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
      title: l10n.suppliersSuppliercode,
      field: 'supplierCode',
      type: PlutoColumnType.text(),
      width: 130,
      readOnly: true,
      enableContextMenu: false,
    ),
    PlutoColumn(
      title: l10n.fieldsEmail,
      field: 'email',
      type: PlutoColumnType.text(),
      width: 190,
      readOnly: true,
      enableContextMenu: false,
    ),
    PlutoColumn(
      title: l10n.fieldsPhone,
      field: 'phone',
      type: PlutoColumnType.text(),
      width: 120,
      readOnly: true,
      enableContextMenu: false,
    ),
    _numberColumn('totalOrders', l10n.reportsTotalorders, 110),
    _moneyColumn('totalPurchaseValue', l10n.reportsTotalpurchasevalue, 150),
    _moneyColumn('averageOrderValue', l10n.reportsAvgordervalue, 150),
    PlutoColumn(
      title: l10n.reportsOntimedeliveryrate,
      field: 'onTimeDeliveryRate',
      type: PlutoColumnType.number(format: '#,###.##'),
      width: 160,
      readOnly: true,
      textAlign: PlutoColumnTextAlign.end,
      titleTextAlign: PlutoColumnTextAlign.end,
      enableContextMenu: false,
      renderer: (ctx) {
        final rate = ctx.cell.value as num? ?? 0;
        return Align(
          alignment: Alignment.centerRight,
          child: Text(
            '${Formatters.number(rate)}%',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: _deliveryRateColor(rate),
            ),
          ),
        );
      },
    ),
    PlutoColumn(
      title: l10n.reportsLastpurchase,
      field: 'lastPurchaseDate',
      type: PlutoColumnType.text(),
      width: 130,
      readOnly: true,
      enableContextMenu: false,
      renderer: (ctx) => Align(
        alignment: Alignment.centerLeft,
        child: Text(Formatters.date(ctx.cell.value as String? ?? '')),
      ),
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
    final report = ref.watch(supplierAnalysisReportProvider);
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;

    ref.listen(
      supplierAnalysisReportProvider,
      (previous, next) => _applyRows(next),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.reportsSupplieranalysisreport,
                  style: textTheme.titleLarge,
                ),
              ),
              ReportDateRangeFilter(
                fromProvider: reportSupplierFromDateProvider,
                toProvider: reportSupplierToDateProvider,
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed:
                    report.isLoading || (report.valueOrNull?.isEmpty ?? true)
                    ? null
                    : () => saveCsv(
                        context,
                        suggestedName: csvSuggestedName('supplier-analysis'),
                        csv: buildSupplierAnalysisCsv(l10n, report.valueOrNull!),
                        successMessage: l10n.reportsExported,
                        errorMessage: l10n.reportsExportfailed,
                      ),
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: Text(l10n.reportsExportcsv),
              ),
            ],
          ),
        ),
        Expanded(child: _body(report)),
      ],
    );
  }

  Widget _body(AsyncValue<List<SupplierAnalysisRow>> report) {
    final l10n = AppLocalizations.of(context)!;
    final errorMessage = switch (report) {
      AsyncError(:final error) => error is ApiError ? error.message : null,
      _ => null,
    };
    if (errorMessage != null) {
      return ScreenErrorPanel(
        message: errorMessage,
        onRetry: () => ref.invalidate(supplierAnalysisReportProvider),
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
          _applyRows(ref.read(supplierAnalysisReportProvider));
        },
        onRowDoubleTap: (event) {
          final key = event.row.cells['key']?.value as String?;
          if (key == null || key.isEmpty) return;
          final supplier = _rowsByKey[key];
          if (supplier == null) return;
          showSupplierAnalysisDetailDialog(context, supplier: supplier);
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
