// Top debtors report — GET /reports/top-debtors (PORTING.md §11). Port
// of the web `TopDebtorsReport.tsx`: a read-only grid of the customers
// with the highest outstanding balances, with a row-limit selector
// (Top 5/10/20/50) and a double-tap detail dialog. The endpoint returns
// a **bare array**.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/csv_export.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/report.dart' show TopDebtorRow;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/pluto_grid_screen.dart' show plutoGridConfigurationFor, serialGridColumn;
import '../../widgets/screen_error_panel.dart';
import '../../widgets/screen_toolbar.dart' show ScreenToolbar;
import 'report_providers.dart';
import 'top_debtor_detail_dialog.dart';

class TopDebtorsReportScreen extends ConsumerStatefulWidget {
  const TopDebtorsReportScreen({super.key});

  @override
  ConsumerState<TopDebtorsReportScreen> createState() =>
      _TopDebtorsReportScreenState();
}

class _TopDebtorsReportScreenState
    extends ConsumerState<TopDebtorsReportScreen> {
  /// Row index → model for the double-tap detail dialog (the report has
  /// no per-row endpoint — the dialog renders from the grid's own row
  /// data; rows are keyed by grid index because the server sends no id).
  final Map<int, TopDebtorRow> _rowsById = {};

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
  void _applyReport(AsyncValue<List<TopDebtorRow>> value) {
    final manager = _manager;
    if (manager == null) return;
    manager.setShowLoading(value.isLoading);
    if (value.hasValue) {
      final loaded = value.value ?? const <TopDebtorRow>[];
      _rowsById.clear();
      manager.removeAllRows();
      manager.appendRows([
        for (final (index, row) in loaded.indexed) _rowFor(index, row),
      ]);
    }
  }

  PlutoRow _rowFor(int index, TopDebtorRow row) {
    _rowsById[index] = row;
    return PlutoRow(
      cells: {
        'serial': PlutoCell(value: index + 1),
        'key': PlutoCell(value: index),
        'customerName': PlutoCell(value: row.customerName),
        'customerCode': PlutoCell(value: row.customerCode),
        'outstanding': PlutoCell(value: row.totalOutstanding),
        'invoiced': PlutoCell(value: row.totalInvoiced),
        'invoiceCount': PlutoCell(value: row.invoiceCount),
      },
    );
  }

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

  static PlutoColumn _numberColumn(String field, String title, double width) =>
      PlutoColumn(
        title: title,
        field: field,
        type: PlutoColumnType.number(format: '#,###'),
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
      title: l10n.fieldsCustomer,
      field: 'customerName',
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
      title: l10n.fieldsCustomerCode,
      field: 'customerCode',
      type: PlutoColumnType.text(),
      width: 130,
      readOnly: true,
      enableContextMenu: false,
    ),
    _moneyColumn('outstanding', l10n.reportsTotaloutstanding, 160),
    _moneyColumn('invoiced', l10n.reportsTotalinvoiced, 150),
    _numberColumn('invoiceCount', l10n.reportsInvoicecount, 120),
    // Hidden key column — carries the grid row index to the double-tap
    // handler (same pattern as the other read-only grids).
    PlutoColumn(
      title: '',
      field: 'key',
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
    final report = ref.watch(topDebtorsReportProvider);
    final l10n = AppLocalizations.of(context)!;

    ref.listen(
      topDebtorsReportProvider,
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

  Widget _header(AppLocalizations l10n, AsyncValue<List<TopDebtorRow>> report) {
    final value = report.valueOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            l10n.reportsTopdebtorsreport,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        ScreenToolbar(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          filters: [
            // Row-limit selector — same options as the web page's filter.
            DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: ref.watch(topDebtorsLimitProvider),
                items: const [
                  DropdownMenuItem(value: 5, child: Text('Top 5')),
                  DropdownMenuItem(value: 10, child: Text('Top 10')),
                  DropdownMenuItem(value: 20, child: Text('Top 20')),
                  DropdownMenuItem(value: 50, child: Text('Top 50')),
                ],
                onChanged: (limit) {
                  if (limit == null) return;
                  ref.read(topDebtorsLimitProvider.notifier).state = limit;
                },
              ),
            ),
          ],
          onRefresh: () => ref.invalidate(topDebtorsReportProvider),
          actions: [
            TextButton.icon(
              onPressed: report.isLoading || (value?.isEmpty ?? true)
                  ? null
                  : () => saveCsv(
                      context,
                      suggestedName: csvSuggestedName('top-debtors'),
                      csv: buildTopDebtorsCsv(l10n, value!),
                      successMessage: l10n.reportsExported,
                      errorMessage: l10n.reportsExportfailed,
                    ),
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: Text(l10n.reportsExportcsv),
            ),
          ],
        ),
      ],
    );
  }

  Widget _body(AsyncValue<List<TopDebtorRow>> report) {
    final l10n = AppLocalizations.of(context)!;
    final errorMessage = switch (report) {
      AsyncError(:final error) => error is ApiError ? error.message : null,
      _ => null,
    };
    if (errorMessage != null) {
      return ScreenErrorPanel(
        message: errorMessage,
        onRetry: () => ref.invalidate(topDebtorsReportProvider),
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
          _applyReport(ref.read(topDebtorsReportProvider));
        },
        onRowDoubleTap: (event) {
          final key = (event.row.cells['key']?.value as num?)?.toInt();
          if (key == null) return;
          final row = _rowsById[key];
          if (row == null) return;
          showTopDebtorDetailDialog(context, row: row);
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
