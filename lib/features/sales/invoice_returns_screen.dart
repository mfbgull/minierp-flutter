// Invoice returns list screen — a read-only grid over `GET
// /invoices/returns` (**server-paginated**; search/warehouse/date filters
// and sorting happen server-side, grid-pagination §5 — the endpoint
// returns a `pagination` block). Rendered with PlutoGrid via the shared
// [PlutoGridScreen] mixin: F2/Enter + double-tap open the return detail,
// and the [ServerPaginationBar] sits beneath the grid. Hosted as the
// 'Invoice Returns' tab of the sales shell.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/csv_export.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/sales_return.dart' show SalesReturn;
import '../../data/models/warehouse.dart' show Warehouse;
import '../../data/repositories/paged_request.dart' show PagedResponse;
import '../../features/inventory/inventory_providers.dart'
    show warehousesProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/date_range_picker.dart' show DateRangeFilter;
import '../../widgets/pagination_bar.dart' show ServerPaginationBar;
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
      // A new search starts back at page 1.
      if (ref.read(invoiceReturnsPageProvider) != 1) {
        ref.read(invoiceReturnsPageProvider.notifier).state = 1;
      }
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
    if (ref.read(invoiceReturnsPageProvider) != 1) {
      ref.read(invoiceReturnsPageProvider.notifier).state = 1;
    }
  }

  /// The returns provider returns a `PagedResponse` envelope — unwrap the
  /// current page's items as the grid rows.
  @override
  Iterable<SalesReturn> gridRowsFrom(Object? value) =>
      (value as PagedResponse<SalesReturn>).items;

  /// Grid field → server sort column (whitelist in sqlSanitizer.ts).
  String? _sortColumnFor(String field) => switch (field) {
    'returnNo' => 'movement_no',
    'date' => 'return_date',
    'item' => 'item_name',
    'customer' => 'customer_name',
    'warehouse' => 'warehouse_name',
    'qty' => 'quantity',
    'unitCost' => 'unit_cost',
    _ => null,
  };

  /// Column sort maps to the server-side sort provider (this endpoint is
  /// server-paginated, so ordering happens on the server).
  @override
  void onGridSorted(PlutoGridOnSortedEvent event) {
    final sortBy = _sortColumnFor(event.column.field);
    if (sortBy == null) return;
    final sort = event.column.sort;
    ref.read(invoiceReturnsSortProvider.notifier).state = sort.isNone
        ? null
        : InvoiceReturnSort(
            sortBy,
            sort == PlutoColumnSort.ascending ? 'ASC' : 'DESC',
          );
    if (ref.read(invoiceReturnsPageProvider) != 1) {
      ref.read(invoiceReturnsPageProvider.notifier).state = 1;
    }
  }

  /// Opt into the per-row ⋮ actions menu (View detail).
  @override
  bool get hasRowActions => true;

  @override
  List<GridRowAction>? gridRowActionsFor(PlutoRow row, BuildContext context) {
    final id = row.cells['id']?.value as int?;
    if (id == null || id <= 0) return null;
    final salesReturn = _returnsById[id];
    if (salesReturn == null) return null;
    final l10n = AppLocalizations.of(context)!;
    return [
      GridRowAction(
        icon: Icons.visibility_outlined,
        label: l10n.commonView,
        onTap: () =>
            showInvoiceReturnDetailDialog(context, salesReturn: salesReturn),
      ),
    ];
  }

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
    // The full filtered list feeds the CSV export.
    final filtered = ref.watch(filteredInvoiceReturnsProvider);
    // Warehouse filter options — `All` (null) plus every active
    // warehouse (from the warehouses list; the filter matches
    // `warehouse_name` server-side).
    final warehouseOptions =
        (ref.watch(warehousesProvider).valueOrNull ?? const <Warehouse>[])
            .map((w) => w.warehouseName ?? '')
            .where((n) => n.isNotEmpty)
            .toList()
          ..sort();

    // Keep the grid in sync with provider transitions (loading → data).
    // The mixin listener routes through the default syncGridRows, which
    // unwraps the PagedResponse via gridRowsFrom.
    watchGridProvider(invoiceReturnsProvider);

    // The filters drive the search-clear button and the warehouse
    // dropdown, so they must be watched here for the build to re-run.
    ref.watch(invoiceReturnsSearchProvider);
    ref.watch(invoiceReturnsWarehouseProvider);
    ref.watch(invoiceReturnsFromDateProvider);
    ref.watch(invoiceReturnsToDateProvider);

    final filteredRows = filtered.valueOrNull ?? const <SalesReturn>[];

    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = constraints.maxWidth < 768;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Toolbar: search + warehouse filter + date range + actions —
            // the same header the invoices tab has (the New slot opens the
            // Process Return picker, since returns are created against an
            // invoice). The shared toolbar wraps, so the picker stays
            // reachable on mobile.
            ScreenToolbar(
              searchController: _searchController,
              searchHint: l10n.salesreturnsSearchplaceholder,
              onSearchChanged: _onSearchChanged,
              filters: [
                ScreenToolbarDropdown<String?>(
                  items: [null, ...warehouseOptions],
                  value: ref.watch(invoiceReturnsWarehouseProvider),
                  hint: l10n.commonAll,
                  labelBuilder: (v) => v ?? l10n.commonAll,
                  width: 170,
                  onChanged: (v) {
                    ref.read(invoiceReturnsWarehouseProvider.notifier).state =
                        v;
                    // A new warehouse filter starts back at page 1.
                    if (ref.read(invoiceReturnsPageProvider) != 1) {
                      ref.read(invoiceReturnsPageProvider.notifier).state = 1;
                    }
                  },
                ),
                DateRangeFilter(
                  width: 120,
                  fromProvider: invoiceReturnsFromDateProvider,
                  toProvider: invoiceReturnsToDateProvider,
                  onChanged: () {
                    // A new date range starts back at page 1.
                    if (ref.read(invoiceReturnsPageProvider) != 1) {
                      ref.read(invoiceReturnsPageProvider.notifier).state = 1;
                    }
                  },
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
                          csv: buildInvoiceReturnsCsv(l10n, filteredRows),
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
              child: mobile
                  ? _mobileList(l10n)
                  : gridScreenBody(returns, provider: invoiceReturnsProvider),
            ),
            if (!mobile)
              if (returns.valueOrNull case final page?)
                ServerPaginationBar(
                  page: page.currentPage,
                  totalPages: page.totalPages,
                  totalItems: page.totalItems,
                  hasNext: page.hasNext,
                  hasPrev: page.hasPrev,
                  limit: ref.watch(invoiceReturnsLimitProvider),
                  itemLabel: l10n.salesreturnsReturns,
                  onPageChanged: (p) =>
                      ref.read(invoiceReturnsPageProvider.notifier).state = p,
                  onLimitChanged: (limit) {
                    ref.read(invoiceReturnsLimitProvider.notifier).state =
                        limit;
                    if (ref.read(invoiceReturnsPageProvider) != 1) {
                      ref.read(invoiceReturnsPageProvider.notifier).state = 1;
                    }
                  },
                ),
            if (!mobile) const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  /// Compact cards under 768px (Compact Card System — modeled on
  /// `PurchaseReturnsScreen._mobileList`): one card per return line fed
  /// by the full *filtered* list provider, so the search + warehouse +
  /// date filters apply to the mobile view too. Tapping a card opens the
  /// same [InvoiceReturnDetailDialog] the grid F2/Enter opens. The
  /// toolbar's Process Return primary action (source picker → return
  /// dialog with the required restock-warehouse picker) stays above the
  /// list.
  Widget _mobileList(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final filtered = ref.watch(filteredInvoiceReturnsProvider);
    return filtered.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('$error', style: TextStyle(color: scheme.error)),
        ),
      ),
      data: (rows) => rows.isEmpty
          ? Center(
              child: Text(
                l10n.salesreturnsReturnnoitems,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final salesReturn = rows[i];
                return _CompactInvoiceReturnCard(
                  salesReturn: salesReturn,
                  l10n: l10n,
                  onTap: () => showInvoiceReturnDetailDialog(
                    context,
                    salesReturn: salesReturn,
                  ),
                );
              },
            ),
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

/// One compact card for the mobile invoice-returns list — mirrors the
/// grid's columns (item, return no + invoice ref, date, qty / unit cost /
/// total, customer, warehouse, remarks). Tapping the card opens the same
/// [InvoiceReturnDetailDialog] the grid opens.
class _CompactInvoiceReturnCard extends StatelessWidget {
  const _CompactInvoiceReturnCard({
    required this.salesReturn,
    required this.l10n,
    required this.onTap,
  });

  final SalesReturn salesReturn;
  final AppLocalizations l10n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final r = salesReturn;
    final remarks = r.remarks?.trim();

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.itemName,
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (r.itemCode.isNotEmpty)
                          Text(
                            r.itemCode,
                            style: textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    Formatters.date(r.returnDate),
                    style: textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${l10n.salesreturnsReturnno}: ${r.movementNo}',
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _cardStat(
                    context,
                    l10n.salesreturnsReturnqty,
                    Formatters.number(r.quantity),
                  ),
                  _cardStat(
                    context,
                    l10n.fieldsCost,
                    Formatters.currency(r.unitCost),
                  ),
                  _cardStat(
                    context,
                    l10n.salesreturnsReturnvalue,
                    Formatters.currency(r.returnValue),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _metaLine(
                      context,
                      Icons.person_outline,
                      r.customerName ?? '',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _metaLine(
                      context,
                      Icons.warehouse_outlined,
                      r.warehouseName,
                    ),
                  ),
                ],
              ),
              if (remarks != null && remarks.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  remarks,
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _metaLine(BuildContext context, IconData icon, String text) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Icon(icon, size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _cardStat(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
