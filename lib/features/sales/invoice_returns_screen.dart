// Invoice returns list screen — a read-only grid over `GET
// /invoices/returns` (**bare array** of `RETURN` stock movements; no
// search/page params, so sorting and filtering stay client-side like the
// items screen). Rendered with PlutoGrid via the shared [PlutoGridScreen]
// mixin: F2/Enter + double-tap open the return detail, and the
// keyboard-hint status bar sits beneath the grid. Hosted as the
// 'Invoice Returns' tab of the sales shell (the web app pairs it with
// `/sales/returns`).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/csv_export.dart';
import '../../core/utils/date_utils.dart' show isoDate;
import '../../core/utils/formatters.dart';
import '../../data/models/sales_return.dart' show SalesReturn;
import '../../l10n/app_localizations.dart';
import '../../widgets/date_range_picker.dart' show DateRangeFilter;
import '../../widgets/pluto_grid_screen.dart';
import '../../widgets/screen_toolbar.dart';
import 'invoice_return_detail_dialog.dart';
import 'invoice_return_picker_dialog.dart' show showInvoiceReturnPicker;
import 'invoice_return_providers.dart';

class InvoiceReturnsScreen extends ConsumerStatefulWidget {
  const InvoiceReturnsScreen({super.key});

  @override
  ConsumerState<InvoiceReturnsScreen> createState() =>
      _InvoiceReturnsScreenState();
}

