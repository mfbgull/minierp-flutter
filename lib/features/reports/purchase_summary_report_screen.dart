// Purchase summary report — GET /reports/purchase-summary (PORTING.md
// §11). Port of the web `PurchaseSummaryReport.tsx`: a read-only grid of
// purchase orders with a summary strip (orders / cost / items / avg
// order value / returns) and a double-tap detail dialog. From/To date
// buttons refetch via the providers (the endpoint requires both dates).
// The web page's supplier/item multi-select filters are no-ops
// server-side (getPurchaseSummary takes only dates), so they are
// omitted — same call as the inventory-movement port.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/csv_export.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/po_status.dart';
import '../../data/models/report.dart'
    show PurchaseSummaryReport, PurchaseSummaryRow, PurchaseSummaryStats;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/date_picker_helpers.dart' show DateRangeFilter;
import '../../widgets/pluto_grid_screen.dart' show serialGridColumn;
import '../../widgets/screen_error_panel.dart';
import '../../widgets/screen_toolbar.dart' show ScreenToolbar;
import '../../widgets/status_badge.dart';
import 'purchase_summary_detail_dialog.dart';
import 'report_providers.dart';

class PurchaseSummaryReportScreen extends ConsumerStatefulWidget {
  const PurchaseSummaryReportScreen({super.key});

  @override
  ConsumerState<PurchaseSummaryReportScreen> createState() =>
      _PurchaseSummaryReportScreenState();
}

class _PurchaseSummaryReportScreenState
    extends ConsumerState<PurchaseSummaryReportScreen> {
  /// po_id → model for the double-tap detail dialog (the report has no
  /// per-row endpoint — the dialog renders from the grid's own row data).
  final Map<int, PurchaseSummaryRow> _rowsById = {};

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
  void _applyReport(AsyncValue<PurchaseSummaryReport> value) {
    final manager = _manager;
    if (manager == null) return;
    manager.setShowLoading(value.isLoading);
    if (value.hasValue) {
      final loaded = value.value?.rows ?? const <PurchaseSummaryRow>[];
      _rowsById.clear();
      manager.removeAllRows();
      manager.appendRows([for (final row in loaded) _rowFor(row)]);
    }
  }

  PlutoRow _rowFor(PurchaseSummaryRow row) {
    _rowsById[row.poId] = row;
    return PlutoRow(
      cells: {
        'serial': PlutoCell(value: 0),
        'id': PlutoCell(value: row.poId),
        'purchaseDate': PlutoCell(value: row.purchaseDate),
        'poNumber': PlutoCell(value: row.purchaseOrderNumber),
        'supplier': PlutoCell(value: row.supplierName),
        'totalCost': PlutoCell(value: row.totalCost),
        'items': PlutoCell(value: row.totalItems),
        'received': PlutoCell(value: row.receivedAmount),
        'balance': PlutoCell(value: row.balanceAmount),
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
          child: Text(Formatters.currency(ctx.cell.value as num? ?? 0)),
        ),
      );

  static List<PlutoColumn> _buildColumns(AppLocalizations l10n) => [
    serialGridColumn(),
    PlutoColumn(
      title: l10n.fieldsDate,
      field: 'purchaseDate',
      type: PlutoColumnType.text(),
      width: 110,
      readOnly: true,
      enableContextMenu: false,
      renderer: (ctx) => Align(
        alignment: Alignment.centerLeft,
        child: Text(Formatters.date(ctx.cell.value as String? ?? '')),
      ),
    ),
    PlutoColumn(
      title: l10n.purchaseordersPono,
      field: 'poNumber',
      type: PlutoColumnType.text(),
      width: 140,
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
      title: l10n.fieldsSupplier,
      field: 'supplier',
      type: PlutoColumnType.text(),
      width: 220,
      readOnly: true,
      enableContextMenu: false,
    ),
    _moneyColumn('totalCost', l10n.reportsTotalcost, 130),
    _numberColumn('items', l10n.reportsItems, 80),
    _moneyColumn('received', l10n.reportsReceived, 130),
    _moneyColumn('balance', l10n.reportsBalance, 130),
    PlutoColumn(
      title: l10n.fieldsStatus,
      field: 'status',
      type: PlutoColumnType.text(),
      width: 140,
      readOnly: true,
      enableContextMenu: false,
      renderer: (ctx) => Builder(
        builder: (cellContext) {
          final status = ctx.cell.value as String? ?? '';
          final l10n = AppLocalizations.of(cellContext)!;
          return Align(
            alignment: Alignment.centerLeft,
            child: StatusBadge(status: poStatusLabel(l10n, status)),
          );
        },
      ),
    ),
    // Hidden id column — carries the row's po_id to the double-tap
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
    final report = ref.watch(purchaseSummaryReportProvider);
    final l10n = AppLocalizations.of(context)!;

    ref.listen(
      purchaseSummaryReportProvider,
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
    AsyncValue<PurchaseSummaryReport> report,
  ) {
    final loaded = report.valueOrNull?.summary;
    final value = report.valueOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            l10n.reportsPurchasesummaryreport,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        ScreenToolbar(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          filters: [
            DateRangeFilter(
              fromProvider: reportPurchaseFromDateProvider,
              toProvider: reportPurchaseToDateProvider,
            ),
          ],
          onRefresh: () => ref.invalidate(purchaseSummaryReportProvider),
          actions: [
            TextButton.icon(
              onPressed: report.isLoading || (value?.rows.isEmpty ?? true)
                  ? null
                  : () => saveCsv(
                      context,
                      suggestedName: csvSuggestedName('purchase-summary'),
                      csv: buildPurchaseSummaryCsv(l10n, value!),
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

  /// Orders | Cost | Items | Avg Order Value | Returns.
  Widget _summaryStrip(AppLocalizations l10n, PurchaseSummaryStats summary) {
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
          cell(l10n.reportsTotalorders, Formatters.number(summary.totalOrders)),
          const SizedBox(width: 8),
          cell(l10n.reportsTotalcost, Formatters.currency(summary.totalCost)),
          const SizedBox(width: 8),
          cell(l10n.reportsItems, Formatters.number(summary.totalItems)),
          const SizedBox(width: 8),
          cell(
            l10n.reportsAvginvoicevalue,
            Formatters.currency(summary.averageOrderValue),
          ),
          const SizedBox(width: 8),
          cell(
            l10n.reportsReturnvalue,
            Formatters.currency(summary.returnValue),
            valueColor: Colors.amber.shade800,
          ),
        ],
      ),
    );
  }

  Widget _body(AsyncValue<PurchaseSummaryReport> report) {
    final l10n = AppLocalizations.of(context)!;
    final errorMessage = switch (report) {
      AsyncError(:final error) => error is ApiError ? error.message : null,
      _ => null,
    };
    if (errorMessage != null) {
      return ScreenErrorPanel(
        message: errorMessage,
        onRetry: () => ref.invalidate(purchaseSummaryReportProvider),
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
          _applyReport(ref.read(purchaseSummaryReportProvider));
        },
        onRowDoubleTap: (event) {
          final id = (event.row.cells['id']?.value as num?)?.toInt();
          if (id == null || id <= 0) return;
          final row = _rowsById[id];
          if (row == null) return;
          showPurchaseSummaryDetailDialog(context, row: row);
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
