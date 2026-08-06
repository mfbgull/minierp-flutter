// Direct purchases list screen — a read-only grid over `GET /purchases`
// (**bare array**; no search/page params, so sorting and filtering stay
// client-side like the items screen). Rendered with PlutoGrid via the
// shared [PlutoGridScreen] mixin: F2/Enter + double-tap open the
// purchase detail, whose Process Return action drives the return-
// processing flow. Sits in the purchasing module shell alongside the
// PO and purchase-returns tabs (the web app hosts `/purchases` in the
// same module).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/purchase.dart' show Purchase;
import '../../l10n/app_localizations.dart';
import '../../widgets/pluto_grid_screen.dart';
import 'purchase_detail_dialog.dart';
import 'purchase_providers.dart';

class PurchasesScreen extends ConsumerStatefulWidget {
  const PurchasesScreen({super.key});

  @override
  ConsumerState<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends ConsumerState<PurchasesScreen>
    with PlutoGridScreen<Purchase, PurchasesScreen> {
  @override
  void openRowDetail(int purchaseId) {
    if (!mounted) return;
    showPurchaseDetailDialog(context, purchaseId: purchaseId);
  }

  @override
  PlutoRow gridRowFor(Purchase purchase) => PlutoRow(
    cells: {
      'id': PlutoCell(value: purchase.id),
      'purchaseNo': PlutoCell(value: purchase.purchaseNo),
      'date': PlutoCell(value: purchase.purchaseDate),
      'item': PlutoCell(value: purchase.itemName),
      'qty': PlutoCell(value: purchase.quantity),
      'unitCost': PlutoCell(value: purchase.unitCost),
      'total': PlutoCell(value: purchase.totalCost),
      'supplier': PlutoCell(value: purchase.supplierName ?? ''),
      'warehouse': PlutoCell(value: purchase.warehouseName),
      'invoiceNo': PlutoCell(value: purchase.invoiceNo ?? ''),
    },
  );

  @override
  Widget build(BuildContext context) {
    final purchases = ref.watch(purchasesProvider);
    final l10n = AppLocalizations.of(context)!;

    // Keep the grid in sync with provider transitions (loading → data).
    watchGridProvider(purchasesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                tooltip: l10n.commonRefresh,
                icon: const Icon(Icons.refresh),
                onPressed: () => ref.invalidate(purchasesProvider),
              ),
            ],
          ),
        ),
        Expanded(child: gridScreenBody(purchases, provider: purchasesProvider)),
      ],
    );
  }

  /// Column set — order/format mirrors the web PurchasesPage grid
  /// (Purchase #, Date, Item, Qty, Unit Cost, Total, Supplier,
  /// Warehouse, Invoice No); read-only.
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

    PlutoColumn moneyColumn(String field, String title, double width) =>
        PlutoColumn(
          title: title,
          field: field,
          type: PlutoColumnType.number(format: '#,###.00'),
          width: width,
          readOnly: true,
          textAlign: PlutoColumnTextAlign.end,
          titleTextAlign: PlutoColumnTextAlign.end,
          enableContextMenu: false,
          renderer: (ctx) => Builder(
            builder: (cellContext) => Align(
              alignment: Alignment.centerRight,
              child: Text(
                Formatters.currency(ctx.cell.value as num? ?? 0),
                style: Theme.of(cellContext).textTheme.bodyMedium,
              ),
            ),
          ),
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
      textColumn('purchaseNo', l10n.purchasesPurchaseno, 120),
      PlutoColumn(
        title: l10n.purchasesDatecol,
        field: 'date',
        type: PlutoColumnType.text(),
        width: 105,
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
      PlutoColumn(
        title: l10n.purchasesItemcol,
        field: 'item',
        type: PlutoColumnType.text(),
        width: 190,
        readOnly: true,
        enableContextMenu: false,
      ),
      PlutoColumn(
        title: l10n.purchasesQuantitycol,
        field: 'qty',
        type: PlutoColumnType.number(format: '#,###.00'),
        width: 85,
        readOnly: true,
        textAlign: PlutoColumnTextAlign.end,
        titleTextAlign: PlutoColumnTextAlign.end,
        enableContextMenu: false,
      ),
      moneyColumn('unitCost', l10n.purchasesUnitcost, 100),
      moneyColumn('total', l10n.purchasesTotalcol, 110),
      textColumn('supplier', l10n.purchasesSuppliercol, 170),
      textColumn('warehouse', l10n.purchasesWarehousecol, 130),
      textColumn('invoiceNo', l10n.purchasesInvoicenumber, 110),
    ];
  }
}
