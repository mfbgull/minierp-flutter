// Purchase orders list screen — a read-only grid over `GET
// /purchase-orders` (**server-paginated**; search and sorting happen
// server-side, grid-pagination §6 — the endpoint returns a `pagination`
// block). Rendered with PlutoGrid via the shared [PlutoGridScreen]
// mixin: F2/Enter + double-tap open the PO detail, and the
// [ServerPaginationBar] sits beneath the grid. Sits at the shell branch
// `/purchasing`.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/csv_export.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/po_status.dart';
import '../../data/models/purchase_order.dart' show PurchaseOrder;
import '../../data/repositories/paged_request.dart' show PagedResponse;
import '../../l10n/app_localizations.dart';
import '../../widgets/pagination_bar.dart' show ServerPaginationBar;
import '../../widgets/pluto_grid_screen.dart';
import '../../widgets/date_range_picker.dart' show DateRangeFilter;
import '../../widgets/screen_toolbar.dart';
import '../../widgets/status_badge.dart';
import '../../features/purchases/purchase_return_form_dialog.dart'
    show ReturnSource, showPurchaseReturnFormDialog;
import 'purchase_order_detail_dialog.dart';
import 'purchase_order_form_dialog.dart';
import 'purchase_order_providers.dart'
    show
        PurchaseOrderSort,
        filteredPurchaseOrdersProvider,
        purchaseOrdersFromDateProvider,
        purchaseOrdersLimitProvider,
        purchaseOrdersPageProvider,
        purchaseOrdersProvider,
        purchaseOrdersSearchProvider,
        purchaseOrdersSortProvider,
        purchaseOrdersToDateProvider;

class PurchaseOrdersScreen extends ConsumerStatefulWidget {
  const PurchaseOrdersScreen({super.key});

  @override
  ConsumerState<PurchaseOrdersScreen> createState() =>
      _PurchaseOrdersScreenState();
}

