// Physical counts list screen — PORTING.md §6. Read-only grid over
// `GET /inventory/physical-counts` (server-paginated, `search` filter)
// rendered with PlutoGrid via the shared [PlutoGridScreen] mixin.
// Double-tap/F2 opens the count's detail dialog (header + counted item
// lines); the grid row's hidden `id` cell carries the count id. Search /
// sorting / paging all refetch server-side through the paged endpoint.

import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/theme/status_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/auth/auth_notifier.dart' show authProvider;
import '../../core/utils/csv_export.dart';
import '../../data/models/physical_count.dart' show PhysicalCount;
import '../../data/repositories/inventory_repository.dart' show inventoryRepositoryProvider;
import '../../data/repositories/paged_request.dart' show PagedResponse;
import '../../l10n/app_localizations.dart';
import '../../widgets/bulk_operations.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/pagination_bar.dart';
import '../../widgets/pluto_grid_screen.dart';
import '../../widgets/screen_toolbar.dart';
import '../../widgets/status_badge.dart';
import 'inventory_providers.dart'
    show
        GridSort,
        physicalCountsLimitProvider,
        physicalCountsPageProvider,
        physicalCountsProvider,
        physicalCountsSearchProvider,
        physicalCountsSortProvider;
import 'new_physical_count_dialog.dart';
import 'physical_count_detail_dialog.dart';

class PhysicalCountScreen extends ConsumerStatefulWidget {
  const PhysicalCountScreen({super.key});

  @override
  ConsumerState<PhysicalCountScreen> createState() =>
      _PhysicalCountScreenState();
}

