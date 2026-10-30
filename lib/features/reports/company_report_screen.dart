// Company Report — GET /reports/company/stock|sales|purchases.
//
// Stock shows the current physical stock and batch-cost value for one
// company and deliberately ignores the date range. Sales and Purchases
// group valid posted document lines by product over an inclusive date
// range; returns are separate columns and already reduce net values.
// Quantities are grouped by unit of measure, never summed across them.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/date_utils.dart' show isoDate;
import '../../core/utils/formatters.dart';
import '../../data/models/company_report.dart'
    show
        CompanyPeriodReport,
        CompanyPeriodRow,
        CompanyReportTransaction,
        CompanyStockReport,
        CompanyStockRow;
import '../../data/models/item.dart' show ItemCompany;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/date_range_picker.dart' show DateRangeFilter;
import '../../widgets/grid_column_widths.dart';
import '../../widgets/pagination_bar.dart';
import '../../widgets/pluto_grid_screen.dart'
    show autoFitPlutoColumns, plutoGridConfigurationFor;
import '../../widgets/screen_error_panel.dart';
import '../../widgets/screen_toolbar.dart' show ScreenToolbar;
import '../inventory/item_detail_dialog.dart' show showItemDetailDialog;
import 'report_providers.dart';

class CompanyReportScreen extends ConsumerStatefulWidget {
  const CompanyReportScreen({super.key});

  @override
  ConsumerState<CompanyReportScreen> createState() =>
      _CompanyReportScreenState();
}

