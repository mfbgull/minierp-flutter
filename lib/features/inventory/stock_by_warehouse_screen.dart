// Stock by warehouse screen — PORTING.md §6. Read-only grid over
// `GET /inventory/stock-balances` (bare array) rendered with PlutoGrid via
// the shared [PlutoGridScreen] mixin. Each row is an item×warehouse
// balance; double-tap/F2 drills into the item's detail dialog (its
// stock-by-warehouse breakdown is what this screen aggregates).
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
import '../../l10n/app_localizations.dart';
import '../../widgets/pluto_grid_screen.dart';
import '../../widgets/screen_toolbar.dart';
import 'inventory_providers.dart' show stockBalancesProvider, stockBalancesSearchProvider;
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
    });
  }

  /// Client-side search over the loaded rows (the endpoint has no search
  /// param) — overrides the mixin's unfiltered clear+append.
  List<StockBalance> _filteredRows(List<StockBalance> balances) {
    final search = ref.read(stockBalancesSearchProvider).toLowerCase();
    if (search.isEmpty) return balances;
    return balances
        .where(
          (b) =>
              b.itemCode.toLowerCase().contains(search) ||
              b.itemName.toLowerCase().contains(search) ||
              b.warehouseName.toLowerCase().contains(search),
        )
        .toList();
  }

  @override
  void syncGridRows(AsyncValue<Object?> value) {
    final manager = gridStateManager;
    if (manager == null) return;
    manager.setShowLoading(value.isLoading);
    if (value.hasValue) {
      final rows = _filteredRows(value.value as List<StockBalance>);
      manager.removeAllRows();
      manager.appendRows([
        for (final (index, row) in rows.indexed)
          withSerialCell(gridRowFor(row), index),
      ]);
    }
  }

  void _refilter() => syncGridRows(ref.read(stockBalancesProvider));

  @override
  List<String> get hiddenGridColumnFields => const ['id', 'code', 'codeWh'];

  @override
  void openRowDetail(int itemId) {
    if (!mounted) return;
    showItemDetailDialog(context, itemId: itemId);
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
    final l10n = AppLocalizations.of(context)!;

    // Keep the grid in sync with provider transitions (loading → data).
    // The mixin listener routes through the overridden syncGridRows, so
    // the client-side search applies on every load/refresh too.
    watchGridProvider(stockBalancesProvider);
    // Client-side search re-runs the filter over the loaded rows without
    // refetching.
    ref.listen(stockBalancesSearchProvider, (previous, next) => _refilter());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Toolbar: client-side search (item code/name, warehouse) + refresh.
        ScreenToolbar(
          searchController: _searchController,
          searchHint: l10n.commonSearch,
          onSearchChanged: _onSearchChanged,
          onRefresh: () => ref.invalidate(stockBalancesProvider),
        ),
        Expanded(
          child: gridScreenBody(balances, provider: stockBalancesProvider),
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
