import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/csv_export.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/production.dart';
import '../../data/repositories/paged_request.dart' show PagedResponse;
import '../../l10n/app_localizations.dart';
import '../../widgets/pagination_bar.dart' show ServerPaginationBar;
import '../../widgets/pluto_grid_screen.dart';
import '../../widgets/date_range_picker.dart' show DateRangeFilter;
import '../../widgets/screen_toolbar.dart';
import 'production_detail_dialog.dart';
import 'production_form_dialog.dart';
import 'production_providers.dart'
    show
        ProductionSort,
        filteredProductionsProvider,
        productionsFromDateProvider,
        productionsLimitProvider,
        productionsPageProvider,
        productionsProvider,
        productionsSortProvider,
        productionsToDateProvider,
        searchTextProvider;

class ProductionScreen extends ConsumerStatefulWidget {
  const ProductionScreen({super.key});

  @override
  ConsumerState<ProductionScreen> createState() => _ProductionScreenState();
}

class _ProductionScreenState extends ConsumerState<ProductionScreen>
    with PlutoGridScreen<Production, ProductionScreen> {
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
      ref.read(searchTextProvider.notifier).state = value.trim();
      // A new search starts back at page 1.
      if (ref.read(productionsPageProvider) != 1) {
        ref.read(productionsPageProvider.notifier).state = 1;
      }
    });
  }

  @override
  void openRowDetail(int productionId) {
    if (!mounted) return;
    showProductionDetailDialog(context, productionId: productionId);
  }

  /// The productions provider returns a `PagedResponse` envelope —
  /// unwrap the current page's items as the grid rows.
  @override
  Iterable<Production> gridRowsFrom(Object? value) =>
      (value as PagedResponse<Production>).items;

  /// Grid field → server sort column (whitelist in sqlSanitizer.ts).
  String? _sortColumnFor(String field) => switch (field) {
    'productionNo' => 'production_no',
    'date' => 'production_date',
    'output' => 'output_item_name',
    'warehouse' => 'warehouse_name',
    'qty' => 'output_quantity',
    'unitCost' => 'unit_cost',
    'totalCost' => 'total_batch_cost',
    'batchNo' => 'batch_no',
    _ => null,
  };

  /// Column sort maps to the server-side sort provider (this endpoint is
  /// server-paginated, so ordering happens on the server).
  @override
  void onGridSorted(PlutoGridOnSortedEvent event) {
    final sortBy = _sortColumnFor(event.column.field);
    if (sortBy == null) return;
    final sort = event.column.sort;
    ref.read(productionsSortProvider.notifier).state = sort.isNone
        ? null
        : ProductionSort(sortBy, sort == PlutoColumnSort.ascending ? 'ASC' : 'DESC');
    if (ref.read(productionsPageProvider) != 1) {
      ref.read(productionsPageProvider.notifier).state = 1;
    }
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
        onTap: () => showProductionDetailDialog(context, productionId: id),
      ),
    ];
  }

  @override
  PlutoRow gridRowFor(Production production) => PlutoRow(
    cells: {
      'id': PlutoCell(value: production.id),
      'productionNo': PlutoCell(value: production.productionNo),
      'date': PlutoCell(value: production.productionDate),
      'output': PlutoCell(
        value: production.outputItemName ?? production.outputItemCode ?? '',
      ),
      'qty': PlutoCell(value: production.outputQuantity),
      'uom': PlutoCell(value: production.outputUom ?? ''),
      'warehouse': PlutoCell(
        value: production.finishedGoodsWarehouseName ?? '',
      ),
      'unitCost': PlutoCell(value: production.unitCost ?? 0),
      'totalCost': PlutoCell(value: production.totalBatchCost ?? 0),
      'batchNo': PlutoCell(value: production.batchNo ?? ''),
      'remarks': PlutoCell(value: production.remarks ?? ''),
    },
  );

  @override
  Widget build(BuildContext context) {
    final productions = ref.watch(productionsProvider);
    final l10n = AppLocalizations.of(context)!;
    // The full filtered list feeds the CSV export.
    final filtered = ref.watch(filteredProductionsProvider);

    // Keep the grid in sync with provider transitions (loading → data).
    watchGridProvider(productionsProvider);

    final filteredRows = filtered.valueOrNull ?? const <Production>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Toolbar: search + CSV export + refresh + New production.
        ScreenToolbar(
          searchController: _searchController,
          searchHint: l10n.commonSearch,
          onSearchChanged: _onSearchChanged,
          onRefresh: () => ref.invalidate(productionsProvider),
          filters: [
            DateRangeFilter(
              fromProvider: productionsFromDateProvider,
              toProvider: productionsToDateProvider,
              onChanged: () {
                if (ref.read(productionsPageProvider) != 1) {
                  ref.read(productionsPageProvider.notifier).state = 1;
                }
              },
            ),
          ],
          actions: [
            TextButton.icon(
              onPressed: productions.isLoading || filteredRows.isEmpty
                  ? null
                  : () => saveCsv(
                      context,
                      suggestedName: csvSuggestedName('productions'),
                      csv: buildProductionsCsv(l10n, filteredRows),
                      successMessage: l10n.productionExported,
                      errorMessage: l10n.productionExportfailed,
                    ),
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: Text(l10n.productionExportcsv),
            ),
          ],
          primaryActions: [
            FilledButton.tonalIcon(
              onPressed: () => showProductionFormDialog(context),
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.productionNewproduction),
            ),
          ],
        ),
        Expanded(
          child: gridScreenBody(productions, provider: productionsProvider),
        ),
        if (productions.valueOrNull case final page?)
          ServerPaginationBar(
            page: page.currentPage,
            totalPages: page.totalPages,
            totalItems: page.totalItems,
            hasNext: page.hasNext,
            hasPrev: page.hasPrev,
            limit: ref.watch(productionsLimitProvider),
            itemLabel: l10n.productionProductions,
            onPageChanged: (p) =>
                ref.read(productionsPageProvider.notifier).state = p,
            onLimitChanged: (limit) {
              ref.read(productionsLimitProvider.notifier).state = limit;
              if (ref.read(productionsPageProvider) != 1) {
                ref.read(productionsPageProvider.notifier).state = 1;
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
      textColumn('productionNo', l10n.productionNo, 130),
      PlutoColumn(
        title: l10n.commonDate,
        field: 'date',
        type: PlutoColumnType.text(),
        width: 110,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) => Builder(
          builder: (cellContext) => Align(
            alignment: Alignment.centerLeft,
            child: Text(
              Formatters.date(ctx.cell.value as String? ?? ''),
              style: Theme.of(cellContext).textTheme.bodyMedium,
            ),
          ),
        ),
      ),
      textColumn('output', l10n.productionOutputitem, 240),
      PlutoColumn(
        title: l10n.commonQuantity,
        field: 'qty',
        type: PlutoColumnType.number(format: '#,###.000'),
        width: 100,
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
      textColumn('warehouse', l10n.productionWarehouse, 180),
      PlutoColumn(
        title: l10n.productionUnitcost,
        field: 'unitCost',
        type: PlutoColumnType.number(format: '#,###.00'),
        width: 110,
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
        title: l10n.productionTotalcost,
        field: 'totalCost',
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
      textColumn('batchNo', l10n.productionBatchno, 130),
      textColumn('remarks', l10n.purchasesRemarks, 240),
    ];
  }
}
