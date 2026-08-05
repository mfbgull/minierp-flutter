// Items list screen — PORTING.md §5/§6: the first authenticated data
// screen. A read-only grid over `GET /inventory/items` (enveloped array,
// server-side `search` + flag filters) rendered with PlutoGrid — the
// AG-Grid replacement for this project. Sits at the shell branch root
// `/inventory` (the web app hosts it at `/inventory/items`).
//
// Grid state: PlutoGrid keeps its own `PlutoGridStateManager`, so rows
// are fed through the manager (clear + append) on provider changes rather
// than by rebuilding the widget; the provider is the single source of
// truth and the screen never mutates rows directly. Sorting/filtering
// stay client-side because the items endpoint returns the full list.
//
// Low-stock highlighting: the grid's row cells carry `stock` and
// `reorder`, so both the row tint and the stock-cell renderer can decide
// without an item-lookup map — this survives client-side re-sorting.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/item.dart' show Item;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/grid_status_bar.dart';
import '../../widgets/pluto_grid_shortcuts.dart';
import '../../widgets/screen_error_panel.dart';
import '../../widgets/status_badge.dart';
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

class _ItemsScreenState extends ConsumerState<ItemsScreen> {
  Timer? _debounce;
  final TextEditingController _searchController = TextEditingController();
  PlutoGridStateManager? _stateManager;
  late List<PlutoColumn> _columns;
  bool _columnsReady = false;
  PlutoGridConfiguration _configuration = const PlutoGridConfiguration();
  bool _configurationReady = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Column titles are localized — build them once here (lookups of
    // inherited widgets are not allowed before initState completes).
    if (!_columnsReady) {
      _columns = _buildColumns(AppLocalizations.of(context)!);
      _columnsReady = true;
    }
    // Same for the grid configuration: F2/Enter open the focused row's
    // detail (see _OpenDetailAction). Built once — the shortcut map holds
    // a closure over this State's context, so it must not be recreated
    // after the widget is disposed (the same instance is passed on every
    // rebuild, and PlutoGrid re-applies it without re-running actions).
    if (!_configurationReady) {
      _configuration = PlutoGridConfiguration(
        shortcut: PlutoGridShortcut(
          actions: rowDetailShortcutActions(_openDetail),
        ),
      );
      _configurationReady = true;
    }
  }

  void _openDetail(int itemId) {
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
    });
  }

  /// Pushes the provider state into the grid manager (clear + append, with
  /// the loading overlay toggled). No-op until the grid reports `onLoaded`.
  void _applyItems(AsyncValue<List<Item>> value) {
    final manager = _stateManager;
    if (manager == null) return;
    manager.setShowLoading(value.isLoading);
    if (value.hasValue) {
      manager.removeAllRows();
      manager.appendRows([
        for (final item in value.value ?? const <Item>[]) _rowFor(item),
      ]);
    }
  }

  static PlutoRow _rowFor(Item item) => PlutoRow(cells: {
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
      });

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(itemsProvider);
    final lowStockOnly = ref.watch(itemsLowStockOnlyProvider);
    final l10n = AppLocalizations.of(context)!;

    // Keep the grid in sync with provider transitions (loading → data).
    ref.listen(itemsProvider, (previous, next) => _applyItems(next));

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
                      // The low-stock endpoint has no search param — the
                      // field is disabled (and visually dimmed) while it's
                      // active instead of silently dropping the term.
                      enabled: !lowStockOnly,
                      decoration: InputDecoration(
                        hintText: l10n.commonSearch,
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: value.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  // Cancel any pending debounce so a stale
                                  // timer can't resurrect the old term.
                                  _debounce?.cancel();
                                  _searchController.clear();
                                  ref
                                      .read(itemsSearchProvider.notifier)
                                      .state = '';
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
                onPressed: () => showItemFormDialog(context),
                icon: const Icon(Icons.add, size: 18),
                label: Text(l10n.inventoryNewitem),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: Text(l10n.inventoryLowstock),
                selected: lowStockOnly,
                // Setting the state re-runs itemsProvider automatically
                // (it watches the toggle) — no manual invalidate needed.
                onSelected: (selected) =>
                    ref.read(itemsLowStockOnlyProvider.notifier).state =
                        selected,
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: l10n.commonRefresh,
                icon: const Icon(Icons.refresh),
                onPressed: () => ref.invalidate(itemsProvider),
              ),
            ],
          ),
        ),
        Expanded(child: _buildBody(items)),
      ],
    );
  }

  Widget _buildBody(AsyncValue<List<Item>> items) {
    final errorMessage = switch (items) {
      AsyncError(:final error) => error is ApiError ? error.message : null,
      _ => null,
    };
    if (errorMessage != null) {
      // The grid unmounts below — drop the manager handle so a later
      // listener callback (e.g. the loading tick of a retry) never touches
      // the disposed PlutoGridStateManager.
      _stateManager = null;
      return ScreenErrorPanel(
        message: errorMessage,
        onRetry: () => ref.invalidate(itemsProvider),
      );
    }
    // Data and loading (including first load) both render the grid; the
    // loading overlay is driven through the grid manager in `_applyItems`.
    return _grid();
  }

  Widget _grid() {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    // The grid fills the space; the keyboard-hint status bar sits beneath
    // it (attached via its top border), exactly where AG-Grid draws its
    // status bar. The bar renders only with the grid — the error panel
    // path in _buildBody returns before this.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: PlutoGrid(
              columns: _columns,
              configuration: _configuration,
              // NOTE: must be a *growable* list — PlutoGrid's FilteredList
              // wraps the passed rows and appends to it (a `const []` would
              // be an unmodifiable list and crash on the first appendRows).
              rows: <PlutoRow>[],
              onLoaded: (event) {
                _stateManager = event.stateManager;
                // The id column exists only to carry the row's item id to
                // the double-tap handler — hide it (cells stay readable via
                // `row.cells['id']`, so it survives client-side sorting).
                _stateManager?.hideColumn(
                  _columns.firstWhere((c) => c.field == 'id'),
                  true,
                  notify: false,
                );
                // Sync any provider state that changed before the grid
                // finished mounting (e.g. the first loading flag).
                _applyItems(ref.read(itemsProvider));
              },
              onRowDoubleTap: (event) {
                final id = (event.row.cells['id']?.value as num?)?.toInt();
                if (id == null || id <= 0) return;
                showItemDetailDialog(context, itemId: id);
              },
              noRowsWidget: Center(
                child: Text(
                  l10n.commonNoresults,
                  style: TextStyle(color: scheme.outline),
                ),
              ),
              rowColorCallback: (context) => _isLowStockRow(context.row)
                  ? scheme.error.withValues(alpha: 0.07)
                  : Colors.transparent,
            ),
          ),
        ),
        const GridStatusBar(),
      ],
    );
  }

  /// Column set — order/format mirrors the web grid conventions in
  /// PORTING.md §6; read-only for now (create/edit comes with the form).
  static List<PlutoColumn> _buildColumns(AppLocalizations l10n) {
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
              color: active ? Colors.green : Colors.blueGrey,
            ),
          );
        },
      ),
    ];
  }
}

/// Full-pane error state with a retry (matches the dashboard's pattern) —
/// shown only when the provider fails, so the grid never renders stale
/// rows after an error.
