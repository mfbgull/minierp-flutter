// Suppliers list screen — PORTING.md §5/§6. Server-paginated like
// customers: `GET /suppliers` returns one page plus a `pagination` block,
// so this screen drives page/limit/search/sortBy/sortOrder through the
// provider and renders a [ServerPaginationBar] under the grid. Column
// sort maps to the server's SUPPLIER_SORT_COLUMNS whitelist.
//
// Keyboard: the shared [rowDetailShortcutActions] bind F2 / Enter to open
// the focused row's detail (the same path as a double tap), and a
// [GridStatusBar] beneath the grid states those hints — the items/customers
// convention.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/supplier.dart' show Supplier;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../data/repositories/paged_request.dart' show PagedResponse;
import '../../l10n/app_localizations.dart';
import '../../widgets/grid_status_bar.dart';
import '../../widgets/pagination_bar.dart';
import '../../widgets/pluto_grid_shortcuts.dart';
import '../../widgets/screen_error_panel.dart';
import '../../widgets/status_badge.dart';
import 'supplier_detail_dialog.dart';
import 'supplier_form_dialog.dart';
import 'supplier_providers.dart';

class SuppliersScreen extends ConsumerStatefulWidget {
  const SuppliersScreen({super.key});

  @override
  ConsumerState<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends ConsumerState<SuppliersScreen> {
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
    // detail (see [rowDetailShortcutActions]). Built once — the shortcut
    // map holds a closure over this State's context, so it must not be
    // recreated after the widget is disposed.
    if (!_configurationReady) {
      _configuration = PlutoGridConfiguration(
        shortcut: PlutoGridShortcut(
          actions: rowDetailShortcutActions(_openDetail),
        ),
      );
      _configurationReady = true;
    }
  }

  void _openDetail(int supplierId) {
    if (!mounted) return;
    showSupplierDetailDialog(context, supplierId: supplierId);
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
      ref.read(suppliersSearchProvider.notifier).state = value.trim();
      // A new search starts back at page 1.
      if (ref.read(suppliersPageProvider) != 1) {
        ref.read(suppliersPageProvider.notifier).state = 1;
      }
    });
  }

  /// Grid field → server sort column (whitelist in sqlSanitizer.ts).
  String? _sortColumnFor(String field) => switch (field) {
        'code' => 'supplier_code',
        'name' => 'supplier_name',
        'email' => 'email',
        'phone' => 'phone',
        'balance' => 'current_balance',
        'active' => 'is_active', // whitelisted server sort column
        _ => null,
      };

  void _onSorted(PlutoGridOnSortedEvent event) {
    final sortBy = _sortColumnFor(event.column.field);
    if (sortBy == null) return;
    final sort = event.column.sort;
    ref.read(suppliersSortProvider.notifier).state = sort.isNone
        ? null
        : SupplierSort(
            sortBy,
            sort == PlutoColumnSort.ascending ? 'ASC' : 'DESC',
          );
    if (ref.read(suppliersPageProvider) != 1) {
      ref.read(suppliersPageProvider.notifier).state = 1;
    }
  }

  void _applyPage(AsyncValue<PagedResponse<Supplier>> value) {
    final manager = _stateManager;
    if (manager == null) return;
    manager.setShowLoading(value.isLoading);
    if (value.hasValue) {
      manager.removeAllRows();
      manager.appendRows([
        for (final supplier in value.value?.items ?? const <Supplier>[])
          _rowFor(supplier),
      ]);
    }
  }

  static PlutoRow _rowFor(Supplier supplier) => PlutoRow(cells: {
        'id': PlutoCell(value: supplier.id),
        'code': PlutoCell(value: supplier.supplierCode),
        'name': PlutoCell(value: supplier.supplierName),
        'phone': PlutoCell(value: supplier.phone ?? ''),
        'email': PlutoCell(value: supplier.email ?? ''),
        'balance': PlutoCell(value: supplier.currentBalance ?? 0),
        'active': PlutoCell(value: supplier.isActive),
      });

  @override
  Widget build(BuildContext context) {
    final suppliers = ref.watch(suppliersProvider);
    final l10n = AppLocalizations.of(context)!;
    final page = suppliers.valueOrNull;

    ref.listen(suppliersProvider, (previous, next) => _applyPage(next));

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
                                  // Cancel any pending debounce so a stale
                                  // timer can't resurrect the old term.
                                  _debounce?.cancel();
                                  _searchController.clear();
                                  ref
                                      .read(suppliersSearchProvider.notifier)
                                      .state = '';
                                  if (ref.read(suppliersPageProvider) != 1) {
                                    ref
                                        .read(suppliersPageProvider.notifier)
                                        .state = 1;
                                  }
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
                onPressed: () => showSupplierFormDialog(context),
                icon: const Icon(Icons.add, size: 18),
                label: Text(l10n.suppliersNewsupplier),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: l10n.commonRefresh,
                icon: const Icon(Icons.refresh),
                onPressed: () => ref.invalidate(suppliersProvider),
              ),
            ],
          ),
        ),
        Expanded(child: _buildBody(suppliers)),
        if (page != null)
          ServerPaginationBar(
            page: page.currentPage,
            totalPages: page.totalPages,
            totalItems: page.totalItems,
            hasNext: page.hasNext,
            hasPrev: page.hasPrev,
            limit: ref.watch(suppliersLimitProvider),
            itemLabel: l10n.suppliersSuppliers,
            onPageChanged: (p) =>
                ref.read(suppliersPageProvider.notifier).state = p,
            onLimitChanged: (limit) {
              ref.read(suppliersLimitProvider.notifier).state = limit;
              if (ref.read(suppliersPageProvider) != 1) {
                ref.read(suppliersPageProvider.notifier).state = 1;
              }
            },
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildBody(AsyncValue<PagedResponse<Supplier>> suppliers) {
    final errorMessage = switch (suppliers) {
      AsyncError(:final error) => error is ApiError ? error.message : null,
      _ => null,
    };
    if (errorMessage != null) {
      _stateManager = null;
      return ScreenErrorPanel(
        message: errorMessage,
        onRetry: () => ref.invalidate(suppliersProvider),
      );
    }
    return _grid();
  }

  Widget _grid() {
    final l10n = AppLocalizations.of(context)!;
    // The keyboard-hint status bar sits flush under the grid (items
    // convention); the pagination bar renders below the whole body.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: PlutoGrid(
              columns: _columns,
              configuration: _configuration,
              // Growable — PlutoGrid's FilteredList appends to the list.
              rows: <PlutoRow>[],
              onLoaded: (event) {
                _stateManager = event.stateManager;
                _stateManager?.hideColumn(
                  _columns.firstWhere((c) => c.field == 'id'),
                  true,
                  notify: false,
                );
                _applyPage(ref.read(suppliersProvider));
              },
              onSorted: _onSorted,
              onRowDoubleTap: (event) {
                final id = (event.row.cells['id']?.value as num?)?.toInt();
                if (id == null || id <= 0) return;
                showSupplierDetailDialog(context, supplierId: id);
              },
              noRowsWidget: Center(
                child: Text(
                  l10n.commonNoresults,
                  style: TextStyle(color: Theme.of(context).colorScheme.outline),
                ),
              ),
            ),
          ),
        ),
        const GridStatusBar(),
      ],
    );
  }

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
      textColumn('code', l10n.suppliersSuppliercode, 120),
      textColumn('name', l10n.suppliersSuppliername, 220),
      textColumn('phone', l10n.suppliersPhone, 130),
      textColumn('email', l10n.suppliersEmail, 190),
      PlutoColumn(
        title: l10n.suppliersBalance,
        field: 'balance',
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
