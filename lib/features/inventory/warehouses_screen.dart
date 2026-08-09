// Warehouses list screen — PORTING.md §6. Read-only grid over
// `GET /inventory/warehouses` (enveloped array) rendered with PlutoGrid
// via the shared [PlutoGridScreen] mixin. Double-tap/F2 opens the
// warehouse edit form; the grid row's hidden `id` cell carries the id.
//
// Search is client-side: the server list endpoint has no search param, so
// the debounced term drives the derived [warehousesSearchFilteredProvider]
// (which re-applies grid rows without refetching).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../data/models/warehouse.dart' show Warehouse;
import '../../l10n/app_localizations.dart';
import '../../widgets/pluto_grid_screen.dart';
import '../../widgets/status_badge.dart';
import 'inventory_providers.dart'
    show
        warehouseSearchProvider,
        warehousesProvider,
        warehousesSearchFilteredProvider;
import 'warehouse_form_dialog.dart';

class WarehousesScreen extends ConsumerStatefulWidget {
  const WarehousesScreen({super.key});

  @override
  ConsumerState<WarehousesScreen> createState() => _WarehousesScreenState();
}

class _WarehousesScreenState extends ConsumerState<WarehousesScreen>
    with PlutoGridScreen<Warehouse, WarehousesScreen> {
  Timer? _debounce;
  final TextEditingController _searchController = TextEditingController();
  List<Warehouse> _filtered = const [];

  T? _firstWhereOrNull<T>(Iterable<T> items, bool Function(T) test) {
    for (final item in items) {
      if (test(item)) return item;
    }
    return null;
  }

  @override
  void openRowDetail(int rowId) {
    final warehouse = _firstWhereOrNull(_filtered, (w) => w.id == rowId);
    if (warehouse == null) return;
    _openForm(warehouse);
  }

  Future<void> _openForm(Warehouse? warehouse) async {
    if (!mounted) return;
    final saved = await showWarehouseFormDialog(context, warehouse: warehouse);
    if (saved == true && mounted) {
      ref.invalidate(warehousesProvider);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      ref.read(warehouseSearchProvider.notifier).state = value.trim();
    });
  }

  @override
  PlutoRow gridRowFor(Warehouse w) => PlutoRow(
    cells: {
      'id': PlutoCell(value: w.id),
      'code': PlutoCell(value: w.warehouseCode),
      'name': PlutoCell(value: w.warehouseName ?? ''),
      'location': PlutoCell(value: w.location ?? ''),
      'items': PlutoCell(value: w.totalItems),
      'unique': PlutoCell(value: w.uniqueItems),
      'active': PlutoCell(value: w.isActive),
    },
  );

  @override
  Widget build(BuildContext context) {
    final warehouses = ref.watch(warehousesProvider);
    _filtered = ref.watch(warehousesSearchFilteredProvider);
    final l10n = AppLocalizations.of(context)!;

    // Source-provider sync: loading overlay + initial/refresh rows.
    watchGridProvider(warehousesProvider);

    // Search re-applies rows from the derived filtered provider (the
    // source provider is unchanged, so the mixin's listener doesn't fire).
    // Rows still need the `serial` cell — the grid carries the shared
    // `#` column, and PlutoGrid requires a cell per column per row.
    ref.listen(warehousesSearchFilteredProvider, (previous, next) {
      final manager = gridStateManager;
      if (manager == null) return;
      manager.removeAllRows();
      manager.appendRows([
        for (final (index, w) in next.indexed)
          withSerialCell(gridRowFor(w), index),
      ]);
    });

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
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _searchController,
                    builder: (context, value, _) => TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      decoration: InputDecoration(
                        hintText: l10n.commonSearch,
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: value.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _debounce?.cancel();
                                  _searchController.clear();
                                  ref
                                          .read(
                                            warehouseSearchProvider.notifier,
                                          )
                                          .state =
                                      '';
                                },
                              ),
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: () => _openForm(null),
                icon: const Icon(Icons.add, size: 18),
                label: Text(l10n.warehousesNewwarehouse),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: l10n.commonRefresh,
                icon: const Icon(Icons.refresh),
                onPressed: () => ref.invalidate(warehousesProvider),
              ),
            ],
          ),
        ),
        Expanded(
          child: gridScreenBody(warehouses, provider: warehousesProvider),
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
      title: 'Code',
      field: 'code',
      type: PlutoColumnType.text(),
      width: 140,
      readOnly: true,
      enableContextMenu: false,
    ),
    PlutoColumn(
      title: 'Name',
      field: 'name',
      type: PlutoColumnType.text(),
      width: 240,
      readOnly: true,
      enableContextMenu: false,
    ),
    PlutoColumn(
      title: 'Location',
      field: 'location',
      type: PlutoColumnType.text(),
      width: 220,
      readOnly: true,
      enableContextMenu: false,
    ),
    PlutoColumn(
      title: 'Total Items',
      field: 'items',
      type: PlutoColumnType.number(format: '#,###.##'),
      width: 120,
      readOnly: true,
      textAlign: PlutoColumnTextAlign.end,
      titleTextAlign: PlutoColumnTextAlign.end,
      enableContextMenu: false,
    ),
    PlutoColumn(
      title: 'Unique Items',
      field: 'unique',
      type: PlutoColumnType.number(format: '#,###.##'),
      width: 120,
      readOnly: true,
      textAlign: PlutoColumnTextAlign.end,
      titleTextAlign: PlutoColumnTextAlign.end,
      enableContextMenu: false,
    ),
    PlutoColumn(
      title: l10n.commonStatus,
      field: 'active',
      type: PlutoColumnType.text(),
      width: 110,
      readOnly: true,
      enableContextMenu: false,
      renderer: (ctx) {
        final active = ctx.cell.value == true;
        return Align(
          alignment: Alignment.centerLeft,
          child: StatusBadge(
            status: active ? l10n.statusActive : l10n.statusInactive,
            color: active ? Colors.green : Colors.blueGrey,
          ),
        );
      },
    ),
  ];
}
