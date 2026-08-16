// Customer statements report — GET /reports/customer-statements
// (PORTING.md §11). Port of the web `CustomerStatementsReport.tsx`:
// read-only grid of per-customer statement summaries over a date range,
// with date filters, optional customer picker, double-tap detail dialog,
// and CSV export.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/csv_export.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/customer.dart' show Customer;
import '../../data/models/report.dart' show CustomerStatementRow;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/date_range_picker.dart';
import '../../widgets/pluto_grid_screen.dart' show plutoGridConfigurationFor, serialGridColumn;
import '../../widgets/screen_error_panel.dart';
import '../../widgets/screen_toolbar.dart' show ScreenToolbar;
import '../../widgets/searchable_select.dart';
import 'customer_statement_detail_dialog.dart';
import 'report_providers.dart';

class CustomerStatementsReportScreen extends ConsumerStatefulWidget {
  const CustomerStatementsReportScreen({super.key});

  @override
  ConsumerState<CustomerStatementsReportScreen> createState() =>
      _CustomerStatementsReportScreenState();
}

class _CustomerStatementsReportScreenState
    extends ConsumerState<CustomerStatementsReportScreen> {
  final Map<int, CustomerStatementRow> _rowsById = {};
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

  void _applyReport(AsyncValue<List<CustomerStatementRow>> value) {
    final manager = _manager;
    if (manager == null) return;
    manager.setShowLoading(value.isLoading);
    if (value.hasValue) {
      final loaded = value.value ?? const <CustomerStatementRow>[];
      _rowsById.clear();
      manager.removeAllRows();
      manager.appendRows([
        for (final (index, row) in loaded.indexed) _rowFor(index, row),
      ]);
    }
  }

  PlutoRow _rowFor(int index, CustomerStatementRow row) {
    _rowsById[index] = row;
    return PlutoRow(
      cells: {
        'serial': PlutoCell(value: index + 1),
        'key': PlutoCell(value: row.customerId),
        'customerName': PlutoCell(value: row.customerName),
        'customerCode': PlutoCell(value: row.customerCode),
        'openingBalance': PlutoCell(value: row.openingBalance),
        'totalDebits': PlutoCell(value: row.totalDebits),
        'totalCredits': PlutoCell(value: row.totalCredits),
        'closingBalance': PlutoCell(value: row.closingBalance),
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
    _moneyColumn('openingBalance', l10n.reportsOpeningbalance, 160),
    _moneyColumn('totalDebits', l10n.reportsTotaldebits, 150),
    _moneyColumn('totalCredits', l10n.reportsTotalcredits, 150),
    _moneyColumn('closingBalance', l10n.reportsClosingbalance, 160),
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
    final report = ref.watch(customerStatementsReportProvider);
    final l10n = AppLocalizations.of(context)!;
    final customers = ref.watch(customersForReportProvider);
    final selectedCustomerId = ref.watch(reportStatementsCustomerIdProvider);

    ref.listen(
      customerStatementsReportProvider,
      (previous, next) => _applyReport(next),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(l10n, report, customers, selectedCustomerId),
        Expanded(child: _body(report)),
      ],
    );
  }

  Widget _header(
    AppLocalizations l10n,
    AsyncValue<List<CustomerStatementRow>> report,
    AsyncValue<List<Customer>> customers,
    int? selectedCustomerId,
  ) {
    final value = report.valueOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            l10n.reportsCustomerstatementsreport,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        ScreenToolbar(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          filters: [
            DateRangeFilter(
              fromProvider: reportStatementsFromDateProvider,
              toProvider: reportStatementsToDateProvider,
              showAllDates: false,
            ),
            SizedBox(
              width: 220,
              child: SearchableSelect<int>(
                items:
                    customers.valueOrNull?.map((c) => c.id).toList() ??
                    const <int>[],
                selected: selectedCustomerId,
                onChanged: (customerId) {
                  if (customerId == null) {
                    ref
                            .read(reportStatementsCustomerIdProvider.notifier)
                            .state =
                        null;
                  } else {
                    ref
                            .read(reportStatementsCustomerIdProvider.notifier)
                            .state =
                        customerId;
                  }
                },
                labelBuilder: (id) {
                  final customer = customers.valueOrNull
                      ?.cast<Customer?>()
                      .firstWhere((c) => c?.id == id, orElse: () => null);
                  return customer?.customerName ?? id.toString();
                },
              ),
            ),
          ],
          onRefresh: () => ref.invalidate(customerStatementsReportProvider),
          actions: [
            TextButton.icon(
              onPressed: report.isLoading || (value?.isEmpty ?? true)
                  ? null
                  : () => saveCsv(
                      context,
                      suggestedName: csvSuggestedName('customer-statements'),
                      csv: buildCustomerStatementsCsv(l10n, value!),
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

  Widget _body(AsyncValue<List<CustomerStatementRow>> report) {
    final l10n = AppLocalizations.of(context)!;
    final errorMessage = switch (report) {
      AsyncError(:final error) => error is ApiError ? error.message : null,
      _ => null,
    };
    if (errorMessage != null) {
      return ScreenErrorPanel(
        message: errorMessage,
        onRetry: () => ref.invalidate(customerStatementsReportProvider),
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
          _applyReport(ref.read(customerStatementsReportProvider));
        },
        onRowDoubleTap: (event) {
          final key = (event.row.cells['key']?.value as num?)?.toInt();
          if (key == null) return;
          final row = _rowsById[key];
          if (row == null) return;
          showCustomerStatementDetailDialog(context, row: row);
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
