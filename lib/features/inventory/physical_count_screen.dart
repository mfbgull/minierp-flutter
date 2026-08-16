// Physical counts list screen — PORTING.md §6. Read-only grid over
// `GET /inventory/physical-counts` (enveloped array) rendered with
// PlutoGrid via the shared [PlutoGridScreen] mixin. Double-tap/F2 opens
// the count's detail dialog (header + counted item lines); the grid row's
// hidden `id` cell carries the count id.
//
// The search field is disabled: the counts endpoint has no search param,
// so there is nothing honest to filter against.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../data/models/physical_count.dart' show PhysicalCount;
import '../../l10n/app_localizations.dart';
import '../../widgets/pluto_grid_screen.dart';
import '../../widgets/screen_toolbar.dart';
import '../../widgets/status_badge.dart';
import 'inventory_providers.dart'
    show physicalCountsProvider, physicalCountsSearchProvider;
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
    });
  }

  /// Client-side search over the loaded rows (the endpoint has no search
  /// param) — overrides the mixin's unfiltered clear+append.
  List<PhysicalCount> _filteredRows(List<PhysicalCount> counts) {
    final search = ref.read(physicalCountsSearchProvider).toLowerCase();
    if (search.isEmpty) return counts;
    return counts
        .where(
          (c) =>
              c.countNo.toLowerCase().contains(search) ||
              (c.warehouseName?.toLowerCase().contains(search) ?? false) ||
              c.status.toLowerCase().contains(search),
        )
        .toList();
  }

  @override
  void syncGridRows(AsyncValue<Object?> value) {
    final manager = gridStateManager;
    if (manager == null) return;
    manager.setShowLoading(value.isLoading);
    if (value.hasValue) {
      final rows = _filteredRows(value.value as List<PhysicalCount>);
      manager.removeAllRows();
      manager.appendRows([
        for (final (index, row) in rows.indexed)
          withSerialCell(gridRowFor(row), index),
      ]);
    }
  }

  void _refilter() => syncGridRows(ref.read(physicalCountsProvider));

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

  Color _statusColor(String status, ColorScheme scheme) => switch (status) {
    'Draft' => Colors.blueGrey,
    'In Progress' => Colors.orange,
    'Completed' => Colors.green,
    'Cancelled' => Colors.red,
    _ => scheme.primary,
  };

  @override
  Widget build(BuildContext context) {
    final counts = ref.watch(physicalCountsProvider);
    final l10n = AppLocalizations.of(context)!;

    // Keep the grid in sync with provider transitions (loading → data).
    // The mixin listener routes through the overridden syncGridRows, so
    // the client-side search applies on every load/refresh too.
    watchGridProvider(physicalCountsProvider);
    // Client-side search re-runs the filter over the loaded rows without
    // refetching.
    ref.listen(physicalCountsSearchProvider, (previous, next) => _refilter());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Toolbar: client-side search (count no / warehouse / status) +
        // refresh.
        ScreenToolbar(
          searchController: _searchController,
          searchHint: l10n.commonSearch,
          onSearchChanged: _onSearchChanged,
          onRefresh: () => ref.invalidate(physicalCountsProvider),
        ),
        Expanded(
          child: gridScreenBody(counts, provider: physicalCountsProvider),
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
