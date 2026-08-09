// Sales by customer report — GET /reports/sales-by-customer (PORTING.md
// §11). Port of the web `SalesByCustomerReport.tsx`: a read-only grid of
// per-customer sales over a date range (the endpoint requires both
// dates and returns a bare array). From/To date buttons refetch via the
// providers, mirroring the sales-summary screen; a double-tap opens the
// customer detail dialog with contact + sales stats.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/csv_export.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/report.dart' show SalesByCustomerRow;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/date_picker_helpers.dart' show ReportDateRangeFilter;
import '../../widgets/pluto_grid_screen.dart' show serialGridColumn;
import '../../widgets/screen_error_panel.dart';
import 'report_providers.dart';
import 'sales_by_customer_detail_dialog.dart';

class SalesByCustomerReportScreen extends ConsumerStatefulWidget {
  const SalesByCustomerReportScreen({super.key});

  @override
  ConsumerState<SalesByCustomerReportScreen> createState() =>
      _SalesByCustomerReportScreenState();
}

class _SalesByCustomerReportScreenState
    extends ConsumerState<SalesByCustomerReportScreen> {
  /// Row key → model for the double-tap detail dialog (the report has no
  /// per-row endpoint — the dialog renders from the grid's own row data).
  /// Keyed by customer code when present, else the row index.
  final Map<String, SalesByCustomerRow> _rowsByKey = {};

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
  void _applyRows(AsyncValue<List<SalesByCustomerRow>> value) {
    final manager = _manager;
    if (manager == null) return;
    manager.setShowLoading(value.isLoading);
    if (value.hasValue) {
      final loaded = value.value ?? const <SalesByCustomerRow>[];
      // Drop stale entries from earlier fetches before repopulating.
      _rowsByKey.clear();
      manager.removeAllRows();
      manager.appendRows([
        for (var i = 0; i < loaded.length; i++) _rowFor(loaded[i], i),
      ]);
    }
  }

  PlutoRow _rowFor(SalesByCustomerRow row, int index) {
    final key = row.customerCode.isEmpty ? 'row-$index' : row.customerCode;
    _rowsByKey[key] = row;
    return PlutoRow(
      cells: {
        'serial': PlutoCell(value: index + 1),
        'key': PlutoCell(value: key),
        'customerName': PlutoCell(value: row.customerName),
        'customerCode': PlutoCell(value: row.customerCode),
        'email': PlutoCell(value: row.email),
        'phone': PlutoCell(value: row.phone),
        'totalInvoices': PlutoCell(value: row.totalInvoices),
        'totalSales': PlutoCell(value: row.totalSales),
        'totalItems': PlutoCell(value: row.totalItems),
        'averageOrderValue': PlutoCell(value: row.averageOrderValue),
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

  static List<PlutoColumn> _buildColumns(AppLocalizations l10n) => [
    serialGridColumn(),
    PlutoColumn(
      title: l10n.fieldsCustomer,
      field: 'customerName',
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
      title: l10n.fieldsCustomerCode,
      field: 'customerCode',
      type: PlutoColumnType.text(),
      width: 120,
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
      width: 130,
      readOnly: true,
      enableContextMenu: false,
    ),
    _numberColumn('totalInvoices', l10n.reportsTotalinvoices, 110),
    _moneyColumn('totalSales', l10n.reportsTotalsales, 130),
    _numberColumn('totalItems', l10n.reportsItems, 100),
    _moneyColumn('averageOrderValue', l10n.reportsAvgordervalue, 140),
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
    final report = ref.watch(salesByCustomerReportProvider);
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;

    ref.listen(
      salesByCustomerReportProvider,
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
                  l10n.reportsSalesbycustomerreport,
                  style: textTheme.titleLarge,
                ),
              ),
              // From / To date buttons — same pattern as the sales
              // summary screen's date filters; writing the providers
              // refetches.
              ReportDateRangeFilter(
                fromProvider: reportSalesByCustomerFromDateProvider,
                toProvider: reportSalesByCustomerToDateProvider,
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed:
                    report.isLoading || (report.valueOrNull?.isEmpty ?? true)
                    ? null
                    : () => saveCsv(
                        context,
                        suggestedName: csvSuggestedName('sales-by-customer'),
                        csv: buildSalesByCustomerCsv(l10n, report.valueOrNull!),
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

  Widget _body(AsyncValue<List<SalesByCustomerRow>> report) {
    final l10n = AppLocalizations.of(context)!;
    final errorMessage = switch (report) {
      AsyncError(:final error) => error is ApiError ? error.message : null,
      _ => null,
    };
    if (errorMessage != null) {
      return ScreenErrorPanel(
        message: errorMessage,
        onRetry: () => ref.invalidate(salesByCustomerReportProvider),
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
          _applyRows(ref.read(salesByCustomerReportProvider));
        },
        onRowDoubleTap: (event) {
          final key = event.row.cells['key']?.value as String?;
          if (key == null || key.isEmpty) return;
          final customer = _rowsByKey[key];
          if (customer == null) return;
          showSalesByCustomerDetailDialog(context, customer: customer);
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