class _InvoiceReturnsScreenState extends ConsumerState<InvoiceReturnsScreen>
    with PlutoGridScreen<SalesReturn, InvoiceReturnsScreen> {
  Timer? _debounce;
  final TextEditingController _searchController = TextEditingController();

  /// Row id → model for the detail dialog — there is no per-row endpoint,
  /// so the dialog renders from the row the grid was built from.
  final Map<int, SalesReturn> _returnsById = {};

  @override
  void openRowDetail(int returnId) {
    if (!mounted) return;
    final salesReturn = _returnsById[returnId];
    if (salesReturn == null) return;
    showInvoiceReturnDetailDialog(context, salesReturn: salesReturn);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      ref.read(invoiceReturnsSearchProvider.notifier).state = value.trim();
    });
  }

  bool get _hasActiveFilters =>
      ref.read(invoiceReturnsWarehouseProvider) != null ||
      ref.read(invoiceReturnsFromDateProvider) != null ||
      ref.read(invoiceReturnsToDateProvider) != null ||
      ref.read(invoiceReturnsSearchProvider).isNotEmpty;

  void _clearFilters() {
    _searchController.clear();
    ref.read(invoiceReturnsWarehouseProvider.notifier).state = null;
    ref.read(invoiceReturnsFromDateProvider.notifier).state = null;
    ref.read(invoiceReturnsToDateProvider.notifier).state = null;
    ref.read(invoiceReturnsSearchProvider.notifier).state = '';
  }

  /// Client-side filtering (search term + warehouse + date range) over
  /// the loaded rows — the endpoint only serves the full list, so every
  /// filter runs here.
  List<SalesReturn> _filteredRows(List<SalesReturn> returns) {
    final search = ref.read(invoiceReturnsSearchProvider).toLowerCase();
    final warehouse = ref.read(invoiceReturnsWarehouseProvider);
    final from = ref.read(invoiceReturnsFromDateProvider);
    final to = ref.read(invoiceReturnsToDateProvider);
    if (search.isEmpty &&
        warehouse == null &&
        from == null &&
        to == null) {
      return returns;
    }
    return returns.where((r) {
      if (search.isNotEmpty &&
          !r.movementNo.toLowerCase().contains(search) &&
          !r.itemName.toLowerCase().contains(search) &&
          !(r.customerName ?? '').toLowerCase().contains(search)) {
        return false;
      }
      if (warehouse != null && r.warehouseName != warehouse) return false;
      final iso = r.returnDate;
      if (from != null && iso.compareTo(isoDate(from)) < 0) return false;
      if (to != null && iso.compareTo(isoDate(to)) > 0) return false;
      return true;
    }).toList();
  }

  /// Provider → grid sync that honours the active client-side filters
  /// (overrides the mixin's unfiltered clear+append).
  @override
  void syncGridRows(AsyncValue<Object?> value) {
    final manager = gridStateManager;
    if (manager == null) return;
    manager.setShowLoading(value.isLoading);
    if (value.hasValue) {
      final rows = _filteredRows(value.value as List<SalesReturn>);
      // Rebuild the row-id → model map from the rows the grid actually
      // shows (the detail dialog renders from the in-memory row).
      _returnsById
        ..clear()
        ..addEntries([for (final r in rows) MapEntry(r.id, r)]);
      manager.removeAllRows();
      manager.appendRows([
        for (final (index, row) in rows.indexed)
          withSerialCell(gridRowFor(row), index),
      ]);
    }
  }

  void _refilter() => syncGridRows(ref.read(invoiceReturnsProvider));

  @override
  PlutoRow gridRowFor(SalesReturn salesReturn) {
    // Cache the model for the F2/Enter/double-tap detail path.
    _returnsById[salesReturn.id] = salesReturn;
    return PlutoRow(
      cells: {
        'id': PlutoCell(value: salesReturn.id),
        'returnNo': PlutoCell(value: salesReturn.movementNo),
        'date': PlutoCell(value: salesReturn.returnDate),
        'item': PlutoCell(value: salesReturn.itemName),
        'qty': PlutoCell(value: salesReturn.quantity),
        'unitCost': PlutoCell(value: salesReturn.unitCost),
        'total': PlutoCell(value: salesReturn.returnValue),
        'customer': PlutoCell(value: salesReturn.customerName ?? ''),
        'warehouse': PlutoCell(value: salesReturn.warehouseName),
        'remarks': PlutoCell(value: salesReturn.remarks ?? ''),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final returns = ref.watch(invoiceReturnsProvider);
    final l10n = AppLocalizations.of(context)!;

    // Keep the grid in sync with provider transitions (loading → data).
    // The mixin listener routes through the overridden syncGridRows, so
    // filtering applies on every load/refresh too.
    watchGridProvider(invoiceReturnsProvider);
    // Client-side filters re-run the filter over the loaded rows without
    // refetching.
    ref.listen(invoiceReturnsSearchProvider, (previous, next) => _refilter());
    ref.listen(invoiceReturnsWarehouseProvider, (previous, next) => _refilter());
    ref.listen(invoiceReturnsFromDateProvider, (previous, next) => _refilter());
    ref.listen(invoiceReturnsToDateProvider, (previous, next) => _refilter());

    // The client-side filters drive the search-clear button and the
    // warehouse dropdown, so they must be watched here for the build to
    // re-run.
    ref.watch(invoiceReturnsSearchProvider);
    ref.watch(invoiceReturnsWarehouseProvider);
    ref.watch(invoiceReturnsFromDateProvider);
    ref.watch(invoiceReturnsToDateProvider);

    final allReturns = returns.valueOrNull ?? const <SalesReturn>[];
    final filteredRows = _filteredRows(allReturns);
    // Warehouse filter options — `All` (null) plus the distinct
    // warehouse names from the loaded rows.
    final warehouses = <String>[];
    final seen = <String>{};
    for (final r in allReturns) {
      if (r.warehouseName.isNotEmpty && seen.add(r.warehouseName)) {
        warehouses.add(r.warehouseName);
      }
    }
    warehouses.sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Toolbar: search + warehouse filter + date range + actions —
        // the same header the invoices tab has (the New slot opens the
        // Process Return picker, since returns are created against an
        // invoice).
        ScreenToolbar(
          searchController: _searchController,
          searchHint: l10n.salesreturnsSearchplaceholder,
          onSearchChanged: _onSearchChanged,
          filters: [
            ScreenToolbarDropdown<String?>(
              items: [null, ...warehouses],
              value: ref.watch(invoiceReturnsWarehouseProvider),
              hint: l10n.commonAll,
              labelBuilder: (v) => v ?? l10n.commonAll,
              width: 170,
              onChanged: (v) =>
                  ref.read(invoiceReturnsWarehouseProvider.notifier).state = v,
            ),
            DateRangeFilter(
              width: 120,
              fromProvider: invoiceReturnsFromDateProvider,
              toProvider: invoiceReturnsToDateProvider,
            ),
          ],
          onRefresh: () => ref.invalidate(invoiceReturnsProvider),
          onClearAll: _clearFilters,
          hasActiveFilters: _hasActiveFilters,
          actions: [
            // CSV export — runs over the currently-filtered rows; the
            // shared save helper owns the FilePicker + toast. Disabled
            // until rows are loaded.
            TextButton.icon(
              onPressed: returns.isLoading || filteredRows.isEmpty
                  ? null
                  : () => saveCsv(
                      context,
                      suggestedName: csvSuggestedName('invoice-returns'),
                      csv: buildInvoiceReturnsCsv(
                        l10n,
                        _filteredRows(allReturns),
                      ),
                      successMessage: l10n.salesreturnsExported,
                      errorMessage: l10n.salesreturnsExportfailed,
                    ),
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: Text(l10n.salesreturnsExportcsv),
            ),
          ],
          primaryActions: [
            FilledButton.tonalIcon(
              onPressed: () => showInvoiceReturnPicker(context),
              icon: const Icon(Icons.assignment_return_outlined, size: 18),
              label: Text(l10n.salesreturnsProcessreturn),
            ),
          ],
        ),
        Expanded(
          child: gridScreenBody(returns, provider: invoiceReturnsProvider),
        ),
      ],
    );
  }

  /// Column set — mirrors the return-history columns the web app shows
  /// (Return No, Date, Item, Qty, Unit Cost, Total, Customer, Warehouse,
  /// Remarks); read-only for now (returns are created from an invoice).
  @override
  List<PlutoColumn> buildGridColumns(AppLocalizations l10n) {
    PlutoColumn textColumn(String field, String title, double width) =>
        PlutoColumn(
          title: title,
          field: field,
          type: PlutoColumnType.text(),
          width: width,
          readOnly: true,
          enableContextMenu: false,
        );

    return [
      PlutoColumn(
        title: '',
        field: 'id',
        type: PlutoColumnType.number(),
        width: 80,
        readOnly: true,
        renderer: (ctx) => const SizedBox.shrink(),
        // Hidden in onLoaded — never reveal it via the column menu.
        enableContextMenu: false,
        enableFilterMenuItem: false,
        enableHideColumnMenuItem: false,
        enableSetColumnsMenuItem: false,
      ),
      textColumn('returnNo', l10n.salesreturnsReturnno, 120),
      PlutoColumn(
        title: l10n.salesreturnsReturndate,
        field: 'date',
        type: PlutoColumnType.text(),
        width: 110,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) => Builder(
          builder: (cellContext) => Align(
            alignment: Alignment.centerLeft,
            child: Text(
              Formatters.date(ctx.cell.value as String? ?? ''),
              style: Theme.of(cellContext).textTheme.bodyMedium,
            ),
          ),
        ),
      ),
      textColumn('item', l10n.fieldsItem, 200),
      PlutoColumn(
        title: l10n.salesreturnsReturnqty,
        field: 'qty',
        type: PlutoColumnType.number(format: '#,###.##'),
        width: 90,
        readOnly: true,
        textAlign: PlutoColumnTextAlign.end,
        titleTextAlign: PlutoColumnTextAlign.end,
        enableContextMenu: false,
        renderer: (ctx) => Align(
          alignment: Alignment.centerRight,
          child: Text(Formatters.number(ctx.cell.value as num? ?? 0)),
        ),
      ),
      PlutoColumn(
        title: l10n.fieldsCost,
        field: 'unitCost',
        type: PlutoColumnType.number(format: '#,###.00'),
        width: 100,
        readOnly: true,
        textAlign: PlutoColumnTextAlign.end,
        titleTextAlign: PlutoColumnTextAlign.end,
        enableContextMenu: false,
        renderer: (ctx) => Align(
          alignment: Alignment.centerRight,
          child: Text(Formatters.currency(ctx.cell.value as num? ?? 0)),
        ),
      ),
      PlutoColumn(
        title: l10n.salesreturnsReturnvalue,
        field: 'total',
        type: PlutoColumnType.number(format: '#,###.00'),
        width: 120,
        readOnly: true,
        textAlign: PlutoColumnTextAlign.end,
        titleTextAlign: PlutoColumnTextAlign.end,
        enableContextMenu: false,
        renderer: (ctx) => Align(
          alignment: Alignment.centerRight,
          child: Text(Formatters.currency(ctx.cell.value as num? ?? 0)),
        ),
      ),
      textColumn('customer', l10n.fieldsCustomer, 160),
      textColumn('warehouse', l10n.fieldsWarehouse, 140),
      textColumn('remarks', l10n.fieldsNotes, 180),
    ];
  }
}
