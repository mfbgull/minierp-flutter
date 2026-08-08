import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/csv_export.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/production.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/pluto_grid_screen.dart';
import 'production_detail_dialog.dart';
import 'production_form_dialog.dart';
import 'production_providers.dart';

/// Provider for the search text in the production screen.
final searchTextProvider = StateProvider<String>((ref) => '');

class ProductionScreen extends ConsumerStatefulWidget {
  const ProductionScreen({super.key});

  @override
  ConsumerState<ProductionScreen> createState() => _ProductionScreenState();
}

class _ProductionScreenState extends ConsumerState<ProductionScreen>
    with PlutoGridScreen<Production, ProductionScreen> {
  @override
  void openRowDetail(int productionId) {
    if (!mounted) return;
    showProductionDetailDialog(context, productionId: productionId);
  }

  @override
  Iterable<Production> gridRowsFrom(Object? value) {
    // Client-side search filter over the loaded rows (the mixin's
    // [PlutoGridScreen.gridRowsFrom] is called from the provider listener,
    // so this uses ref.read, not ref.watch).
    final searchText = ref.read(searchTextProvider);
    final lowerSearch = searchText.toLowerCase();
    if (lowerSearch.isEmpty) return super.gridRowsFrom(value);
    return super.gridRowsFrom(value).where((p) {
      return p.productionNo.toLowerCase().contains(lowerSearch) ||
          (p.outputItemName?.toLowerCase().contains(lowerSearch) ?? false) ||
          (p.outputItemCode?.toLowerCase().contains(lowerSearch) ?? false) ||
          (p.batchNo?.toLowerCase().contains(lowerSearch) ?? false) ||
          (p.remarks?.toLowerCase().contains(lowerSearch) ?? false) ||
          (p.finishedGoodsWarehouseName?.toLowerCase().contains(lowerSearch) ??
              false);
    });
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
    final showClear = ref.watch(searchTextProvider).isNotEmpty;

    watchGridProvider(productionsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Search bar
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SearchBar(
                    controller: TextEditingController(
                      text: ref.watch(searchTextProvider),
                    ),
                    onChanged: (text) =>
                        ref.read(searchTextProvider.notifier).state = text,
                    hintText: l10n.commonSearch,
                    leading: const Icon(Icons.search),
                    trailing: [
                      if (showClear)
                        IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () =>
                              ref.read(searchTextProvider.notifier).state = '',
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Toolbar buttons
              FilledButton.tonalIcon(
                onPressed: () => showProductionFormDialog(context),
                icon: const Icon(Icons.add, size: 18),
                label: Text(l10n.productionNewproduction),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed:
                    productions.isLoading ||
                        (productions.valueOrNull?.isEmpty ?? true)
                    ? null
                    : () => saveCsv(
                        context,
                        suggestedName: csvSuggestedName('productions'),
                        csv: buildProductionsCsv(
                          l10n,
                          productions.valueOrNull!,
                        ),
                        successMessage: l10n.productionExported,
                        errorMessage: l10n.productionExportfailed,
                      ),
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: Text(l10n.productionExportcsv),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: l10n.commonRefresh,
                icon: const Icon(Icons.refresh),
                onPressed: () => ref.invalidate(productionsProvider),
              ),
            ],
          ),
        ),
        Expanded(
          child: gridScreenBody(productions, provider: productionsProvider),
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
