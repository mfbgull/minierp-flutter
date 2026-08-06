// Stock by warehouse screen — PORTING.md §6. Read-only grid over
// `GET /inventory/stock-balances` (bare array) rendered with PlutoGrid via
// the shared [PlutoGridScreen] mixin. Each row is an item×warehouse
// balance; double-tap/F2 drills into the item's detail dialog (its
// stock-by-warehouse breakdown is what this screen aggregates).
//
// The item/warehouse code columns are hidden (they are id-like), so
// [hiddenGridColumnFields] hides them alongside the record-id column; the
// hidden `id` cell carries the balance's item id for the drill-down.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/stock_balance.dart' show StockBalance;
import '../../l10n/app_localizations.dart';
import '../../widgets/pluto_grid_screen.dart';
import 'inventory_providers.dart' show stockBalancesProvider;
import 'item_detail_dialog.dart';

class StockByWarehouseScreen extends ConsumerStatefulWidget {
  const StockByWarehouseScreen({super.key});

  @override
  ConsumerState<StockByWarehouseScreen> createState() =>
      _StockByWarehouseScreenState();
}

class _StockByWarehouseScreenState extends ConsumerState<StockByWarehouseScreen>
    with PlutoGridScreen<StockBalance, StockByWarehouseScreen> {
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

    watchGridProvider(stockBalancesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    enabled: false,
                    decoration: InputDecoration(
                      hintText: l10n.commonSearch,
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: l10n.commonRefresh,
                icon: const Icon(Icons.refresh),
                onPressed: () => ref.invalidate(stockBalancesProvider),
              ),
            ],
          ),
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
