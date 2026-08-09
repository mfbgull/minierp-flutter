// Stock movements list screen — PORTING.md §6. Read-only grid over
// `GET /inventory/stock-movements` (bare array) rendered with PlutoGrid
// via the shared [PlutoGridScreen] mixin. Double-tap/F2 opens the
// movement's read-only detail dialog; the grid row's hidden `id` cell
// carries the id.
//
// The toolbar's filter dropdown refetches the list with the
// `movement_type` query param (the endpoint also accepts date/other
// filters — only type is exposed so far).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../data/models/stock_movement.dart' show StockMovement;
import '../../l10n/app_localizations.dart';
import '../../widgets/pluto_grid_screen.dart';
import '../../widgets/searchable_select.dart';
import '../../widgets/status_badge.dart';
import 'inventory_providers.dart'
    show movementTypeFilterProvider, stockMovementsProvider;
import 'stock_adjustment_dialog.dart';
import 'stock_transfer_dialog.dart';
import 'stock_movement_detail_dialog.dart';

class StockMovementScreen extends ConsumerStatefulWidget {
  const StockMovementScreen({super.key});

  @override
  ConsumerState<StockMovementScreen> createState() =>
      _StockMovementScreenState();
}

class _StockMovementScreenState extends ConsumerState<StockMovementScreen>
    with PlutoGridScreen<StockMovement, StockMovementScreen> {
  List<StockMovement> _movements = const [];

  T? _firstWhereOrNull<T>(Iterable<T> items, bool Function(T) test) {
    for (final item in items) {
      if (test(item)) return item;
    }
    return null;
  }

  @override
  void openRowDetail(int rowId) {
    final movement = _firstWhereOrNull(_movements, (m) => m.id == rowId);
    if (movement == null) return;
    showStockMovementDetailDialog(context, movement: movement);
  }

  @override
  PlutoRow gridRowFor(StockMovement m) => PlutoRow(
    cells: {
      'id': PlutoCell(value: m.id),
      'no': PlutoCell(value: m.movementNo),
      'date': PlutoCell(value: m.movementDate),
      'item': PlutoCell(value: m.itemName ?? ''),
      'warehouse': PlutoCell(value: m.warehouseName ?? ''),
      'type': PlutoCell(value: m.movementType),
      'qty': PlutoCell(value: m.quantity),
      'ref': PlutoCell(value: m.referenceDocNo ?? ''),
      'remarks': PlutoCell(value: m.remarks ?? ''),
    },
  );

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(movementTypeFilterProvider);
    final movements = ref.watch(stockMovementsProvider(filter));
    // `value` rethrows the AsyncError — tolerate a failed/loading fetch
    // like the other grids (the grid pane shows its own error/empty
    // states).
    _movements = movements.valueOrNull ?? const [];
    final l10n = AppLocalizations.of(context)!;

    watchGridProvider(stockMovementsProvider(filter));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              // Movement-type filter — the endpoint accepts a
              // `movement_type` query param (no free-text search exists).
              SizedBox(
                width: 210,
                height: 40,
                child: SearchableSelect<String>(
                  items: [
                    for (final option in _movementFilterOptions(l10n))
                      option.$1,
                  ],
                  selected: filter ?? '',
                  labelBuilder: (value) {
                    for (final option in _movementFilterOptions(l10n)) {
                      if (option.$1 == value) return option.$2;
                    }
                    return value;
                  },
                  isDense: true,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(
                      Icons.filter_alt_outlined,
                      size: 20,
                    ),
                    contentPadding: EdgeInsets.zero,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onChanged: (value) {
                    final newFilter = (value == null || value.isEmpty)
                        ? null
                        : value;
                    ref.read(movementTypeFilterProvider.notifier).state =
                        newFilter;
                    // Switching back to All must refetch: the null-keyed
                    // family instance may be stale from an earlier load
                    // (and a movement posted under a filter won't appear
                    // in it otherwise).
                    if (newFilter == null) {
                      ref.invalidate(stockMovementsProvider(null));
                    }
                  },
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => showStockTransferDialog(context),
                icon: const Icon(Icons.swap_horiz, size: 18),
                label: Text(l10n.stockmovementsNewtransfer),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => showStockAdjustmentDialog(context),
                icon: const Icon(Icons.tune, size: 18),
                label: Text(l10n.stockmovementsNewadjustment),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: l10n.commonRefresh,
                icon: const Icon(Icons.refresh),
                onPressed: () => ref.invalidate(stockMovementsProvider(filter)),
              ),
            ],
          ),
        ),
        Expanded(
          child: gridScreenBody(
            movements,
            provider: stockMovementsProvider(filter),
          ),
        ),
      ],
    );
  }

  /// Movement-type filter options — `(query value, label)` pairs; the
  /// empty value means no filter (all movements).
  List<(String, String)> _movementFilterOptions(AppLocalizations l10n) => [
    ('', l10n.stockmovementsFilterall),
    ('PURCHASE', l10n.stockmovementsFilterpurchase),
    ('SALE', l10n.stockmovementsFiltersale),
    ('TRANSFER', l10n.stockmovementsFiltertransfer),
    ('PRODUCTION', l10n.stockmovementsFilterproduction),
    ('ADJUSTMENT', l10n.stockmovementsFilteradjustment),
  ];

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
        enableContextMenu: false,
        enableFilterMenuItem: false,
        enableHideColumnMenuItem: false,
        enableSetColumnsMenuItem: false,
      ),
      textColumn('no', 'Movement No', 120),
      textColumn('date', 'Date', 120),
      textColumn('item', 'Item', 200),
      textColumn('warehouse', 'Warehouse', 160),
      PlutoColumn(
        title: 'Movement Type',
        field: 'type',
        type: PlutoColumnType.text(),
        width: 130,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) {
          final type = ctx.cell.value?.toString() ?? '';
          return Align(
            alignment: Alignment.centerLeft,
            child: StatusBadge(
              status: type,
              color: switch (type) {
                'PURCHASE' || 'PRODUCTION' => Colors.green,
                'SALE' || 'TRANSFER' => Colors.orange,
                'ADJUSTMENT' => Colors.purple,
                _ => Colors.blueGrey,
              },
            ),
          );
        },
      ),
      PlutoColumn(
        title: 'Total Quantity',
        field: 'qty',
        type: PlutoColumnType.number(format: '#,###.##'),
        width: 110,
        readOnly: true,
        textAlign: PlutoColumnTextAlign.end,
        titleTextAlign: PlutoColumnTextAlign.end,
        enableContextMenu: false,
      ),
      textColumn('ref', 'Reference', 140),
      textColumn('remarks', 'Remarks', 220),
    ];
  }
}
