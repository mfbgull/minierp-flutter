// Items list screen — PORTING.md §5/§6: the first authenticated data
// screen. A read-only grid over `GET /inventory/items` (server-paginated,
// `search` + `low_stock` filters) rendered with PlutoGrid via the shared
// [PlutoGridScreen] mixin. Sits at the shell branch root `/inventory`
// (the web app hosts it at `/inventory/items`).
//
// The provider is the single source of truth and the screen never mutates
// rows directly; search / low-stock toggle / sorting / paging all
// refetch server-side through the paged endpoint.
//
// Low-stock highlighting: the grid's row cells carry `stock` and
// `reorder`, so both the row tint and the stock-cell renderer can decide
// without an item-lookup map.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:minierp_app/core/theme/status_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/item.dart' show Item;
import '../../data/repositories/inventory_repository.dart' show inventoryRepositoryProvider;
import '../../data/repositories/paged_request.dart' show PagedResponse;
import '../../l10n/app_localizations.dart';
import '../../widgets/pagination_bar.dart';
import '../../widgets/pluto_grid_screen.dart';
import '../../widgets/screen_toolbar.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/offline_cache_badge.dart';
import '../../widgets/confirm_dialog.dart';
import 'inventory_providers.dart';
import 'item_detail_dialog.dart';
import 'item_form_dialog.dart';

/// True when a grid row is at/below its reorder level — the single
/// low-stock rule, shared by the row tint and the stock-cell renderer.
/// `reorder_level 0` (or null) means no reorder threshold (matches the
/// server's items-low-stock rule and the live data, where 0 is common).
bool _isLowStockRow(PlutoRow row) {
  final stock = (row.cells['stock']?.value as num?) ?? 0;
  final reorder = (row.cells['reorder']?.value as num?) ?? 0;
  return reorder > 0 && stock <= reorder;
}

class ItemsScreen extends ConsumerStatefulWidget {
  const ItemsScreen({super.key});

