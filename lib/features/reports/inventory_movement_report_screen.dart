// Inventory movement report — GET /reports/inventory-movement
// (PORTING.md §11). Port of the web `InventoryMovementReport.tsx`: a
// read-only grid of stock movements with a summary strip (inbound /
// outbound / net) and a double-tap detail dialog. The web page's
// item/warehouse/movement-type filters are no-ops server-side
// (getInventoryMovementReport accepts only dates + itemId), so only the
// From/To date buttons are ported — same call as the low-stock port.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/csv_export.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/movement_type_label.dart';
import '../../data/models/report.dart'
    show
        InventoryMovementReport,
        InventoryMovementRow,
        InventoryMovementSummary;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/pluto_grid_screen.dart' show plutoGridConfigurationFor, serialGridColumn;
import '../../widgets/screen_error_panel.dart';
import '../../widgets/screen_toolbar.dart' show ScreenToolbar;
import 'inventory_movement_detail_dialog.dart';
import 'report_providers.dart';

class InventoryMovementReportScreen extends ConsumerStatefulWidget {
  const InventoryMovementReportScreen({super.key});

  @override
  ConsumerState<InventoryMovementReportScreen> createState() =>
      _InventoryMovementReportScreenState();
}

class _InventoryMovementReportScreenState
    extends ConsumerState<InventoryMovementReportScreen> {
  /// movement_no → model for the double-tap detail dialog (the report
  /// has no per-row endpoint and no numeric row id — the server keys
  /// movements by `movement_no`, so that is the grid's hidden key).
  final Map<String, InventoryMovementRow> _rowsByKey = {};

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
  void _applyReport(AsyncValue<InventoryMovementReport> value) {
    final manager = _manager;
    if (manager == null) return;
    manager.setShowLoading(value.isLoading);
    if (value.hasValue) {
      final loaded = value.value?.rows ?? const <InventoryMovementRow>[];
      _rowsByKey.clear();
      manager.removeAllRows();
      manager.appendRows([for (final row in loaded) _rowFor(row)]);
    }
  }

  PlutoRow _rowFor(InventoryMovementRow row) {
    _rowsByKey[row.movementNo] = row;
    return PlutoRow(
      cells: {
        'serial': PlutoCell(value: 0),
        'key': PlutoCell(value: row.movementNo),
        'movementDate': PlutoCell(value: row.movementDate),
        'itemName': PlutoCell(value: row.itemName),
        'itemCode': PlutoCell(value: row.itemCode),
        'warehouse': PlutoCell(value: row.warehouseName),
        'movementType': PlutoCell(value: row.movementType),
        'quantity': PlutoCell(value: row.quantity),
        'unitCost': PlutoCell(value: row.unitCost),
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
      field: 'movementDate',
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
      width: 120,
      readOnly: true,
      enableContextMenu: false,
    ),
    PlutoColumn(
      title: l10n.fieldsWarehouse,
      field: 'warehouse',
      type: PlutoColumnType.text(),
      width: 150,
      readOnly: true,
      enableContextMenu: false,
    ),
    PlutoColumn(
      title: l10n.reportsMovementtype,
      field: 'movementType',
      type: PlutoColumnType.text(),
      width: 120,
      readOnly: true,
      enableContextMenu: false,
      renderer: (ctx) => Builder(
        builder: (cellContext) {
          final type = ctx.cell.value as String? ?? '';
          final l10n = AppLocalizations.of(cellContext)!;
          return Align(
            alignment: Alignment.centerLeft,
            child: Text(
              movementTypeLabel(l10n, type),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          );
        },
      ),
    ),
    _numberColumn('quantity', l10n.fieldsQuantity, 90),
    _moneyColumn('unitCost', l10n.reportsUnitcost, 120),
    // Hidden key column — carries the row's movement_no to the
    // double-tap handler (same pattern as the other read-only grids).
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
    final report = ref.watch(inventoryMovementReportProvider);
    final l10n = AppLocalizations.of(context)!;

    ref.listen(
      inventoryMovementReportProvider,
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
    AsyncValue<InventoryMovementReport> report,
  ) {
    final loaded = report.valueOrNull?.summary;
    final value = report.valueOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            l10n.reportsInventorymovementreport,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        ScreenToolbar(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          onRefresh: () => ref.invalidate(inventoryMovementReportProvider),
          actions: [
            TextButton.icon(
              onPressed: report.isLoading || (value?.rows.isEmpty ?? true)
                  ? null
                  : () => saveCsv(
                      context,
                      suggestedName: csvSuggestedName('inventory-movement'),
                      csv: buildInventoryMovementCsv(l10n, value!),
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

  /// Inbound | Outbound | Net Movement.
  Widget _summaryStrip(
    AppLocalizations l10n,
    InventoryMovementSummary summary,
  ) {
    final scheme = Theme.of(context).colorScheme;
    Widget cell(String label, num value, {Color? valueColor}) => Container(
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
            Formatters.number(value),
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
            l10n.reportsTotalinbound,
            summary.totalInbound,
            valueColor: Colors.green.shade700,
          ),
          const SizedBox(width: 8),
          cell(
            l10n.reportsTotaloutbound,
            summary.totalOutbound,
            valueColor: Colors.red.shade700,
          ),
          const SizedBox(width: 8),
          cell(l10n.reportsNetmovement, summary.netMovement),
        ],
      ),
    );
  }

  Widget _body(AsyncValue<InventoryMovementReport> report) {
    final l10n = AppLocalizations.of(context)!;
    final errorMessage = switch (report) {
      AsyncError(:final error) => error is ApiError ? error.message : null,
      _ => null,
    };
    if (errorMessage != null) {
      return ScreenErrorPanel(
        message: errorMessage,
        onRetry: () => ref.invalidate(inventoryMovementReportProvider),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: PlutoGrid(
        configuration: plutoGridConfigurationFor(context),
        columns: _columns,
        rows: <PlutoRow>[],
        onLoaded: (event) {
          _manager = event.stateManager;
          _manager?.hideColumn(
            _columns.firstWhere((c) => c.field == 'key'),
            true,
            notify: false,
          );
          _applyReport(ref.read(inventoryMovementReportProvider));
        },
        onRowDoubleTap: (event) {
          final key = event.row.cells['key']?.value as String? ?? '';
          if (key.isEmpty) return;
          final row = _rowsByKey[key];
          if (row == null) return;
          showInventoryMovementDetailDialog(context, row: row);
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
