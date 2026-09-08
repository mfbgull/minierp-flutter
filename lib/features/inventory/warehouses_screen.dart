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
import '../../core/theme/status_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/auth/auth_notifier.dart' show authProvider;
import '../../core/utils/csv_export.dart';
import '../../data/models/warehouse.dart' show Warehouse;
import '../../data/repositories/inventory_repository.dart' show inventoryRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/bulk_operations.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/pluto_grid_screen.dart';
import '../../widgets/screen_toolbar.dart';
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
  bool _bulkBusy = false;

  Map<int, Warehouse> get _warehousesById => {
    for (final w in ref.read(warehousesProvider).valueOrNull ?? const <Warehouse>[])
      w.id: w,
  };

  @override
  bool get enableBulkSelection => true;

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

  /// Bulk soft-delete of selected warehouses (no undo until D25 extends
  /// PUT with `is_active`).
  Future<void> _bulkDelete(Set<int> ids) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.commonDelete,
      message: '${l10n.bulkDeleteSelected} (${ids.length})?',
      confirmLabel: l10n.commonDelete,
      cancelLabel: l10n.commonCancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    final repo = ref.read(inventoryRepositoryProvider);
    setState(() => _bulkBusy = true);
    final result = await runBulkOperation(
      ids: ids.toList(),
      labelFor: (id) => _warehousesById[id]?.warehouseCode ?? '#$id',
      operation: repo.deleteWarehouse,
    );
    if (!mounted) return;
    setState(() => _bulkBusy = false);
    await finishBulkOperation(
      context,
      bulk: bulkSelection,
      result: result,
      successMessage: l10n.bulkDeleted,
      onComplete: () => ref.invalidate(warehousesProvider),
    );
  }

  void _bulkExport(Set<int> ids) {
    final l10n = AppLocalizations.of(context)!;
    final selected = [
      for (final w in _warehousesById.values)
        if (ids.contains(w.id)) w,
    ];
    if (selected.isEmpty) return;
    saveCsv(
      context,
      suggestedName: csvSuggestedName('warehouses'),
      csv: buildWarehousesCsv(l10n, selected),
      successMessage: l10n.bulkExportSelected,
      errorMessage: l10n.bulkDeleteFailed,
    );
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

  /// Opt into the per-row ⋮ actions menu (Edit).
  @override
  bool get hasRowActions => true;

  @override
  List<GridRowAction>? gridRowActionsFor(PlutoRow row, BuildContext context) {
    final warehouse = _firstWhereOrNull(_filtered, (w) => w.id == row.cells['id']?.value);
    if (warehouse == null) return null;
    final l10n = AppLocalizations.of(context)!;
    return [
      GridRowAction(
        icon: Icons.edit_outlined,
        label: l10n.commonEdit,
        onTap: () => _openForm(warehouse),
      ),
    ];
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
        ScreenToolbar(
          searchController: _searchController,
          searchHint: l10n.commonSearch,
          onSearchChanged: _onSearchChanged,
          onClearSearch: () {
            _debounce?.cancel();
            _searchController.clear();
            ref.read(warehouseSearchProvider.notifier).state = '';
          },
          onRefresh: () => ref.invalidate(warehousesProvider),
          primaryActions: [
            FilledButton.tonalIcon(
              onPressed: () => _openForm(null),
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.warehousesNewwarehouse),
            ),
          ],
        ),
        ValueListenableBuilder<Set<int>>(
          valueListenable: bulkSelection.selected,
          builder: (context, sel, _) {
            if (sel.isEmpty) return const SizedBox.shrink();
            final user = ref.watch(authProvider).user;
            return BulkActionBar(
              count: sel.length,
              onClearSelection: bulkSelection.clear,
              busy: _bulkBusy,
              actions: [
                if (user?.hasPermission('inventory', 'read') ?? false)
                  TextButton.icon(
                    onPressed: () => _bulkExport(sel),
                    icon: const Icon(Icons.file_download_outlined, size: 18),
                    label: Text(l10n.bulkExportSelected),
                  ),
                if (user?.hasPermission('inventory', 'delete') ?? false)
                  TextButton.icon(
                    onPressed: () => _bulkDelete(sel),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    label: Text(l10n.bulkDeleteSelected),
                  ),
              ],
            );
          },
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
            color: StatusColors.of(context).active(active),
          ),
        );
      },
    ),
  ];
}