class _CompanyReportScreenState extends ConsumerState<CompanyReportScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  GridColumnWidths? _widthTracker;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: CompanyReportView.values.length,
      vsync: this,
      initialIndex: _viewIndex(ref.read(companyReportViewProvider)),
    )..addListener(_onTabChanged);
  }

  static int _viewIndex(CompanyReportView view) =>
      CompanyReportView.values.indexOf(view);

  void _onTabChanged() {
    if (_tabs.indexIsChanging) return;
    final view = CompanyReportView.values[_tabs.index];
    if (ref.read(companyReportViewProvider) == view) return;
    ref.read(companyReportViewProvider.notifier).state = view;
    _resetPage();
  }

  void _resetPage() {
    ref.read(companyReportPageProvider.notifier).state = 1;
  }

  void _refresh() {
    ref.invalidate(reportCompaniesProvider);
    ref.invalidate(companyStockReportProvider);
    ref.invalidate(companyPeriodReportProvider);
  }

  @override
  void dispose() {
    _tabs
      ..removeListener(_onTabChanged)
      ..dispose();
    _widthTracker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final companies = ref.watch(reportCompaniesProvider);
    final view = ref.watch(companyReportViewProvider);
    final companyId = _effectiveCompanyId(companies);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            l10n.reportsCompanyreport,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: l10n.reportsCompanyStock),
              Tab(text: l10n.reportsCompanySales),
              Tab(text: l10n.reportsCompanyPurchases),
            ],
          ),
        ),
        ScreenToolbar(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          filters: [
            _companyFilter(l10n, companies, companyId),
            if (view != CompanyReportView.stock)
              DateRangeFilter(
                fromProvider: companyReportFromDateProvider,
                toProvider: companyReportToDateProvider,
                showAllDates: false,
                onChanged: _resetPage,
              ),
          ],
          onRefresh: _refresh,
        ),
        Expanded(child: _body(l10n, companies, view, companyId)),
      ],
    );
  }

  int? _effectiveCompanyId(AsyncValue<List<ItemCompany>> companies) {
    final requested = ref.watch(companyReportCompanyIdProvider);
    final loaded = companies.valueOrNull;
    if (loaded == null) return requested;
    if (requested != null && loaded.any((c) => c.id == requested)) {
      return requested;
    }
    return loaded.isEmpty ? null : loaded.first.id;
  }

  Widget _companyFilter(
    AppLocalizations l10n,
    AsyncValue<List<ItemCompany>> companies,
    int? selectedId,
  ) {
    final loaded = companies.valueOrNull;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.reportsCompanyLabel,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 8),
        DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            key: const ValueKey('company-report-selector'),
            value: selectedId,
            hint: Text(l10n.reportsCompanySelect),
            items: [
              for (final company in loaded ?? const <ItemCompany>[])
                DropdownMenuItem(
                  value: company.id,
                  child: Text(
                    company.isActive
                        ? company.name
                        : '${company.name} (${l10n.reportsCompanyArchived})',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: loaded == null
                ? null
                : (id) {
                    if (id == null) return;
                    ref.read(companyReportCompanyIdProvider.notifier).state =
                        id;
                    _resetPage();
                  },
          ),
        ),
        if (companies.isLoading)
          const Padding(
            padding: EdgeInsets.only(left: 8),
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      ],
    );
  }

  Widget _body(
    AppLocalizations l10n,
    AsyncValue<List<ItemCompany>> companies,
    CompanyReportView view,
    int? companyId,
  ) {
    if (companies.hasError) {
      final error = companies.error;
      return ScreenErrorPanel(
        message: error is ApiError
            ? error.message
            : l10n.reportsCompanyLoadfailed,
        onRetry: () => ref.invalidate(reportCompaniesProvider),
      );
    }
    if (companyId == null) {
      if (companies.isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(child: Text(l10n.reportsCompanyNoCompanies));
    }
    return view == CompanyReportView.stock
        ? _stockBody(l10n, companyId)
        : _periodBody(l10n, companyId, view);
  }

  // ── Stock ────────────────────────────────────────────────────────

  Widget _stockBody(AppLocalizations l10n, int companyId) {
    final page = ref.watch(companyReportPageProvider);
    final limit = ref.watch(companyReportLimitProvider);
    final request = (companyId: companyId, page: page, limit: limit);
    final report = ref.watch(companyStockReportProvider(request));

    final error = report.error;
    if (error != null) {
      return ScreenErrorPanel(
        message: error is ApiError ? error.message : l10n.reportsNodata,
        onRetry: () => ref.invalidate(companyStockReportProvider(request)),
      );
    }
    if (report.isLoading && report.valueOrNull == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final data = report.valueOrNull;
    if (data == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _currentStockNote(l10n, data),
        Expanded(
          child: data.rows.isEmpty
              ? Center(child: Text(l10n.reportsCompanyStockEmpty))
              : PlutoGrid(
                  key: ValueKey('company-stock-${data.companyId}-$page-$limit'),
                  configuration: plutoGridConfigurationFor(
                    context,
                    compact: true,
                  ),
                  columns: _stockColumns(l10n),
                  rows: [for (final row in data.rows) _stockRow(row)],
                  onLoaded: (event) {
                    event.stateManager.setSelectingMode(
                      PlutoGridSelectingMode.none,
                    );
                    autoFitPlutoColumns(event.stateManager);
                    _widthTracker?.dispose();
                    _widthTracker = GridColumnWidths.attach(
                      stateManager: event.stateManager,
                      screenKey: 'report_company_stock',
                    );
                  },
                  onRowDoubleTap: (event) {
                    final id = event.row.cells['itemId']?.value as int?;
                    if (id != null && id > 0) {
                      showItemDetailDialog(context, itemId: id);
                    }
                  },
                ),
        ),
        if (data.rows.isNotEmpty)
          ServerPaginationBar(
            page: data.pagination.page,
            totalPages: data.pagination.totalPages,
            totalItems: data.pagination.total,
            hasNext: data.pagination.page < data.pagination.totalPages,
            hasPrev: data.pagination.page > 1,
            limit: limit,
            itemLabel: l10n.reportsItems,
            onPageChanged: (value) =>
                ref.read(companyReportPageProvider.notifier).state = value,
            onLimitChanged: (value) {
              ref.read(companyReportLimitProvider.notifier).state = value;
              _resetPage();
            },
          ),
      ],
    );
  }

  Widget _currentStockNote(AppLocalizations l10n, CompanyStockReport report) {
    final scheme = Theme.of(context).colorScheme;
    final asOf = DateTime.tryParse(report.asOf);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: scheme.primary),
                const SizedBox(width: 6),
                Text(
                  l10n.reportsCompanyCurrentStockNote,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 20,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${l10n.reportsTotalvalue}: ${Formatters.currency(report.totalStockValue)}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
                if (asOf != null)
                  Text(
                    '${l10n.reportsAsOf} ${Formatters.dateTime(asOf.toLocal())}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                for (final entry in report.quantitiesByUom.entries)
                  Text(
                    '${Formatters.number(entry.value)} ${entry.key}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static List<PlutoColumn> _stockColumns(AppLocalizations l10n) => [
    PlutoColumn(
      title: l10n.reportsCompanyProduct,
      field: 'product',
      type: PlutoColumnType.text(),
      width: 260,
      readOnly: true,
      enableContextMenu: false,
    ),
    PlutoColumn(
      title: l10n.reportsCompanyCode,
      field: 'code',
      type: PlutoColumnType.text(),
      width: 130,
      readOnly: true,
      enableContextMenu: false,
    ),
    PlutoColumn(
      title: l10n.reportsCompanyUom,
      field: 'uom',
      type: PlutoColumnType.text(),
      width: 90,
      readOnly: true,
      enableContextMenu: false,
    ),
    _quantityColumn('quantity', l10n.reportsQuantity, 120),
    _moneyColumn('stockValue', l10n.reportsCompanyStockValue, 150),
    _hiddenIdColumn(),
  ];

  static PlutoRow _stockRow(CompanyStockRow row) => PlutoRow(
    cells: {
      'product': PlutoCell(value: row.itemName),
      'code': PlutoCell(value: row.itemCode),
      'uom': PlutoCell(value: row.unitOfMeasure),
      'quantity': PlutoCell(value: row.quantity),
      'stockValue': PlutoCell(value: row.stockValue),
      'itemId': PlutoCell(value: row.itemId),
    },
  );

  // ── Sales / purchases ────────────────────────────────────────────

  Widget _periodBody(
    AppLocalizations l10n,
    int companyId,
    CompanyReportView view,
  ) {
    final page = ref.watch(companyReportPageProvider);
    final limit = ref.watch(companyReportLimitProvider);
    final from = ref.watch(companyReportFromDateProvider) ?? _today();
    final to = ref.watch(companyReportToDateProvider) ?? _today();
    final request = (
      companyId: companyId,
      view: view,
      page: page,
      limit: limit,
      startDate: isoDate(from),
      endDate: isoDate(to),
    );
    final report = ref.watch(companyPeriodReportProvider(request));

    final error = report.error;
    if (error != null) {
      return ScreenErrorPanel(
        message: error is ApiError ? error.message : l10n.reportsNodata,
        onRetry: () => ref.invalidate(companyPeriodReportProvider(request)),
      );
    }
    if (report.isLoading && report.valueOrNull == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final data = report.valueOrNull;
    if (data == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _periodTotals(l10n, data),
        Expanded(
          child: data.rows.isEmpty
              ? Center(child: Text(l10n.reportsCompanyPeriodEmpty))
              : PlutoGrid(
                  key: ValueKey(
                    'company-period-${data.companyId}-${data.view}-'
                    '${data.startDate}-${data.endDate}-$page-$limit',
                  ),
                  configuration: plutoGridConfigurationFor(
                    context,
                    compact: true,
                  ),
                  columns: _periodColumns(l10n),
                  rows: [for (final row in data.rows) _periodRow(row)],
                  onLoaded: (event) {
                    event.stateManager.setSelectingMode(
                      PlutoGridSelectingMode.none,
                    );
                    autoFitPlutoColumns(event.stateManager);
                    _widthTracker?.dispose();
                    _widthTracker = GridColumnWidths.attach(
                      stateManager: event.stateManager,
                      screenKey: 'report_company_period',
                    );
                  },
                  onRowDoubleTap: (event) {
                    final row = event.row.cells['data']?.value;
                    if (row is CompanyPeriodRow) {
                      _showTransactions(l10n, data, row);
                    }
                  },
                ),
        ),
        if (data.rows.isNotEmpty)
          ServerPaginationBar(
            page: data.pagination.page,
            totalPages: data.pagination.totalPages,
            totalItems: data.pagination.total,
            hasNext: data.pagination.page < data.pagination.totalPages,
            hasPrev: data.pagination.page > 1,
            limit: limit,
            itemLabel: l10n.reportsItems,
            onPageChanged: (value) =>
                ref.read(companyReportPageProvider.notifier).state = value,
            onLimitChanged: (value) {
              ref.read(companyReportLimitProvider.notifier).state = value;
              _resetPage();
            },
          ),
      ],
    );
  }

  Widget _periodTotals(AppLocalizations l10n, CompanyPeriodReport report) {
    final scheme = Theme.of(context).colorScheme;
    final totals = report.totals;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${l10n.reportsPeriod}: '
              '${Formatters.date(report.startDate)} ${l10n.commonTo} '
              '${Formatters.date(report.endDate)}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 20,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _totalText(
                  l10n.reportsCompanyGrossValue,
                  Formatters.currency(totals.grossValue),
                ),
                _totalText(
                  l10n.reportsCompanyReturnValue,
                  Formatters.currency(totals.returnValue),
                ),
                _totalText(
                  l10n.reportsCompanyNetValue,
                  Formatters.currency(totals.netValue),
                  emphasised: true,
                ),
                for (final entry in totals.quantitiesByUom.entries)
                  Text(
                    '${entry.key}: '
                    '${Formatters.number(entry.value.gross)} / '
                    '${Formatters.number(entry.value.returns)} / '
                    '${Formatters.number(entry.value.net)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _totalText(String label, String value, {bool emphasised = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '$label: '),
          TextSpan(
            text: value,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: emphasised ? scheme.primary : scheme.onSurface,
            ),
          ),
        ],
      ),
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
    );
  }

  static List<PlutoColumn> _periodColumns(AppLocalizations l10n) => [
    PlutoColumn(
      title: l10n.reportsCompanyProduct,
      field: 'product',
      type: PlutoColumnType.text(),
      width: 240,
      readOnly: true,
      enableContextMenu: false,
    ),
    PlutoColumn(
      title: l10n.reportsCompanyCode,
      field: 'code',
      type: PlutoColumnType.text(),
      width: 120,
      readOnly: true,
      enableContextMenu: false,
    ),
    PlutoColumn(
      title: l10n.reportsCompanyUom,
      field: 'uom',
      type: PlutoColumnType.text(),
      width: 80,
      readOnly: true,
      enableContextMenu: false,
    ),
    _quantityColumn('grossQty', l10n.reportsCompanyGrossQty, 110),
    _quantityColumn('returnQty', l10n.reportsCompanyReturnQty, 110),
    _quantityColumn('netQty', l10n.reportsCompanyNetQty, 110),
    _moneyColumn('grossValue', l10n.reportsCompanyGrossValue, 140),
    _moneyColumn('returnValue', l10n.reportsCompanyReturnValue, 140),
    _moneyColumn('netValue', l10n.reportsCompanyNetValue, 140),
    _hiddenDataColumn(),
  ];

  static PlutoRow _periodRow(CompanyPeriodRow row) => PlutoRow(
    cells: {
      'product': PlutoCell(value: row.itemName),
      'code': PlutoCell(value: row.itemCode),
      'uom': PlutoCell(value: row.unitOfMeasure),
      'grossQty': PlutoCell(value: row.grossQuantity),
      'returnQty': PlutoCell(value: row.returnQuantity),
      'netQty': PlutoCell(value: row.netQuantity),
      'grossValue': PlutoCell(value: row.grossValue),
      'returnValue': PlutoCell(value: row.returnValue),
      'netValue': PlutoCell(value: row.netValue),
      'data': PlutoCell(value: row),
    },
  );

  // ── Grid helpers ─────────────────────────────────────────────────

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

  static PlutoColumn _quantityColumn(
    String field,
    String title,
    double width,
  ) => PlutoColumn(
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

  static PlutoColumn _hiddenIdColumn() => PlutoColumn(
    title: '',
    field: 'itemId',
    type: PlutoColumnType.number(),
    width: 1,
    readOnly: true,
    renderer: (_) => const SizedBox.shrink(),
    enableContextMenu: false,
    enableFilterMenuItem: false,
    enableHideColumnMenuItem: false,
    enableSetColumnsMenuItem: false,
  );

  static PlutoColumn _hiddenDataColumn() => PlutoColumn(
    title: '',
    field: 'data',
    type: PlutoColumnType.text(),
    width: 1,
    readOnly: true,
    renderer: (_) => const SizedBox.shrink(),
    enableContextMenu: false,
    enableFilterMenuItem: false,
    enableHideColumnMenuItem: false,
    enableSetColumnsMenuItem: false,
  );

  // ── Transaction drilldown ────────────────────────────────────────

  void _showTransactions(
    AppLocalizations l10n,
    CompanyPeriodReport report,
    CompanyPeriodRow row,
  ) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(row.itemName),
        content: SizedBox(
          width: 680,
          height: 380,
          child: row.transactions.isEmpty
              ? Center(child: Text(l10n.reportsCompanyNoTransactions))
              : ListView.separated(
                  itemCount: row.transactions.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) => _TransactionLine(
                    l10n: l10n,
                    transaction: row.transactions[index],
                    view: report.view,
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.commonClose),
          ),
        ],
      ),
    );
  }

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }
}

