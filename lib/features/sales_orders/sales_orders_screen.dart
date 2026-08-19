// Sales orders list screen — a read-only grid over `GET /sales-orders`
// (**server-paginated**; search/status/date filters and sorting happen
// server-side, grid-pagination §5 — the endpoint returns a `pagination`
// block). Rendered with PlutoGrid via the shared [PlutoGridScreen]
// mixin: F2/Enter + double-tap open the SO detail, and the
// [ServerPaginationBar] sits beneath the grid. Sits in the `/sales`
// branch's Sales Orders tab.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/csv_export.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/so_status.dart';
import '../../data/models/sales_order.dart' show SalesOrder;
import '../../data/repositories/paged_request.dart' show PagedResponse;
import '../../l10n/app_localizations.dart';
import '../../widgets/date_range_picker.dart' show DateRangeFilter;
import '../../widgets/pagination_bar.dart' show ServerPaginationBar;
import '../../widgets/pluto_grid_screen.dart';
import '../../widgets/screen_toolbar.dart';
import '../../widgets/status_badge.dart';
import 'sales_order_detail_dialog.dart';
import 'sales_order_form_dialog.dart';
import 'sales_order_providers.dart';

class SalesOrdersScreen extends ConsumerStatefulWidget {
  const SalesOrdersScreen({super.key});

  @override
  ConsumerState<SalesOrdersScreen> createState() => _SalesOrdersScreenState();
}

