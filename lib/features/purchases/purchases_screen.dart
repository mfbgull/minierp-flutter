// Direct purchases list screen — a read-only grid over `GET /purchases`
// (**server-paginated**; search and sorting happen server-side,
// grid-pagination §6 — the endpoint returns a `pagination` block).
// Rendered with PlutoGrid via the shared [PlutoGridScreen] mixin:
// F2/Enter + double-tap open the purchase detail, the row menu offers
// View and Return (the return entry form, pre-seeded with this
// purchase), and the [ServerPaginationBar] sits beneath the grid. Sits
// in the purchasing module shell.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/purchase.dart' show Purchase;
import '../../data/repositories/paged_request.dart' show PagedResponse;
import '../../l10n/app_localizations.dart';
import '../../widgets/pagination_bar.dart' show ServerPaginationBar;
import '../../widgets/pluto_grid_screen.dart';
import '../../widgets/screen_toolbar.dart';
import '../../widgets/app_toast.dart' show showAppToast;
import 'void_purchase_dialog.dart' show showVoidPurchaseDialog;
import 'purchase_detail_dialog.dart';
import 'purchase_form_dialog.dart';
import 'purchase_providers.dart';
import 'purchase_return_form_dialog.dart'
    show ReturnSource, showPurchaseReturnFormDialog;

class PurchasesScreen extends ConsumerStatefulWidget {
  const PurchasesScreen({super.key});

