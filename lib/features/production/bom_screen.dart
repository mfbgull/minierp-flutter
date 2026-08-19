// BOM list — a read-only grid over `GET /boms` (**server-paginated**;
// search and sorting happen server-side, grid-pagination §7.2 — the
// endpoint returns a `pagination` block). Rendered with PlutoGrid via
// the shared [PlutoGridScreen] mixin: F2/Enter + double-tap open the
// BOM detail, and the [ServerPaginationBar] sits beneath the grid. Sits
// on the `BOM` tab of the production shell (the web app hosts the BOM
// list at `/bom`).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/csv_export.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/bom.dart';
import '../../data/repositories/paged_request.dart' show PagedResponse;
import '../../l10n/app_localizations.dart';
import '../../widgets/pagination_bar.dart' show ServerPaginationBar;
import '../../widgets/pluto_grid_screen.dart';
import '../../widgets/screen_toolbar.dart';
import '../../widgets/status_badge.dart';
import 'bom_detail_dialog.dart';
import 'bom_form_dialog.dart';
import 'production_providers.dart';

class BomScreen extends ConsumerStatefulWidget {
  const BomScreen({super.key});

  @override
  ConsumerState<BomScreen> createState() => _BomScreenState();
}

class _BomScreenState extends ConsumerState<BomScreen>
    with PlutoGridScreen<Bom, BomScreen> {
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
      ref.read(bomsSearchProvider.notifier).state = value.trim();
      // A new search starts back at page 1.
      if (ref.read(bomsPageProvider) != 1) {
        ref.read(bomsPageProvider.notifier).state = 1;
      }
    });
  }

  /// The boms provider returns a `PagedResponse` envelope — unwrap the
  /// current page's items as the grid rows.
  @override
  Iterable<Bom> gridRowsFrom(Object? value) =>
      (value as PagedResponse<Bom>).items;

  /// Grid field → server sort column (whitelist in sqlSanitizer.ts).
  String? _sortColumnFor(String field) => switch (field) {
    'bomNo' => 'bom_no',
    'name' => 'bom_name',
    'finished' => 'finished_item_name',
    'qty' => 'quantity',
    'items' => 'item_count',
    'cost' => 'total_material_cost',
    _ => null,
  };

  /// Column sort maps to the server-side sort provider (this endpoint is
  /// server-paginated, so ordering happens on the server).
  @override
  void onGridSorted(PlutoGridOnSortedEvent event) {
    final sortBy = _sortColumnFor(event.column.field);
    if (sortBy == null) return;
    final sort = event.column.sort;
    ref.read(bomsSortProvider.notifier).state = sort.isNone
        ? null
        : BomSort(sortBy, sort == PlutoColumnSort.ascending ? 'ASC' : 'DESC');
    if (ref.read(bomsPageProvider) != 1) {
      ref.read(bomsPageProvider.notifier).state = 1;
    }
  }

  @override
  void openRowDetail(int bomId) {
    if (!mounted) return;
    showBomDetailDialog(context, bomId: bomId);
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
        onTap: () => showBomDetailDialog(context, bomId: id),
      ),
    ];
  }

  @override
  PlutoRow gridRowFor(Bom bom) => PlutoRow(
    cells: {
      'id': PlutoCell(value: bom.id),
      'bomNo': PlutoCell(value: bom.bomNo),
      'name': PlutoCell(value: bom.bomName),
      'finished': PlutoCell(
        value: bom.finishedItemName ?? bom.finishedItemCode ?? '',
      ),
      'qty': PlutoCell(value: bom.quantity),
      'uom': PlutoCell(value: bom.finishedUom ?? ''),
      'items': PlutoCell(value: bom.itemCount ?? 0),
      'cost': PlutoCell(value: bom.totalMaterialCost ?? 0),
      'active': PlutoCell(value: bom.isActive),
    },
  );

  @override
  Widget build(BuildContext context) {
    final boms = ref.watch(bomsProvider);
    final l10n = AppLocalizations.of(context)!;
    // The full filtered list feeds the CSV export.
    final filtered = ref.watch(filteredBomsProvider);

    // Keep the grid in sync with provider transitions (loading → data).
    watchGridProvider(bomsProvider);

    final filteredRows = filtered.valueOrNull ?? const <Bom>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Toolbar: search + CSV export + refresh + New BOM.
        ScreenToolbar(
          searchController: _searchController,
          searchHint: l10n.commonSearch,
          onSearchChanged: _onSearchChanged,
          onRefresh: () => ref.invalidate(bomsProvider),
          actions: [
            TextButton.icon(
              onPressed: boms.isLoading || filteredRows.isEmpty
                  ? null
                  : () => saveCsv(
                      context,
                      suggestedName: csvSuggestedName('boms'),
                      csv: buildBomsCsv(l10n, filteredRows),
                      successMessage: l10n.bomExported,
                      errorMessage: l10n.bomExportfailed,
                    ),
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: Text(l10n.bomExportcsv),
            ),
          ],
          primaryActions: [
            FilledButton.tonalIcon(
              onPressed: () => showBomFormDialog(context),
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.bomNewbom),
            ),
          ],
        ),
        Expanded(child: gridScreenBody(boms, provider: bomsProvider)),
        if (boms.valueOrNull case final page?)
          ServerPaginationBar(
            page: page.currentPage,
            totalPages: page.totalPages,
            totalItems: page.totalItems,
            hasNext: page.hasNext,
            hasPrev: page.hasPrev,
            limit: ref.watch(bomsLimitProvider),
            itemLabel: l10n.bomBoms,
            onPageChanged: (p) =>
                ref.read(bomsPageProvider.notifier).state = p,
            onLimitChanged: (limit) {
              ref.read(bomsLimitProvider.notifier).state = limit;
              if (ref.read(bomsPageProvider) != 1) {
                ref.read(bomsPageProvider.notifier).state = 1;
              }
            },
          ),
        const SizedBox(height: 16),
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
      textColumn('bomNo', l10n.bomNo, 120),
      textColumn('name', l10n.bomName, 220),
      textColumn('finished', l10n.bomFinisheditem, 240),
      PlutoColumn(
        title: l10n.commonQuantity,
        field: 'qty',
        type: PlutoColumnType.number(format: '#,###.000'),
        width: 90,
        readOnly: true,
        textAlign: PlutoColumnTextAlign.end,
        titleTextAlign: PlutoColumnTextAlign.end,
        enableContextMenu: false,
        renderer: (ctx) => Align(
          alignment: Alignment.centerRight,
          child: Text(Formatters.number(ctx.cell.value as num? ?? 0)),
        ),
      ),
      textColumn('uom', l10n.commonUom, 80),
      PlutoColumn(
        title: l10n.bomItems,
        field: 'items',
        type: PlutoColumnType.number(),
        width: 90,
        readOnly: true,
        textAlign: PlutoColumnTextAlign.end,
        titleTextAlign: PlutoColumnTextAlign.end,
        enableContextMenu: false,
        renderer: (ctx) => Align(
          alignment: Alignment.centerRight,
          child: Text('${ctx.cell.value}'),
        ),
      ),
      PlutoColumn(
        title: l10n.bomMaterialcost,
        field: 'cost',
        type: PlutoColumnType.number(format: '#,###.00'),
        width: 120,
        readOnly: true,
        textAlign: PlutoColumnTextAlign.right,
        titleTextAlign: PlutoColumnTextAlign.right,
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
        renderer: (ctx) => Builder(
          builder: (cellContext) {
            final active = ctx.cell.value == true;
            final l10n = AppLocalizations.of(cellContext)!;
            return Align(
              alignment: Alignment.centerLeft,
              child: StatusBadge(
                status: active ? l10n.statusActive : l10n.statusInactive,
                color: active
                    ? const Color(0xFF059669)
                    : const Color(0xFF6B7280),
                darkColor: active
                    ? const Color(0xFF10B981)
                    : const Color(0xFF86EFAC),
              ),
            );
          },
        ),
      ),
    ];
  }
}