class _PhysicalCountScreenState extends ConsumerState<PhysicalCountScreen>
    with PlutoGridScreen<PhysicalCount, PhysicalCountScreen> {
  Timer? _debounce;
  final TextEditingController _searchController = TextEditingController();
  bool _bulkBusy = false;

  Map<int, PhysicalCount> get _physicalCountsById => {
    for (final c
        in ref.read(physicalCountsProvider).valueOrNull?.items ??
            const <PhysicalCount>[])
      c.id: c,
  };

  @override
  bool get enableBulkSelection => true;

  @override
  String get filterSignature {
    final search = ref.read(physicalCountsSearchProvider);
    return search;
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
      ref.read(physicalCountsSearchProvider.notifier).state = value.trim();
      // A new search starts back at page 1.
      if (ref.read(physicalCountsPageProvider) != 1) {
        ref.read(physicalCountsPageProvider.notifier).state = 1;
      }
    });
  }

  /// Bulk hard-delete of selected physical counts (server guards:
  /// Draft/Cancelled only).
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
      labelFor: (id) => _physicalCountsById[id]?.countNo ?? '#$id',
      operation: repo.deletePhysicalCount,
    );
    if (!mounted) return;
    setState(() => _bulkBusy = false);
    await finishBulkOperation(
      context,
      bulk: bulkSelection,
      result: result,
      successMessage: l10n.bulkDeleted,
      onComplete: () => ref.invalidate(physicalCountsProvider),
    );
  }

  void _bulkExport(Set<int> ids) {
    final l10n = AppLocalizations.of(context)!;
    final selected = [
      for (final c in _physicalCountsById.values)
        if (ids.contains(c.id)) c,
    ];
    if (selected.isEmpty) return;
    saveCsv(
      context,
      suggestedName: csvSuggestedName('physical-counts'),
      csv: buildPhysicalCountsCsv(l10n, selected),
      successMessage: l10n.bulkExportSelected,
      errorMessage: l10n.bulkDeleteFailed,
    );
  }

  /// The physical-counts provider returns a `PagedResponse` envelope —
  /// unwrap the current page's items as the grid rows.
  @override
  Iterable<PhysicalCount> gridRowsFrom(Object? value) =>
      (value as PagedResponse<PhysicalCount>).items;

  /// Grid field → server sort column (whitelist in sqlSanitizer.ts).
  String? _sortColumnFor(String field) => switch (field) {
    'countNo' => 'count_no',
    'date' => 'count_date',
    'warehouse' => 'warehouse_name',
    'status' => 'status',
    _ => null,
  };

  /// Column sort maps to the server-side sort provider (this endpoint is
  /// server-paginated, so ordering happens on the server).
  @override
  void onGridSorted(PlutoGridOnSortedEvent event) {
    final sortBy = _sortColumnFor(event.column.field);
    if (sortBy == null) return;
    final sort = event.column.sort;
    ref.read(physicalCountsSortProvider.notifier).state = sort.isNone
        ? null
        : GridSort(
            sortBy,
            sort == PlutoColumnSort.ascending ? 'ASC' : 'DESC',
          );
    if (ref.read(physicalCountsPageProvider) != 1) {
      ref.read(physicalCountsPageProvider.notifier).state = 1;
    }
  }

  @override
  void openRowDetail(int rowId) {
    if (!mounted) return;
    showPhysicalCountDetailDialog(context, countId: rowId);
  }

  /// Opt into the per-row ⋮ actions menu (View detail).
  @override
  bool get hasRowActions => true;

  @override
  List<GridRowAction>? gridRowActionsFor(PlutoRow row, BuildContext context) {
    final id = row.cells['id']?.value as int?;
    if (id == null || id <= 0) return null;
    final l10n = AppLocalizations.of(context)!;
    return [
      GridRowAction(
        icon: Icons.visibility_outlined,
        label: l10n.commonView,
        onTap: () => showPhysicalCountDetailDialog(context, countId: id),
      ),
    ];
  }

  @override
  PlutoRow gridRowFor(PhysicalCount c) => PlutoRow(
    cells: {
      'id': PlutoCell(value: c.id),
      'countNo': PlutoCell(value: c.countNo),
      'date': PlutoCell(value: c.countDate),
      'warehouse': PlutoCell(value: c.warehouseName ?? ''),
      'status': PlutoCell(value: c.status),
      'items': PlutoCell(value: c.totalItems ?? 0),
      'counted': PlutoCell(value: c.countedItems ?? 0),
      'variance': PlutoCell(value: c.varianceItems ?? 0),
    },
  );

  Color _statusColor(String status, ColorScheme scheme) => StatusColors(scheme).physicalCount(status);

  @override
  Widget build(BuildContext context) {
    final counts = ref.watch(physicalCountsProvider);
    final page = counts.valueOrNull;
    final l10n = AppLocalizations.of(context)!;

    // Keep the grid in sync with provider transitions (loading → data).
    // Search refetches server-side through the paged provider (it
    // watches the search provider), so no client-side refilter is needed.
    watchGridProvider(physicalCountsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Toolbar: server-side search (count no / warehouse / status) +
        // refresh.
        ScreenToolbar(
          searchController: _searchController,
          searchHint: l10n.commonSearch,
          onSearchChanged: _onSearchChanged,
          onRefresh: () => ref.invalidate(physicalCountsProvider),
          primaryActions: [
            FilledButton.icon(
              onPressed: () async {
                await showNewPhysicalCountDialog(context);
                if (mounted) {
                  ref.invalidate(physicalCountsProvider);
                }
              },
              icon: const Icon(Icons.add_outlined, size: 18),
              label: const Text('New Count'),
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
          child: gridScreenBody(counts, provider: physicalCountsProvider),
        ),
        if (page != null)
          ServerPaginationBar(
            page: page.currentPage,
            totalPages: page.totalPages,
            totalItems: page.totalItems,
            hasNext: page.hasNext,
            hasPrev: page.hasPrev,
            limit: ref.watch(physicalCountsLimitProvider),
            itemLabel: l10n.physicalcountsPhysicalcounts,
            onPageChanged: (p) =>
                ref.read(physicalCountsPageProvider.notifier).state = p,
            onLimitChanged: (limit) {
              ref.read(physicalCountsLimitProvider.notifier).state = limit;
              if (ref.read(physicalCountsPageProvider) != 1) {
                ref.read(physicalCountsPageProvider.notifier).state = 1;
              }
            },
          ),
      ],
    );
  }

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
      textColumn('countNo', 'Count No', 140),
      textColumn('date', 'Date', 120),
      textColumn('warehouse', 'Warehouse', 180),
      PlutoColumn(
        title: 'Status',
        field: 'status',
        type: PlutoColumnType.text(),
        width: 130,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) {
          final status = ctx.cell.value?.toString() ?? '';
          return Align(
            alignment: Alignment.centerLeft,
            child: Builder(
              builder: (context) {
                final scheme = Theme.of(context).colorScheme;
                return StatusBadge(
                  status: status,
                  color: _statusColor(status, scheme),
                );
              },
            ),
          );
        },
      ),
      PlutoColumn(
        title: 'Total Items',
        field: 'items',
        type: PlutoColumnType.number(format: '#,###'),
        width: 110,
        readOnly: true,
        textAlign: PlutoColumnTextAlign.end,
        titleTextAlign: PlutoColumnTextAlign.end,
        enableContextMenu: false,
      ),
      PlutoColumn(
        title: 'Counted',
        field: 'counted',
        type: PlutoColumnType.number(format: '#,###'),
        width: 110,
        readOnly: true,
        textAlign: PlutoColumnTextAlign.end,
        titleTextAlign: PlutoColumnTextAlign.end,
        enableContextMenu: false,
      ),
      PlutoColumn(
        title: 'Variance',
        field: 'variance',
        type: PlutoColumnType.number(format: '#,###'),
        width: 110,
        readOnly: true,
        textAlign: PlutoColumnTextAlign.end,
        titleTextAlign: PlutoColumnTextAlign.end,
        enableContextMenu: false,
      ),
    ];
  }
}
