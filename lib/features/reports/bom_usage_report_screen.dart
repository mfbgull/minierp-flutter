// BOM usage report — GET /reports/bom-usage (PORTING.md §11). Port of
// the web `BOMUsageReport.tsx`: a read-only grid of BOM usage over a
// date range, optionally narrowed to one finished item (the endpoint
// tolerates omitted dates but the port always sends them). From/To date
// buttons + the finished-item picker refetch via the providers; a
// double-tap opens the BOM detail dialog.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/csv_export.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/item.dart' show Item;
import '../../data/models/report.dart' show BomUsageReport, BomUsageRow;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/date_range_picker.dart' show DateRangeFilter;
import '../../widgets/pluto_grid_screen.dart' show plutoGridConfigurationFor, serialGridColumn;
import '../../widgets/screen_error_panel.dart';
import '../../widgets/screen_toolbar.dart' show ScreenToolbar;
import '../../widgets/searchable_select.dart';
import 'bom_usage_detail_dialog.dart';
import 'report_providers.dart';

class BomUsageReportScreen extends ConsumerStatefulWidget {
  const BomUsageReportScreen({super.key});

  @override
  ConsumerState<BomUsageReportScreen> createState() =>
      _BomUsageReportScreenState();
}

class _BomUsageReportScreenState extends ConsumerState<BomUsageReportScreen> {
  /// Row key → model for the double-tap detail dialog (the report has no
  /// per-row endpoint — the dialog renders from the grid's own row data).
  /// Keyed by bom_id when present, else the row index.
  final Map<String, BomUsageRow> _rowsByKey = {};

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

  void _applyReport(AsyncValue<BomUsageReport> value) {
    final manager = _manager;
    if (manager == null) return;
    manager.setShowLoading(value.isLoading);
    if (value.hasValue) {
      final loaded = value.value?.rows ?? const <BomUsageRow>[];
      _rowsByKey.clear();
      manager.removeAllRows();
      manager.appendRows([
        for (var i = 0; i < loaded.length; i++) _rowFor(loaded[i], i),
      ]);
    }
  }

  PlutoRow _rowFor(BomUsageRow row, int index) {
    final key = row.bomId > 0 ? 'bom-${row.bomId}' : 'row-$index';
    _rowsByKey[key] = row;
    return PlutoRow(
      cells: {
        'serial': PlutoCell(value: index + 1),
        'key': PlutoCell(value: key),
        'bomName': PlutoCell(value: row.bomName),
        'parentItemName': PlutoCell(value: row.parentItemName),
        'usageCount': PlutoCell(value: row.usageCount),
        'lastUsedDate': PlutoCell(value: row.lastUsedDate ?? ''),
        'totalComponents': PlutoCell(value: row.totalComponents),
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
      title: l10n.bomName,
      field: 'bomName',
      type: PlutoColumnType.text(),
      width: 240,
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
      title: l10n.reportsParentitem,
      field: 'parentItemName',
      type: PlutoColumnType.text(),
      width: 200,
      readOnly: true,
      enableContextMenu: false,
    ),
    _numberColumn('usageCount', l10n.reportsUsagecount, 120),
    PlutoColumn(
      title: l10n.reportsLastused,
      field: 'lastUsedDate',
      type: PlutoColumnType.text(),
      width: 140,
      readOnly: true,
      enableContextMenu: false,
      renderer: (ctx) => Align(
        alignment: Alignment.centerLeft,
        child: Text(Formatters.date(ctx.cell.value as String? ?? '')),
      ),
    ),
    _numberColumn('totalComponents', l10n.reportsTotalcomponents, 150),
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
    final report = ref.watch(bomUsageReportProvider);
    final items = ref.watch(finishedItemsForReportProvider);
    final selectedItemId = ref.watch(reportBomItemIdProvider);
    final l10n = AppLocalizations.of(context)!;

    ref.listen(bomUsageReportProvider, (previous, next) => _applyReport(next));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            l10n.reportsBomusage,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        ScreenToolbar(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          filters: [
            DateRangeFilter(
              fromProvider: reportBomFromDateProvider,
              toProvider: reportBomToDateProvider,
              showAllDates: false,
            ),
            SizedBox(
              width: 220,
              child: SearchableSelect<int>(
                items:
                    items.valueOrNull?.map((i) => i.id).toList() ??
                    const <int>[],
                selected: selectedItemId,
                onChanged: (itemId) {
                  ref.read(reportBomItemIdProvider.notifier).state = itemId;
                },
                labelBuilder: (id) {
                  final item = items.valueOrNull?.cast<Item?>().firstWhere(
                    (i) => i?.id == id,
                    orElse: () => null,
                  );
                  return item?.itemName ?? id.toString();
                },
                hint: l10n.reportsAllitems,
              ),
            ),
          ],
          onRefresh: () => ref.invalidate(bomUsageReportProvider),
          actions: [
            TextButton.icon(
              onPressed:
                  report.isLoading || (report.valueOrNull?.rows.isEmpty ?? true)
                  ? null
                  : () => saveCsv(
                      context,
                      suggestedName: csvSuggestedName('bom-usage'),
                      csv: buildBomUsageCsv(l10n, report.valueOrNull!),
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

  Widget _body(AsyncValue<BomUsageReport> report) {
    final l10n = AppLocalizations.of(context)!;
    final errorMessage = switch (report) {
      AsyncError(:final error) => error is ApiError ? error.message : null,
      _ => null,
    };
    if (errorMessage != null) {
      return ScreenErrorPanel(
        message: errorMessage,
        onRetry: () => ref.invalidate(bomUsageReportProvider),
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
          _applyReport(ref.read(bomUsageReportProvider));
        },
        onRowDoubleTap: (event) {
          final key = event.row.cells['key']?.value as String?;
          if (key == null || key.isEmpty) return;
          final row = _rowsByKey[key];
          if (row == null) return;
          showBomUsageDetailDialog(context, row: row);
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
