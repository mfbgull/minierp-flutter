// Purchase returns list screen — a read-only grid over `GET
// /purchases/returns` (**bare array** of negative stock movements; no
// search/page params, so sorting and filtering stay client-side like the
// items screen). Rendered with PlutoGrid via the shared
// [PlutoGridScreen] mixin: F2/Enter + double-tap open the return detail,
// and the keyboard-hint status bar sits beneath the grid. Hosted as the
// 'Purchase Returns' tab of the purchasing shell (the web app pairs it
// with `/purchase-orders`).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/purchase_return.dart' show PurchaseReturn;
import '../../l10n/app_localizations.dart';
import '../../widgets/pluto_grid_screen.dart';
import '../../widgets/status_badge.dart';
import 'purchase_return_detail_dialog.dart';
import 'purchase_return_providers.dart';
import 'purchase_return_type.dart';

class PurchaseReturnsScreen extends ConsumerStatefulWidget {
  const PurchaseReturnsScreen({super.key});

  @override
  ConsumerState<PurchaseReturnsScreen> createState() =>
      _PurchaseReturnsScreenState();
}

class _PurchaseReturnsScreenState extends ConsumerState<PurchaseReturnsScreen>
    with PlutoGridScreen<PurchaseReturn, PurchaseReturnsScreen> {
  /// Row id → model for the detail dialog — there is no per-row endpoint,
  /// so the dialog renders from the row the grid was built from.
  final Map<int, PurchaseReturn> _returnsById = {};

  @override
  void openRowDetail(int returnId) {
    if (!mounted) return;
    final purchaseReturn = _returnsById[returnId];
    if (purchaseReturn == null) return;
    showPurchaseReturnDetailDialog(context, purchaseReturn: purchaseReturn);
  }

  @override
  PlutoRow gridRowFor(PurchaseReturn purchaseReturn) {
    // Cache the model for the F2/Enter/double-tap detail path.
    _returnsById[purchaseReturn.id] = purchaseReturn;
    return PlutoRow(
      cells: {
        'id': PlutoCell(value: purchaseReturn.id),
        'returnNo': PlutoCell(value: purchaseReturn.movementNo),
        'date': PlutoCell(value: purchaseReturn.returnDate),
        'item': PlutoCell(value: purchaseReturn.itemName),
        'qty': PlutoCell(value: purchaseReturn.returnQty),
        'unitCost': PlutoCell(value: purchaseReturn.unitCost),
        'total': PlutoCell(value: purchaseReturn.returnValue),
        'type': PlutoCell(value: purchaseReturn.referenceDocType),
        'warehouse': PlutoCell(value: purchaseReturn.warehouseName),
        'remarks': PlutoCell(value: purchaseReturn.remarks ?? ''),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final returns = ref.watch(purchaseReturnsProvider);
    final l10n = AppLocalizations.of(context)!;

    // Keep the grid in sync with provider transitions (loading → data).
    watchGridProvider(purchaseReturnsProvider);

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
                onPressed: () => ref.invalidate(purchaseReturnsProvider),
              ),
            ],
          ),
        ),
        Expanded(
          child: gridScreenBody(returns, provider: purchaseReturnsProvider),
        ),
      ],
    );
  }

  /// Column set — mirrors the return-history columns the web app shows
  /// (Return No, Date, Item, Qty, Unit Cost, Total, Type, Warehouse,
  /// Remarks); read-only for now (returns are created from a purchase).
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
        // Hidden in onLoaded — never reveal it via the column menu.
        enableContextMenu: false,
        enableFilterMenuItem: false,
        enableHideColumnMenuItem: false,
        enableSetColumnsMenuItem: false,
      ),
      textColumn('returnNo', l10n.purchasesReturnno, 120),
      PlutoColumn(
        title: l10n.purchasesReturndate,
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
      textColumn('item', l10n.fieldsItem, 200),
      PlutoColumn(
        title: l10n.purchasesReturnqty,
        field: 'qty',
        type: PlutoColumnType.number(format: '#,###.##'),
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
      PlutoColumn(
        title: l10n.purchasesUnitcost,
        field: 'unitCost',
        type: PlutoColumnType.number(format: '#,###.00'),
        width: 100,
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
        title: l10n.purchasesReturnvalue,
        field: 'total',
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
        title: l10n.purchasesReturntype,
        field: 'type',
        type: PlutoColumnType.text(),
        width: 140,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) => Builder(
          builder: (cellContext) {
            final type = ctx.cell.value as String? ?? '';
            final (color, darkColor) = returnTypeColors(type);
            return Align(
              alignment: Alignment.centerLeft,
              child: StatusBadge(
                status: returnTypeLabel(
                  AppLocalizations.of(cellContext)!,
                  type,
                ),
                color: color,
                darkColor: darkColor,
              ),
            );
          },
        ),
      ),
      textColumn('warehouse', l10n.fieldsWarehouse, 140),
      textColumn('remarks', l10n.fieldsNotes, 180),
    ];
  }
}
