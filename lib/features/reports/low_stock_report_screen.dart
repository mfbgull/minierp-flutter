// Low stock report — GET /reports/low-stock (PORTING.md §11). Port of
// the web `LowStockReport.tsx`: a read-only grid of items at or below
// their reorder level, with a summary strip (count + total shortage)
// and a double-tap detail dialog (the web's stock modal). The web page's
// warehouse filter is a no-op server-side (getLowStockReport takes no
// params), so it is omitted here.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/csv_export.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/report.dart' show LowStockReportRow;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/screen_error_panel.dart';
import 'low_stock_detail_dialog.dart';
import 'report_providers.dart';

class LowStockReportScreen extends ConsumerStatefulWidget {
  const LowStockReportScreen({super.key});

  @override
  ConsumerState<LowStockReportScreen> createState() =>
      _LowStockReportScreenState();
}

class _LowStockReportScreenState extends ConsumerState<LowStockReportScreen> {
  /// Row id → model for the double-tap detail dialog (no per-row
  /// endpoint — the dialog renders from the grid's own row data).
  final Map<int, LowStockReportRow> _rowsById = {};

  /// Grid manager — rows are fed through the manager (clear + append)
  /// on provider changes, the same pattern as the expenses screen
  /// (PlutoGrid only reads its `rows` prop in initState).
  ///
  /// The grid's `rows:` list must stay **mutable** — PlutoGrid wraps the
  /// passed list and `appendRows` mutates it, so a `const` list throws
  /// "Cannot add to an unmodifiable list".
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
  void _applyRows(AsyncValue<List<LowStockReportRow>> value) {
    final manager = _manager;
    if (manager == null) return;
    manager.setShowLoading(value.isLoading);
    if (value.hasValue) {
      final loaded = value.value ?? const <LowStockReportRow>[];
      // Drop stale entries from earlier fetches before repopulating.
      _rowsById.clear();
      manager.removeAllRows();
      manager.appendRows([for (final row in loaded) _rowFor(row)]);
    }
  }

  PlutoRow _rowFor(LowStockReportRow row) {
    _rowsById[row.id] = row;
    return PlutoRow(
      cells: {
        'id': PlutoCell(value: row.id),
        'itemName': PlutoCell(value: row.itemName),
        'itemCode': PlutoCell(value: row.itemCode),
        'category': PlutoCell(value: row.itemCategory),
        'currentStock': PlutoCell(value: row.currentStock),
        'minimumStock': PlutoCell(value: row.minimumStock),
        'shortage': PlutoCell(value: row.shortage),
        'reorderLevel': PlutoCell(value: row.reorderLevel),
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
    _numberColumn('currentStock', l10n.inventoryCurrentstock, 130),
    _numberColumn('minimumStock', l10n.reportsMinimumstock, 140),
    _numberColumn('shortage', l10n.reportsShortage, 120),
    _numberColumn('reorderLevel', l10n.inventoryReorderlevel, 140),
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
    final rows = ref.watch(lowStockReportProvider);
    final l10n = AppLocalizations.of(context)!;

    ref.listen(lowStockReportProvider, (previous, next) => _applyRows(next));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _header(l10n, rows),
        ),
        Expanded(child: _body(rows)),
      ],
    );
  }

  Widget _header(
    AppLocalizations l10n,
    AsyncValue<List<LowStockReportRow>> rows,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final loaded = rows.valueOrNull ?? const <LowStockReportRow>[];
    final totalShortage = loaded.fold<num>(0, (sum, r) => sum + r.shortage);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.reportsLowstockalertreport,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            TextButton.icon(
              onPressed: rows.isLoading || loaded.isEmpty
                  ? null
                  : () => saveCsv(
                      context,
                      suggestedName: csvSuggestedName('low-stock'),
                      csv: buildLowStockCsv(l10n, loaded),
                      successMessage: l10n.reportsExported,
                      errorMessage: l10n.reportsExportfailed,
                    ),
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: Text(l10n.reportsExportcsv),
            ),
          ],
        ),
        if (loaded.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_outlined,
                  size: 18,
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '${loaded.length} ${l10n.reportsLowstockcount}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(width: 14),
                Text(
                  '${l10n.reportsShortagetotal}: '
                  '${Formatters.number(totalShortage)}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.error,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _body(AsyncValue<List<LowStockReportRow>> rows) {
    final l10n = AppLocalizations.of(context)!;
    final errorMessage = switch (rows) {
      AsyncError(:final error) => error is ApiError ? error.message : null,
      _ => null,
    };
    if (errorMessage != null) {
      return ScreenErrorPanel(
        message: errorMessage,
        onRetry: () => ref.invalidate(lowStockReportProvider),
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
          _applyRows(ref.read(lowStockReportProvider));
        },
        onRowDoubleTap: (event) {
          final id = (event.row.cells['id']?.value as num?)?.toInt();
          if (id == null || id <= 0) return;
          final item = _rowsById[id];
          if (item == null) return;
          showLowStockDetailDialog(context, item: item);
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