class _PurchaseOrdersScreenState extends ConsumerState<PurchaseOrdersScreen>
    with PlutoGridScreen<PurchaseOrder, PurchaseOrdersScreen> {
  Timer? _debounce;
  final TextEditingController _searchController = TextEditingController();

  /// Row id → model for the row-menu return action — the grid rows are
  /// built from the page models, so the menu can pre-seed the return
  /// form with the exact PO (its number + warehouse).
  final Map<int, PurchaseOrder> _ordersById = {};

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
      ref.read(purchaseOrdersSearchProvider.notifier).state = value.trim();
      // A new search starts back at page 1.
      if (ref.read(purchaseOrdersPageProvider) != 1) {
        ref.read(purchaseOrdersPageProvider.notifier).state = 1;
      }
    });
  }

  /// The purchase-orders provider returns a `PagedResponse` envelope —
  /// unwrap the current page's items as the grid rows.
  @override
  Iterable<PurchaseOrder> gridRowsFrom(Object? value) =>
      (value as PagedResponse<PurchaseOrder>).items;

  /// Grid field → server sort column (whitelist in sqlSanitizer.ts).
  String? _sortColumnFor(String field) => switch (field) {
    'poNo' => 'po_no',
    'date' => 'po_date',
    'supplier' => 'supplier_name',
    'status' => 'status',
    'total' => 'total_amount',
    'balance' => 'balance_amount',
    'expected' => 'expected_delivery_date',
    _ => null,
  };

  /// Column sort maps to the server-side sort provider (this endpoint is
  /// server-paginated, so ordering happens on the server).
  @override
  void onGridSorted(PlutoGridOnSortedEvent event) {
    final sortBy = _sortColumnFor(event.column.field);
    if (sortBy == null) return;
    final sort = event.column.sort;
    ref.read(purchaseOrdersSortProvider.notifier).state = sort.isNone
        ? null
        : PurchaseOrderSort(
            sortBy,
            sort == PlutoColumnSort.ascending ? 'ASC' : 'DESC',
          );
    if (ref.read(purchaseOrdersPageProvider) != 1) {
      ref.read(purchaseOrdersPageProvider.notifier).state = 1;
    }
  }

  @override
  void openRowDetail(int poId) {
    if (!mounted) return;
    showPurchaseOrderDetailDialog(context, poId: poId);
  }

  /// Opt into the per-row ⋮ actions menu (View detail + Process Return —
  /// the latter opens the return entry form pre-seeded with this PO; the
  /// form loads the PO detail and shows only received lines).
  @override
  bool get hasRowActions => true;

  @override
  List<GridRowAction>? gridRowActionsFor(PlutoRow row, BuildContext context) {
    final id = row.cells['id']?.value as int?;
    if (id == null || id <= 0) return null;
    final l10n = AppLocalizations.of(context)!;
    final po = _ordersById[id];
    return [
      GridRowAction(
        icon: Icons.visibility_outlined,
        label: l10n.commonView,
        onTap: () => showPurchaseOrderDetailDialog(context, poId: id),
      ),
      if (po != null && po.status != 'Draft')
        GridRowAction(
          icon: Icons.assignment_return_outlined,
          label: l10n.purchasesProcessreturn,
          onTap: () => showPurchaseReturnFormDialog(
            context,
            source: ReturnSource.purchaseOrder(
              id: po.id,
              no: po.poNo,
              warehouseId: po.warehouseId,
            ),
          ),
        ),
    ];
  }

  @override
  PlutoRow gridRowFor(PurchaseOrder po) {
    _ordersById[po.id] = po;
    return PlutoRow(
    cells: {
      'id': PlutoCell(value: po.id),
      'poNo': PlutoCell(value: po.poNo),
      'date': PlutoCell(value: po.poDate),
      'supplier': PlutoCell(value: po.supplierName),
      'status': PlutoCell(value: po.status),
      'total': PlutoCell(value: po.totalAmount),
      'balance': PlutoCell(value: po.balanceAmount),
      'expected': PlutoCell(value: po.expectedDeliveryDate ?? ''),
    },
    );
  }

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(purchaseOrdersProvider);
    final l10n = AppLocalizations.of(context)!;
    // The full filtered list feeds the CSV export.
    final filtered = ref.watch(filteredPurchaseOrdersProvider);

    // Keep the grid in sync with provider transitions (loading → data).
    // The mixin listener routes through the default syncGridRows, which
    // unwraps the PagedResponse via gridRowsFrom.
    watchGridProvider(purchaseOrdersProvider);

    final filteredRows = filtered.valueOrNull ?? const <PurchaseOrder>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Toolbar: search + CSV export + refresh + New PO.
        ScreenToolbar(
          searchController: _searchController,
          searchHint: l10n.commonSearch,
          onSearchChanged: _onSearchChanged,
          onRefresh: () => ref.invalidate(purchaseOrdersProvider),
          filters: [
            DateRangeFilter(
              fromProvider: purchaseOrdersFromDateProvider,
              toProvider: purchaseOrdersToDateProvider,
              onChanged: () {
                if (ref.read(purchaseOrdersPageProvider) != 1) {
                  ref.read(purchaseOrdersPageProvider.notifier).state = 1;
                }
              },
            ),
          ],
          actions: [
            // CSV export — mirrors the sales-orders/returns grids: the
            // pure builder runs over the currently-filtered rows and
            // the shared save helper owns the FilePicker + toast.
            TextButton.icon(
              onPressed: orders.isLoading || filteredRows.isEmpty
                  ? null
                  : () => saveCsv(
                      context,
                      suggestedName: csvSuggestedName('purchase-orders'),
                      csv: buildPurchaseOrdersCsv(l10n, filteredRows),
                      successMessage: l10n.purchaseordersExported,
                      errorMessage: l10n.purchaseordersExportfailed,
                    ),
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: Text(l10n.purchaseordersExportcsv),
            ),
          ],
          primaryActions: [
            FilledButton.tonalIcon(
              onPressed: () => showPurchaseOrderFormDialog(context),
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.purchaseordersNewpurchaseorder),
            ),
          ],
        ),
        Expanded(
          child: gridScreenBody(orders, provider: purchaseOrdersProvider),
        ),
        if (orders.valueOrNull case final page?)
          ServerPaginationBar(
            page: page.currentPage,
            totalPages: page.totalPages,
            totalItems: page.totalItems,
            hasNext: page.hasNext,
            hasPrev: page.hasPrev,
            limit: ref.watch(purchaseOrdersLimitProvider),
            itemLabel: l10n.purchaseordersPurchaseorders,
            onPageChanged: (p) =>
                ref.read(purchaseOrdersPageProvider.notifier).state = p,
            onLimitChanged: (limit) {
              ref.read(purchaseOrdersLimitProvider.notifier).state = limit;
              if (ref.read(purchaseOrdersPageProvider) != 1) {
                ref.read(purchaseOrdersPageProvider.notifier).state = 1;
              }
            },
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  /// Column set — order/format mirrors the web POSTab grid (PO No, Date,
  /// Status, Total, Expected Delivery) plus Supplier for the standalone
  /// list; read-only for now.
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
      textColumn('poNo', l10n.purchaseordersPono, 110),
      PlutoColumn(
        title: l10n.commonDate,
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
      PlutoColumn(
        title: l10n.purchasesSuppliercol,
        field: 'supplier',
        type: PlutoColumnType.text(),
        width: 220,
        readOnly: true,
        enableContextMenu: false,
      ),
      PlutoColumn(
        title: l10n.commonStatus,
        field: 'status',
        type: PlutoColumnType.text(),
        width: 140,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) => Builder(
          builder: (cellContext) {
            final status = ctx.cell.value as String? ?? '';
            final color = poStatusColors(Theme.of(context).colorScheme, status);
            return Align(
              alignment: Alignment.centerLeft,
              child: StatusBadge(
                status: poStatusLabel(
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
        title: l10n.purchaseordersBalance,
        field: 'balance',
        type: PlutoColumnType.number(format: '#,###.00'),
        width: 110,
        readOnly: true,
        textAlign: PlutoColumnTextAlign.end,
        titleTextAlign: PlutoColumnTextAlign.end,
        enableContextMenu: false,
        renderer: (ctx) => Builder(
          builder: (cellContext) {
            final scheme = Theme.of(cellContext).colorScheme;
            final balance = ctx.cell.value as num? ?? 0;
            return Align(
              alignment: Alignment.centerRight,
              child: Text(
                Formatters.currency(balance),
                style: Theme.of(cellContext).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  // Outstanding → error tone; fully paid → green.
                  color: balance > 0
                      ? scheme.error
                      : const Color(0xff16a34a),
                ),
              ),
            );
          },
        ),
      ),
      PlutoColumn(
        title: l10n.purchaseordersExpecteddelivery,
        field: 'expected',
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
