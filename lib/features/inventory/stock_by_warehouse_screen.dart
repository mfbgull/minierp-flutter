// Stock by warehouse screen — PORTING.md §6. Read-only grid over
// `GET /inventory/stock-balances` (server-paginated, `search` +
// `warehouse_code` filters) rendered with PlutoGrid via the shared
// [PlutoGridScreen] mixin. Each row is an item×warehouse balance;
// double-tap/F2 drills into the item's detail dialog (its
// stock-by-warehouse breakdown is what this screen aggregates). Search /
// warehouse filter / sorting / paging all refetch server-side.
//
// The item/warehouse code columns are hidden (they are id-like), so
// [hiddenGridColumnFields] hides them alongside the record-id column; the
// hidden `id` cell carries the balance's item id for the drill-down.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/stock_balance.dart' show StockBalance;
import '../../data/repositories/paged_request.dart' show PagedResponse;
import '../../l10n/app_localizations.dart';
import '../../widgets/pagination_bar.dart';
import '../../widgets/pluto_grid_screen.dart';
import '../../widgets/screen_toolbar.dart';
import 'inventory_providers.dart'
    show
        GridSort,
        stockBalancesLimitProvider,
        stockBalancesPageProvider,
        stockBalancesProvider,
        stockBalancesSearchProvider,
        stockBalancesSortProvider,
        stockBalancesWarehouseFilterProvider,
        warehousesProvider;
import 'item_detail_dialog.dart';

class StockByWarehouseScreen extends ConsumerStatefulWidget {
  const StockByWarehouseScreen({super.key});

  @override
  ConsumerState<StockByWarehouseScreen> createState() =>
      _StockByWarehouseScreenState();
}