class _TransactionLine extends StatelessWidget {
  const _TransactionLine({
    required this.l10n,
    required this.transaction,
    required this.view,
  });

  final AppLocalizations l10n;
  final CompanyReportTransaction transaction;

  /// `'sales'` or `'purchases'`.
  final String view;

  String get _typeLabel {
    final type = transaction.documentType;
    if (view == 'purchases') {
      return switch (type) {
        'PURCHASE' => l10n.reportsCompanyPurchaseDoc,
        'GOODS_RECEIPT' => l10n.reportsCompanyGoodsReceipt,
        'PURCHASE_RETURN' => l10n.reportsCompanyPurchaseReturn,
        _ => type,
      };
    }
    return switch (type) {
      'INVOICE' => l10n.reportsCompanyInvoice,
      'INVOICE_RETURN' => l10n.reportsCompanyInvoiceReturn,
      _ => type,
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final sign = transaction.isReturn ? '−' : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(
              Formatters.date(transaction.date),
              style: textTheme.bodySmall,
            ),
          ),
          SizedBox(
            width: 120,
            child: Text(
              transaction.documentNo,
              style: textTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 140,
            child: Text(
              _typeLabel,
              style: textTheme.bodySmall?.copyWith(
                color: transaction.isReturn ? scheme.error : null,
              ),
            ),
          ),
          Expanded(
            child: Text(
              '$sign${Formatters.number(transaction.quantity)}',
              textAlign: TextAlign.end,
              style: textTheme.bodyMedium,
            ),
          ),
          SizedBox(
            width: 140,
            child: Text(
              '$sign${Formatters.currency(transaction.amount)}',
              textAlign: TextAlign.end,
              style: textTheme.bodyMedium?.copyWith(
                color: transaction.isReturn ? scheme.error : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