class _SalesOrdersScreenState extends ConsumerState<SalesOrdersScreen>
    with PlutoGridScreen<SalesOrder, SalesOrdersScreen> {
  Timer? _debounce;
  final TextEditingController _searchController = TextEditingController();

  @override
  void openRowDetail(int soId) {
    if (!mounted) return;
    showSalesOrderDetailDialog(context, soId: soId);
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
      ref.read(salesOrdersSearchProvider.notifier).state = value.trim();
      // A new search starts back at page 1.
      if (ref.read(salesOrdersPageProvider) != 1) {
        ref.read(salesOrdersPageProvider.notifier).state = 1;
      }
    });
  }

  bool get _hasActiveFilters =>
      ref.read(salesOrdersStatusProvider) != null ||
      ref.read(salesOrdersFromDateProvider) != null ||
      ref.read(salesOrdersToDateProvider) != null ||
      ref.read(salesOrdersSearchProvider).isNotEmpty;

  void _clearFilters() {
    _searchController.clear();
    ref.read(salesOrdersStatusProvider.notifier).state = null;
    ref.read(salesOrdersFromDateProvider.notifier).state = null;
    ref.read(salesOrdersToDateProvider.notifier).state = null;
    ref.read(salesOrdersSearchProvider.notifier).state = '';
    if (ref.read(salesOrdersPageProvider) != 1) {
      ref.read(salesOrdersPageProvider.notifier).state = 1;
    }
  }

  /// The sales-orders provider returns a `PagedResponse` envelope —
  /// unwrap the current page's items as the grid rows.
  @override
  Iterable<SalesOrder> gridRowsFrom(Object? value) =>
      (value as PagedResponse<SalesOrder>).items;

  /// Grid field → server sort column (whitelist in sqlSanitizer.ts).
  String? _sortColumnFor(String field) => switch (field) {
    'soNo' => 'so_no',
    'date' => 'so_date',
    'customer' => 'customer_name',
    'status' => 'status',
    'total' => 'total_amount',
    'delivery' => 'delivery_date',
    _ => null,
  };

  /// Column sort maps to the server-side sort provider (this endpoint is
  /// server-paginated, so ordering happens on the server).
  @override
  void onGridSorted(PlutoGridOnSortedEvent event) {
    final sortBy = _sortColumnFor(event.column.field);
    if (sortBy == null) return;
    final sort = event.column.sort;
    ref.read(salesOrdersSortProvider.notifier).state = sort.isNone
        ? null
        : SalesOrderSort(
            sortBy,
            sort == PlutoColumnSort.ascending ? 'ASC' : 'DESC',
          );
    if (ref.read(salesOrdersPageProvider) != 1) {
      ref.read(salesOrdersPageProvider.notifier).state = 1;
    }
  }

  /// Opt into the per-row ⋮ actions menu (View detail).
  @override
  bool get hasRowActions => true;

  @override
  List<GridRowAction>? gridRowActionsFor(PlutoRow row, BuildContext context) {
    final id = row.cells['id']?.value as int?;
    if (id == null || id <= 0) return null;
    final l10n = AppLocalizations.of(context)!;
    return [
      GridRowAction(
        icon: Icons.visibility_outlined,
        label: l10n.commonView,
        onTap: () => showSalesOrderDetailDialog(context, soId: id),
      ),
    ];
  }

  @override
  PlutoRow gridRowFor(SalesOrder so) => PlutoRow(
    cells: {
      'id': PlutoCell(value: so.id),
      'soNo': PlutoCell(value: so.soNo),
      'date': PlutoCell(value: so.soDate),
      'customer': PlutoCell(value: so.customerName),
      'status': PlutoCell(value: so.status),
      'total': PlutoCell(value: so.totalAmount),
      'delivery': PlutoCell(value: so.deliveryDate ?? ''),
    },
  );

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(salesOrdersProvider);
    final l10n = AppLocalizations.of(context)!;
    // The full filtered list feeds the CSV export.
    final filtered = ref.watch(filteredSalesOrdersProvider);

    // Keep the grid in sync with provider transitions (loading → data).
    // The mixin listener routes through the default syncGridRows, which
    // unwraps the PagedResponse via gridRowsFrom.
    watchGridProvider(salesOrdersProvider);

    // The filters drive the search-clear button and the dropdown, so they
    // must be watched here for the build to re-run.
    ref.watch(salesOrdersSearchProvider);
    ref.watch(salesOrdersStatusProvider);
    ref.watch(salesOrdersFromDateProvider);
    ref.watch(salesOrdersToDateProvider);

    final filteredRows = filtered.valueOrNull ?? const <SalesOrder>[];
    // Status filter options — `(label, server value)` pairs with `All` =
    // null (localized, so built per build).
    final statusOptions = <(String, String?)>[
      (l10n.commonAll, null),
      (l10n.salesordersDraft, 'Draft'),
      (l10n.salesordersConfirmed, 'Confirmed'),
      (l10n.salesordersDelivered, 'Delivered'),
      (l10n.salesordersInvoiced, 'Invoiced'),
      (l10n.salesordersCompleted, 'Completed'),
      (l10n.salesordersCancelled, 'Cancelled'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Toolbar: search + status filter + date range + actions — the
        // same header the invoices tab has.
        ScreenToolbar(
          searchController: _searchController,
          searchHint: l10n.salesordersSearchplaceholder,
          onSearchChanged: _onSearchChanged,
          filters: [
            ScreenToolbarDropdown<String?>(
              items: [for (final (_, value) in statusOptions) value],
              value: ref.watch(salesOrdersStatusProvider),
              hint: statusOptions.first.$1,
              labelBuilder: (value) {
                for (final (label, option) in statusOptions) {
                  if (option == value) return label;
                }
                return value ?? '';
              },
              width: 170,
              onChanged: (v) {
                ref.read(salesOrdersStatusProvider.notifier).state = v;
                // A new status filter starts back at page 1.
                if (ref.read(salesOrdersPageProvider) != 1) {
                  ref.read(salesOrdersPageProvider.notifier).state = 1;
                }
              },
            ),
            DateRangeFilter(
              width: 120,
              fromProvider: salesOrdersFromDateProvider,
              toProvider: salesOrdersToDateProvider,
              onChanged: () {
                // A new date range starts back at page 1.
                if (ref.read(salesOrdersPageProvider) != 1) {
                  ref.read(salesOrdersPageProvider.notifier).state = 1;
                }
              },
            ),
          ],
          onRefresh: () => ref.invalidate(salesOrdersProvider),
          onClearAll: _clearFilters,
          hasActiveFilters: _hasActiveFilters,
          actions: [
            // CSV export — runs over the currently-filtered rows; the
            // shared save helper owns the FilePicker + toast. Disabled
            // until rows are loaded.
            TextButton.icon(
              onPressed: orders.isLoading || filteredRows.isEmpty
                  ? null
                  : () => saveCsv(
                      context,
                      suggestedName: csvSuggestedName('sales-orders'),
                      csv: buildSalesOrdersCsv(l10n, filteredRows),
                      successMessage: l10n.salesordersExported,
                      errorMessage: l10n.salesordersExportfailed,
                    ),
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: Text(l10n.salesordersExportcsv),
            ),
          ],
          primaryActions: [
            FilledButton.tonalIcon(
              onPressed: () => showSalesOrderFormDialog(context),
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.salesordersNewsalesorder),
            ),
          ],
        ),
        Expanded(child: gridScreenBody(orders, provider: salesOrdersProvider)),
        if (orders.valueOrNull case final page?)
          ServerPaginationBar(
            page: page.currentPage,
            totalPages: page.totalPages,
            totalItems: page.totalItems,
            hasNext: page.hasNext,
            hasPrev: page.hasPrev,
            limit: ref.watch(salesOrdersLimitProvider),
            itemLabel: l10n.salesordersSalesorders,
            onPageChanged: (p) =>
                ref.read(salesOrdersPageProvider.notifier).state = p,
            onLimitChanged: (limit) {
              ref.read(salesOrdersLimitProvider.notifier).state = limit;
              if (ref.read(salesOrdersPageProvider) != 1) {
                ref.read(salesOrdersPageProvider.notifier).state = 1;
              }
            },
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  /// Column set — order/format mirrors the web SalesOrdersPage grid (SO
  /// No, Date, Customer, Status, Total, Delivery); read-only for now.
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
      textColumn('soNo', l10n.salesordersSono, 110),
      PlutoColumn(
        title: l10n.salesordersDate,
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
      textColumn('customer', l10n.salesordersCustomer, 220),
      PlutoColumn(
        title: l10n.salesordersStatus,
        field: 'status',
        type: PlutoColumnType.text(),
        width: 140,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) => Builder(
          builder: (cellContext) {
            final status = ctx.cell.value as String? ?? '';
            final color = soStatusColors(Theme.of(context).colorScheme, status);
            return Align(
              alignment: Alignment.centerLeft,
              child: StatusBadge(
                status: soStatusLabel(
                  AppLocalizations.of(cellContext)!,
                  status,
                ),
                color: color,
              ),
            );
          },
        ),
      ),
      PlutoColumn(
        title: l10n.commonTotal,
        field: 'total',
        type: PlutoColumnType.number(format: '#,###.00'),
        width: 110,
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
        title: l10n.salesordersDelivery,
        field: 'delivery',
        type: PlutoColumnType.text(),
        width: 140,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) => Builder(
          builder: (cellContext) {
            final value = ctx.cell.value as String? ?? '';
            return Align(
              alignment: Alignment.centerLeft,
              child: Text(
                value.isEmpty ? '—' : Formatters.date(value),
                style: Theme.of(cellContext).textTheme.bodyMedium,
              ),
            );
          },
        ),
      ),
    ];
  }
}