  @override
  ConsumerState<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends ConsumerState<PurchasesScreen>
    with PlutoGridScreen<Purchase, PurchasesScreen> {
  Timer? _debounce;
  final TextEditingController _searchController = TextEditingController();

  /// Row id → model for the row-menu return action — the grid rows are
  /// built from the page models, so the menu can hand the exact
  /// [Purchase] (with its returnable qty + warehouse) to the form.
  final Map<int, Purchase> _purchasesById = {};

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
      ref.read(purchasesSearchProvider.notifier).state = value.trim();
      // A new search starts back at page 1.
      if (ref.read(purchasesPageProvider) != 1) {
        ref.read(purchasesPageProvider.notifier).state = 1;
      }
    });
  }

  /// The purchases provider returns a `PagedResponse` envelope — unwrap
  /// the current page's items as the grid rows.
  @override
  Iterable<Purchase> gridRowsFrom(Object? value) =>
      (value as PagedResponse<Purchase>).items;

  /// Grid field → server sort column (whitelist in sqlSanitizer.ts).
  String? _sortColumnFor(String field) => switch (field) {
    'purchaseNo' => 'purchase_no',
    'date' => 'purchase_date',
    'item' => 'item_name',
    'qty' => 'quantity',
    'unitCost' => 'unit_cost',
    'total' => 'total_cost',
    'paid' => 'paid_amount',
    'balance' => 'balance_amount',
    'supplier' => 'supplier_name',
    'warehouse' => 'warehouse_name',
    _ => null,
  };

  /// Column sort maps to the server-side sort provider (this endpoint is
  /// server-paginated, so ordering happens on the server).
  @override
  void onGridSorted(PlutoGridOnSortedEvent event) {
    final sortBy = _sortColumnFor(event.column.field);
    if (sortBy == null) return;
    final sort = event.column.sort;
    ref.read(purchasesSortProvider.notifier).state = sort.isNone
        ? null
        : PurchaseSort(
            sortBy,
            sort == PlutoColumnSort.ascending ? 'ASC' : 'DESC',
          );
    if (ref.read(purchasesPageProvider) != 1) {
      ref.read(purchasesPageProvider.notifier).state = 1;
    }
  }

  @override
  void openRowDetail(int purchaseId) {
    if (!mounted) return;
    showPurchaseDetailDialog(context, purchaseId: purchaseId);
  }

  /// Opt into the per-row ⋮ actions menu (View detail + Return — the
  /// latter opens the return entry form pre-seeded with this purchase;
  /// hidden when nothing is returnable).
  @override
  bool get hasRowActions => true;

  @override
  List<GridRowAction>? gridRowActionsFor(PlutoRow row, BuildContext context) {
    final id = row.cells['id']?.value as int?;
    if (id == null || id <= 0) return null;
    final l10n = AppLocalizations.of(context)!;
    final purchase = _purchasesById[id];
    return [
      GridRowAction(
        icon: Icons.visibility_outlined,
        label: l10n.commonView,
        onTap: () => showPurchaseDetailDialog(context, purchaseId: id),
      ),
      if (purchase != null && purchase.returnableQty > 0)
        GridRowAction(
          icon: Icons.assignment_return_outlined,
          label: l10n.purchasesReturn,
          onTap: () => showPurchaseReturnFormDialog(
            context,
            source: ReturnSource.purchase(
              id: purchase.id,
              no: purchase.purchaseNo,
              warehouseId: purchase.warehouseId,
            ),
          ),
      ),
      GridRowAction(
        // PUR-03 (task 3.5): void with reason — never hard delete.
        icon: Icons.block_outlined,
        label: l10n.purchasesVoid,
        color: Theme.of(context).colorScheme.error,
        onTap: () => showVoidPurchaseDialog(
          context,
            id: id,
            purchaseNo: purchase?.purchaseNo ?? '#$id',
            onVoided: () {
              if (!mounted) return;
              showAppToast(context, l10n.purchasesVoid);
              ref.invalidate(purchasesProvider);
            },
        ),
      ),
    ];
  }

  @override
  PlutoRow gridRowFor(Purchase purchase) {
    _purchasesById[purchase.id] = purchase;
    return PlutoRow(
    cells: {
      'id': PlutoCell(value: purchase.id),
      'purchaseNo': PlutoCell(value: purchase.purchaseNo),
      'date': PlutoCell(value: purchase.purchaseDate),
      'item': PlutoCell(value: purchase.itemName),
      'qty': PlutoCell(value: purchase.quantity),
      'unitCost': PlutoCell(value: purchase.unitCost),
      'total': PlutoCell(value: purchase.totalCost),
      'paid': PlutoCell(value: purchase.paidAmount),
      'balance': PlutoCell(value: purchase.balanceAmount),
      'supplier': PlutoCell(value: purchase.supplierName ?? ''),
      'warehouse': PlutoCell(value: purchase.warehouseName),
      'invoiceNo': PlutoCell(value: purchase.invoiceNo ?? ''),
    },
    );
  }

  @override
  Widget build(BuildContext context) {
    final purchases = ref.watch(purchasesProvider);
    final l10n = AppLocalizations.of(context)!;

    // Keep the grid in sync with provider transitions (loading → data).
    // The mixin listener routes through the default syncGridRows, which
    // unwraps the PagedResponse via gridRowsFrom.
    watchGridProvider(purchasesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Toolbar: search + refresh.
        ScreenToolbar(
          searchController: _searchController,
          searchHint: l10n.commonSearch,
          onSearchChanged: _onSearchChanged,
          onRefresh: () => ref.invalidate(purchasesProvider),
          primaryActions: [
            FilledButton.icon(
              onPressed: () => showPurchaseFormDialog(context),
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.purchasesNewpurchase),
            ),
          ],
        ),
        Expanded(child: gridScreenBody(purchases, provider: purchasesProvider)),
        if (purchases.valueOrNull case final page?)
          ServerPaginationBar(
            page: page.currentPage,
            totalPages: page.totalPages,
            totalItems: page.totalItems,
            hasNext: page.hasNext,
            hasPrev: page.hasPrev,
            limit: ref.watch(purchasesLimitProvider),
            itemLabel: l10n.purchasesPurchases,
            onPageChanged: (p) =>
                ref.read(purchasesPageProvider.notifier).state = p,
            onLimitChanged: (limit) {
              ref.read(purchasesLimitProvider.notifier).state = limit;
              if (ref.read(purchasesPageProvider) != 1) {
                ref.read(purchasesPageProvider.notifier).state = 1;
              }
            },
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  /// Column set — order/format mirrors the web PurchasesPage grid
  /// (Purchase #, Date, Item, Qty, Unit Cost, Total, Supplier,
  /// Warehouse, Invoice No); read-only.
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

    PlutoColumn moneyColumn(String field, String title, double width) =>
        PlutoColumn(
          title: title,
          field: field,
          type: PlutoColumnType.number(format: '#,###.00'),
          width: width,
          readOnly: true,
          textAlign: PlutoColumnTextAlign.end,
          titleTextAlign: PlutoColumnTextAlign.end,
          enableContextMenu: false,
          renderer: (ctx) => Builder(
            builder: (cellContext) => Align(
              alignment: Alignment.centerRight,
              child: Text(
                Formatters.currency(ctx.cell.value as num? ?? 0),
                style: Theme.of(cellContext).textTheme.bodyMedium,
              ),
            ),
          ),
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
      textColumn('purchaseNo', l10n.purchasesPurchaseno, 120),
      PlutoColumn(
        title: l10n.purchasesDatecol,
        field: 'date',
        type: PlutoColumnType.text(),
        width: 105,
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
        title: l10n.purchasesItemcol,
        field: 'item',
        type: PlutoColumnType.text(),
        width: 190,
        readOnly: true,
        enableContextMenu: false,
      ),
      PlutoColumn(
        title: l10n.purchasesQuantitycol,
        field: 'qty',
        type: PlutoColumnType.number(format: '#,###.00'),
        width: 85,
        readOnly: true,
        textAlign: PlutoColumnTextAlign.end,
        titleTextAlign: PlutoColumnTextAlign.end,
        enableContextMenu: false,
      ),
      moneyColumn('unitCost', l10n.purchasesUnitcost, 100),
      moneyColumn('total', l10n.purchasesTotalcol, 110),
      moneyColumn('paid', l10n.salesTotalpaid, 105),
      PlutoColumn(
        title: l10n.salesBalance,
        field: 'balance',
        type: PlutoColumnType.number(format: '#,###.00'),
        width: 105,
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
                  // Fully paid → green; outstanding → the error tone.
                  color: balance > 0
                      ? scheme.error
                      : const Color(0xff16a34a),
                ),
              ),
            );
          },
        ),
      ),
      textColumn('supplier', l10n.purchasesSuppliercol, 170),
      textColumn('warehouse', l10n.purchasesWarehousecol, 130),
      textColumn('invoiceNo', l10n.purchasesInvoicenumber, 110),
    ];
  }
}