class _StockByWarehouseScreenState extends ConsumerState<StockByWarehouseScreen>
    with PlutoGridScreen<StockBalance, StockByWarehouseScreen> {
  Timer? _debounce;
  final TextEditingController _searchController = TextEditingController();

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
      ref.read(stockBalancesSearchProvider.notifier).state = value.trim();
      // A new search starts back at page 1.
      if (ref.read(stockBalancesPageProvider) != 1) {
        ref.read(stockBalancesPageProvider.notifier).state = 1;
      }
    });
  }

  /// The stock-balances provider returns a `PagedResponse` envelope —
  /// unwrap the current page's items as the grid rows.
  @override
  Iterable<StockBalance> gridRowsFrom(Object? value) =>
      (value as PagedResponse<StockBalance>).items;

  /// Grid field → server sort column (whitelist in sqlSanitizer.ts).
  String? _sortColumnFor(String field) => switch (field) {
    'code' => 'item_code',
    'item' => 'item_name',
    'warehouse' => 'warehouse_name',
    'qty' => 'quantity',
    _ => null,
  };

  /// Column sort maps to the server-side sort provider (this endpoint is
  /// server-paginated, so ordering happens on the server).
  @override
  void onGridSorted(PlutoGridOnSortedEvent event) {
    final sortBy = _sortColumnFor(event.column.field);
    if (sortBy == null) return;
    final sort = event.column.sort;
    ref.read(stockBalancesSortProvider.notifier).state = sort.isNone
        ? null
        : GridSort(
            sortBy,
            sort == PlutoColumnSort.ascending ? 'ASC' : 'DESC',
          );
    if (ref.read(stockBalancesPageProvider) != 1) {
      ref.read(stockBalancesPageProvider.notifier).state = 1;
    }
  }

  @override
  List<String> get hiddenGridColumnFields => const ['id', 'code', 'codeWh'];

  @override
  void openRowDetail(int itemId) {
    if (!mounted) return;
    showItemDetailDialog(context, itemId: itemId);
  }

  /// Opt into the per-row ⋮ actions menu (View item detail).
  @override
  bool get hasRowActions => true;

  @override
  List<GridRowAction>? gridRowActionsFor(PlutoRow row, BuildContext context) {
    final itemId = row.cells['id']?.value as int?;
    if (itemId == null || itemId <= 0) return null;
    final l10n = AppLocalizations.of(context)!;
    return [
      GridRowAction(
        icon: Icons.visibility_outlined,
        label: l10n.commonView,
        onTap: () => showItemDetailDialog(context, itemId: itemId),
      ),
    ];
  }

  @override
  PlutoRow gridRowFor(StockBalance balance) => PlutoRow(
    cells: {
      'id': PlutoCell(value: balance.itemId),
      'code': PlutoCell(value: balance.itemCode),
      'item': PlutoCell(value: balance.itemName),
      'warehouse': PlutoCell(value: balance.warehouseName),
      'codeWh': PlutoCell(value: balance.warehouseCode),
      'qty': PlutoCell(value: balance.quantity),
    },
  );

  @override
  Widget build(BuildContext context) {
    final balances = ref.watch(stockBalancesProvider);
    final page = balances.valueOrNull;
    final warehouses = ref.watch(warehousesProvider).valueOrNull ?? const [];
    final selectedWarehouse = ref.watch(stockBalancesWarehouseFilterProvider);
    final l10n = AppLocalizations.of(context)!;

    // Keep the grid in sync with provider transitions (loading → data).
    // Search / warehouse filter refetch server-side through the paged
    // provider (it watches both), so no client-side refilter is needed.
    watchGridProvider(stockBalancesProvider);

    String warehouseLabel(String code) {
      if (code.isEmpty) return l10n.stockbywarehouseAllwarehouses;
      final match = warehouses.where((w) => w.warehouseCode == code);
      return match.isEmpty ? code : '${match.first.warehouseCode} — ${match.first.warehouseName ?? ''}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Toolbar: warehouse dropdown + server-side search (item code/name,
        // warehouse) + refresh.
        ScreenToolbar(
          filters: [
            ScreenToolbarDropdown<String>(
              value: selectedWarehouse,
              items: [
                '',
                for (final w in warehouses) w.warehouseCode,
              ],
              labelBuilder: warehouseLabel,
              hint: l10n.stockbywarehouseAllwarehouses,
              width: 210,
              prefixIcon: Icons.warehouse_outlined,
              onChanged: (value) {
                ref.read(stockBalancesWarehouseFilterProvider.notifier).state =
                    value ?? '';
                // A new filter starts back at page 1.
                if (ref.read(stockBalancesPageProvider) != 1) {
                  ref.read(stockBalancesPageProvider.notifier).state = 1;
                }
              },
            ),
          ],
          searchController: _searchController,
          searchHint: l10n.commonSearch,
          onSearchChanged: _onSearchChanged,
          onRefresh: () => ref.invalidate(stockBalancesProvider),
        ),
        Expanded(
          child: gridScreenBody(balances, provider: stockBalancesProvider),
        ),
        if (page != null)
          ServerPaginationBar(
            page: page.currentPage,
            totalPages: page.totalPages,
            totalItems: page.totalItems,
            hasNext: page.hasNext,
            hasPrev: page.hasPrev,
            limit: ref.watch(stockBalancesLimitProvider),
            itemLabel: l10n.stockbywarehouseStock,
            onPageChanged: (p) =>
                ref.read(stockBalancesPageProvider.notifier).state = p,
            onLimitChanged: (limit) {
              ref.read(stockBalancesLimitProvider.notifier).state = limit;
              if (ref.read(stockBalancesPageProvider) != 1) {
                ref.read(stockBalancesPageProvider.notifier).state = 1;
              }
            },
          ),
      ],
    );
  }

  @override
  List<PlutoColumn> buildGridColumns(AppLocalizations l10n) => [
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
    PlutoColumn(
      title: 'Item Code',
      field: 'code',
      type: PlutoColumnType.text(),
      width: 100,
      readOnly: true,
      enableContextMenu: false,
    ),
    PlutoColumn(
      title: 'Item',
      field: 'item',
      type: PlutoColumnType.text(),
      width: 260,
      readOnly: true,
      enableContextMenu: false,
    ),
    PlutoColumn(
      title: 'Warehouse',
      field: 'warehouse',
      type: PlutoColumnType.text(),
      width: 220,
      readOnly: true,
      enableContextMenu: false,
    ),
    PlutoColumn(
      title: 'WH Code',
      field: 'codeWh',
      type: PlutoColumnType.text(),
      width: 110,
      readOnly: true,
      enableContextMenu: false,
    ),
    PlutoColumn(
      title: 'Quantity',
      field: 'qty',
      type: PlutoColumnType.number(format: '#,###.##'),
      width: 120,
      readOnly: true,
      textAlign: PlutoColumnTextAlign.end,
      titleTextAlign: PlutoColumnTextAlign.end,
      enableContextMenu: false,
      renderer: (ctx) => Align(
        alignment: Alignment.centerRight,
        child: Text(Formatters.number(ctx.cell.value as num? ?? 0)),
      ),
    ),
  ];
}