  @override
  ConsumerState<ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends ConsumerState<ItemsScreen>
    with PlutoGridScreen<Item, ItemsScreen> {
  Timer? _debounce;
  final TextEditingController _searchController = TextEditingController();

  @override
  void openRowDetail(int itemId) {
    if (!mounted) return;
    showItemDetailDialog(context, itemId: itemId);
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
      ref.read(itemsSearchProvider.notifier).state = value.trim();
      // A new search starts back at page 1.
      if (ref.read(itemsPageProvider) != 1) {
        ref.read(itemsPageProvider.notifier).state = 1;
      }
    });
  }

  /// The items provider returns a `PagedResponse` envelope — unwrap the
  /// current page's items as the grid rows.
  @override
  Iterable<Item> gridRowsFrom(Object? value) =>
      (value as PagedResponse<Item>).items;

  /// Grid field → server sort column (whitelist in sqlSanitizer.ts).
  String? _sortColumnFor(String field) => switch (field) {
    'code' => 'item_code',
    'name' => 'item_name',
    'category' => 'category',
    'stock' => 'current_stock',
    'reorder' => 'reorder_level',
    _ => null,
  };

  /// Column sort maps to the server-side sort provider (this endpoint is
  /// server-paginated, so ordering happens on the server).
  @override
  void onGridSorted(PlutoGridOnSortedEvent event) {
    final sortBy = _sortColumnFor(event.column.field);
    if (sortBy == null) return;
    final sort = event.column.sort;
    ref.read(itemsSortProvider.notifier).state = sort.isNone
        ? null
        : GridSort(
            sortBy,
            sort == PlutoColumnSort.ascending ? 'ASC' : 'DESC',
          );
    if (ref.read(itemsPageProvider) != 1) {
      ref.read(itemsPageProvider.notifier).state = 1;
    }
  }

  /// Opt into the per-row ⋮ actions menu (View / Edit).
  @override
  bool get hasRowActions => true;

  /// Bulk selection (SHORTCOMINGS-FIX 4.4): checkbox column + select-all
  /// header, driving the bulk action bar (activate / deactivate / delete
  /// with undo). Selection resets whenever the grid rows are replaced.
  @override
  bool get enableBulkSelection => true;

  @override
  PlutoRow gridRowFor(Item item) => PlutoRow(
    cells: {
      // Hidden cell carrying the full Item so the ⋮ menu can open the
      // edit form prefilled.
      'data': PlutoCell(value: item),
      'id': PlutoCell(value: item.id),
      'code': PlutoCell(value: item.itemCode),
      'name': PlutoCell(value: item.itemName),
      'category': PlutoCell(value: item.category ?? ''),
      'unit': PlutoCell(value: item.unitOfMeasure),
      'stock': PlutoCell(value: item.currentStock),
      'reorder': PlutoCell(value: item.reorderLevel ?? 0),
      'cost': PlutoCell(value: item.standardCost ?? 0),
      'price': PlutoCell(value: item.standardSellingPrice ?? 0),
      'active': PlutoCell(value: item.isActive),
    },
  );

  @override
  List<GridRowAction>? gridRowActionsFor(PlutoRow row, BuildContext context) {
    final item = row.cells['data']?.value as Item?;
    if (item == null) return null;
    final l10n = AppLocalizations.of(context)!;
    return [
      GridRowAction(
        icon: Icons.visibility_outlined,
        label: l10n.commonView,
        onTap: () => showItemDetailDialog(context, itemId: item.id),
      ),
      GridRowAction(
        icon: Icons.edit_outlined,
        label: l10n.commonEdit,
        onTap: () => showItemFormDialog(context, item: item),
      ),
      GridRowAction(
        icon: Icons.delete_outline,
        label: l10n.commonDelete,
        onTap: () => _deleteItem(item),
      ),
    ];
  }

  /// Bulk activate/deactivate of the selected items (SHORTCOMINGS-FIX
  /// 4.4). Each item's `is_active` flag flips via the standard update
  /// endpoint; a failed item doesn't stop the rest.
  Future<void> _bulkSetActive(Set<int> ids, bool active) async {
    final l10n = AppLocalizations.of(context)!;
    final repo = ref.read(inventoryRepositoryProvider);
    var ok = 0;
    var failed = 0;
    for (final id in ids) {
      final result = await repo.update(id, {'is_active': active ? 1 : 0});
      if (!mounted) return;
      result.fold(
        onSuccess: (_) => ok++,
        onFailure: (_) => failed++,
      );
    }
    if (!mounted) return;
    bulkSelection.clear();
    if (failed == 0) {
      showAppToast(
        context,
        active ? l10n.bulkActivated(ok) : l10n.bulkDeactivated(ok),
      );
    } else {
      showAppToast(context, l10n.bulkUpdateFailed, isError: true);
    }
    ref.invalidate(itemsProvider);
  }

  /// Bulk soft-delete of the selected items with the 4.2 undo pattern —
  /// one 10s toast with a single Undo action that restores every deleted
  /// item in place.
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
    var ok = 0;
    var failed = 0;
    for (final id in ids) {
      final result = await repo.delete(id);
      if (!mounted) return;
      result.fold(
        onSuccess: (_) => ok++,
        onFailure: (_) => failed++,
      );
    }
    if (!mounted) return;
    bulkSelection.clear();
    if (failed == 0) {
      showAppToast(
        context,
        l10n.bulkDeleted(ok),
        duration: const Duration(seconds: 10),
        action: SnackBarAction(
          label: l10n.commonUndo,
          onPressed: () async {
            for (final id in ids) {
              final undo = await repo.restore(id);
              if (!mounted) return;
              undo.fold(
                onSuccess: (_) {},
                onFailure: (err) =>
                    showAppToast(context, err.message, isError: true),
              );
            }
            if (!mounted) return;
            ref.invalidate(itemsProvider);
          },
        ),
      );
    } else {
      showAppToast(context, l10n.bulkDeleteFailed, isError: true);
    }
    ref.invalidate(itemsProvider);
  }

  Future<void> _deleteItem(Item item) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.commonDelete,
      message: '${l10n.inventoryConfirmdelete} ${item.itemName}?',
      confirmLabel: l10n.commonDelete,
      cancelLabel: l10n.commonCancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    final result = await ref
        .read(inventoryRepositoryProvider)
        .delete(item.id);
    if (!mounted) return;
    result.fold(
      onSuccess: (_) {
        // 10s window + Undo (SHORTCOMINGS-FIX 4.2) — the delete is a
        // soft delete server-side, so restore() reverts it in place.
        showAppToast(
          context,
          l10n.inventoryItemdeleted,
          duration: const Duration(seconds: 10),
          action: SnackBarAction(
            label: l10n.commonUndo,
            onPressed: () async {
              final undo = await ref
                  .read(inventoryRepositoryProvider)
                  .restore(item.id);
              if (!mounted) return;
              undo.fold(
                onSuccess: (_) => ref.invalidate(itemsProvider),
                onFailure: (err) =>
                    showAppToast(context, err.message, isError: true),
              );
            },
          ),
        );
        ref.invalidate(itemsProvider);
      },
      onFailure: (err) => showAppToast(context, err.message, isError: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(itemsProvider);
    final lowStockOnly = ref.watch(itemsLowStockOnlyProvider);
    final page = items.valueOrNull;
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    // Keep the grid in sync with provider transitions (loading → data).
    watchGridProvider(itemsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScreenToolbar(
          searchController: _searchController,
          searchHint: l10n.commonSearch,
          onSearchChanged: _onSearchChanged,
          filters: [
            FilterChip(
              label: Text(l10n.inventoryLowstock),
              selected: lowStockOnly,
              // Setting the state re-runs itemsProvider automatically
              // (it watches the toggle) — no manual invalidate needed.
              onSelected: (selected) {
                ref.read(itemsLowStockOnlyProvider.notifier).state =
                    selected;
                // A new filter starts back at page 1.
                if (ref.read(itemsPageProvider) != 1) {
                  ref.read(itemsPageProvider.notifier).state = 1;
                }
              },
            ),
          ],
          onRefresh: () => ref.invalidate(itemsProvider),
          actions: [const OfflineCacheBadge()],
          primaryActions: [
            FilledButton.tonalIcon(
              onPressed: () => showItemFormDialog(context),
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.inventoryNewitem),
            ),
          ],
        ),
        // Bulk action bar (checkbox rows selected) — activate /
        // deactivate / delete-with-undo the selected items
        // (SHORTCOMINGS-FIX 4.4).
        ValueListenableBuilder<Set<int>>(
          valueListenable: bulkSelection.selected,
          builder: (context, sel, _) {
            if (sel.isEmpty) return const SizedBox.shrink();
            return BulkActionBar(
              count: sel.length,
              onClearSelection: bulkSelection.clear,
              actions: [
                TextButton.icon(
                  onPressed: () => _bulkSetActive(sel, true),
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: Text(l10n.bulkActivateSelected),
                ),
                TextButton.icon(
                  onPressed: () => _bulkSetActive(sel, false),
                  icon: const Icon(Icons.cancel_outlined, size: 18),
                  label: Text(l10n.bulkDeactivateSelected),
                ),
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
          child: gridScreenBody(
            items,
            provider: itemsProvider,
            rowColorCallback: (context) => _isLowStockRow(context.row)
                ? scheme.error.withValues(alpha: 0.07)
                : Colors.transparent,
          ),
        ),
        if (page != null)
          ServerPaginationBar(
            page: page.currentPage,
            totalPages: page.totalPages,
            totalItems: page.totalItems,
            hasNext: page.hasNext,
            hasPrev: page.hasPrev,
            limit: ref.watch(itemsLimitProvider),
            itemLabel: l10n.inventoryItems,
            onPageChanged: (p) =>
                ref.read(itemsPageProvider.notifier).state = p,
            onLimitChanged: (limit) {
              ref.read(itemsLimitProvider.notifier).state = limit;
              if (ref.read(itemsPageProvider) != 1) {
                ref.read(itemsPageProvider.notifier).state = 1;
              }
            },
          ),
      ],
    );
  }

  /// Column set — order/format mirrors the web grid conventions in
  /// PORTING.md §6; read-only for now (create/edit comes with the form).
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

    PlutoColumn numberColumn(String field, String title, double width) =>
        PlutoColumn(
          title: title,
          field: field,
          type: PlutoColumnType.number(format: '#,###.##'),
          width: width,
          readOnly: true,
          textAlign: PlutoColumnTextAlign.end,
          titleTextAlign: PlutoColumnTextAlign.end,
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
      textColumn('code', l10n.inventoryItemcode, 120),
      textColumn('name', l10n.inventoryItemname, 240),
      textColumn('category', l10n.commonCategory, 130),
      textColumn('unit', l10n.fieldsUnit, 90),
      PlutoColumn(
        title: l10n.inventoryCurrentstock,
        field: 'stock',
        type: PlutoColumnType.number(format: '#,###.##'),
        width: 110,
        readOnly: true,
        textAlign: PlutoColumnTextAlign.end,
        titleTextAlign: PlutoColumnTextAlign.end,
        enableContextMenu: false,
        // Low-stock cell: red + bold. Reads stock/reorder straight from the
        // row's cells so it stays correct after client-side sorting.
        renderer: (ctx) => Builder(
          builder: (cellContext) {
            final scheme = Theme.of(cellContext).colorScheme;
            final stock = (ctx.cell.value as num?) ?? 0;
            final low = _isLowStockRow(ctx.row);
            return Align(
              alignment: Alignment.centerRight,
              child: Text(
                Formatters.number(stock),
                style: TextStyle(
                  color: low ? scheme.error : null,
                  fontWeight: low ? FontWeight.w700 : null,
                ),
              ),
            );
          },
        ),
      ),
      numberColumn('reorder', l10n.inventoryReorderlevel, 110),
      PlutoColumn(
        title: l10n.inventoryStandardcost,
        field: 'cost',
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
      PlutoColumn(
        title: l10n.inventorySellingprice,
        field: 'price',
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
}
