// Purchases tab — the supplier's direct-purchase grid (Purchase No |
// Date | Item | Qty | Unit Cost | Total | Invoice No) with a per-row ⋮
// menu — View (opens the shared purchase detail dialog). Companion to
// the POs tab: POs are orders placed with the supplier, purchases are
// the goods actually received/recorded against them.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/purchase.dart' show Purchase;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/detail_error.dart';
import '../../widgets/detail_tab_grid.dart';
import '../../widgets/pagination_bar.dart' show ServerPaginationBar;
import '../purchases/purchase_detail_dialog.dart' show showPurchaseDetailDialog;
import 'supplier_providers.dart';

enum _PurchaseRowAction { view }

class SupplierPurchasesTab extends ConsumerStatefulWidget {
  const SupplierPurchasesTab({super.key, required this.supplierId});

  final int supplierId;

  @override
  ConsumerState<SupplierPurchasesTab> createState() =>
      _SupplierPurchasesTabState();
}

class _SupplierPurchasesTabState extends ConsumerState<SupplierPurchasesTab> {
  /// Current page / per-page size for the server-side pagination.
  int _page = 1;
  int _limit = 10;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final purchases = ref.watch(
      supplierPurchasesPagedProvider(
        SupplierPurchasesArgs(
          supplierId: widget.supplierId,
          page: _page,
          limit: _limit,
        ),
      ),
    );

    // After a void the current page can fall past the last page — clamp
    // back so the tab doesn't strand the user on an empty page.
    ref.listen(
      supplierPurchasesPagedProvider(
        SupplierPurchasesArgs(
          supplierId: widget.supplierId,
          page: _page,
          limit: _limit,
        ),
      ),
      (previous, next) {
        final value = next.valueOrNull;
        if (value == null || value.items.isNotEmpty) return;
        if (value.totalPages > 0 && _page > value.totalPages) {
          setState(() => _page = value.totalPages);
        }
      },
    );

    return switch (purchases) {
      AsyncData(:final value) =>
        value.items.isEmpty
            ? _empty(context, l10n.suppliersNopurchases)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: DetailTabGrid<Purchase>(
                      data: value.items,
                      buildColumns: (l10n) => _columns(context, l10n),
                      gridRowFor: _gridRowFor,
                      hiddenFields: const ['data'],
                      widthKey: 'supplier_purchases',
                    ),
                  ),
                  ServerPaginationBar(
                    page: value.currentPage,
                    totalPages: value.totalPages,
                    totalItems: value.totalItems,
                    hasNext: value.hasNext,
                    hasPrev: value.hasPrev,
                    limit: _limit,
                    itemLabel: l10n.purchasesPurchases,
                    onPageChanged: (p) => setState(() => _page = p),
                    onLimitChanged: (limit) => setState(() {
                      _limit = limit;
                      _page = 1;
                    }),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
      AsyncError(:final error) => DetailError(
        message: error is ApiError ? error.message : '$error',
        onRetry: () => ref.invalidate(
          supplierPurchasesPagedProvider(
            SupplierPurchasesArgs(
              supplierId: widget.supplierId,
              page: _page,
              limit: _limit,
            ),
          ),
        ),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }

  Widget _empty(BuildContext context, String message) => Center(
    child: Text(
      message,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );

  void _viewPurchase(Purchase? purchase) {
    if (purchase == null || !mounted) return;
    showPurchaseDetailDialog(context, purchaseId: purchase.id);
  }

  PlutoRow _gridRowFor(Purchase p) => PlutoRow(
    cells: {
      'data': PlutoCell(value: p),
      'purchaseNo': PlutoCell(value: p.purchaseNo),
      'date': PlutoCell(value: Formatters.date(p.purchaseDate)),
      'item': PlutoCell(value: p.itemName),
      'quantity': PlutoCell(value: p.quantity),
      'unitCost': PlutoCell(value: p.unitCost),
      'total': PlutoCell(value: p.totalCost),
      'invoiceNo': PlutoCell(value: p.invoiceNo ?? ''),
      'actions': PlutoCell(value: ''),
    },
  );

  List<PlutoColumn> _columns(BuildContext context, AppLocalizations l10n) {
    PlutoColumn textCol(
      String field,
      String title,
      double width, {
      PlutoColumnTextAlign align = PlutoColumnTextAlign.start,
    }) => PlutoColumn(
      title: title,
      field: field,
      type: PlutoColumnType.text(),
      width: width,
      readOnly: true,
      enableContextMenu: false,
      textAlign: align,
      titleTextAlign: align,
    );

    return [
      // Hidden cell carrying the row's Purchase for the actions menu.
      PlutoColumn(
        title: '',
        field: 'data',
        type: PlutoColumnType.text(),
        width: 80,
        readOnly: true,
        renderer: (ctx) => const SizedBox.shrink(),
        enableContextMenu: false,
        enableFilterMenuItem: false,
        enableHideColumnMenuItem: false,
        enableSetColumnsMenuItem: false,
      ),
      // Link-style Purchase No (same treatment as the POs tab's PO No).
      PlutoColumn(
        title: l10n.purchasesPurchaseno,
        field: 'purchaseNo',
        type: PlutoColumnType.text(),
        width: 130,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) => Builder(
          builder: (cellContext) => GestureDetector(
            onTap: () =>
                _viewPurchase(ctx.cell.row.cells['data']?.value as Purchase?),
            child: Text(
              '${ctx.cell.value}',
              style: TextStyle(
                color: Theme.of(cellContext).colorScheme.primary,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
                decorationColor: Theme.of(cellContext).colorScheme.primary,
              ),
            ),
          ),
        ),
      ),
      textCol('date', l10n.purchasesDatecol, 110),
      textCol('item', l10n.purchasesItemcol, 200),
      textCol(
        'quantity',
        l10n.purchasesQuantitycol,
        90,
        align: PlutoColumnTextAlign.end,
      ),
      textCol(
        'unitCost',
        l10n.purchasesUnitcost,
        110,
        align: PlutoColumnTextAlign.end,
      ),
      textCol(
        'total',
        l10n.purchasesTotalcol,
        120,
        align: PlutoColumnTextAlign.end,
      ),
      textCol('invoiceNo', l10n.purchasesInvoicenumber, 120),
      // Per-row actions menu (same ⋮ dropdown pattern as the POs tab).
      PlutoColumn(
        title: l10n.suppliersActions,
        field: 'actions',
        // Pinned to the right edge — stays reachable when the grid scrolls.
        frozen: PlutoColumnFrozen.end,
        type: PlutoColumnType.text(),
        width: 64,
        readOnly: true,
        enableContextMenu: false,
        enableFilterMenuItem: false,
        enableHideColumnMenuItem: false,
        enableSetColumnsMenuItem: false,
        renderer: (ctx) {
          final purchase = ctx.cell.row.cells['data']?.value as Purchase?;
          return Builder(
            builder: (cellContext) => Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) => _openRowMenu(cellContext, purchase),
              child: Center(
                child: Icon(
                  Icons.more_vert,
                  size: 18,
                  color: Theme.of(cellContext).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        },
      ),
    ];
  }

  Future<void> _openRowMenu(
    BuildContext cellContext,
    Purchase? purchase,
  ) async {
    if (purchase == null || !mounted) return;
    final box = cellContext.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final overlay = Overlay.of(cellContext, rootOverlay: true);
    final l10n = AppLocalizations.of(cellContext)!;
    final action = await showMenu<_PurchaseRowAction>(
      context: cellContext,
      position: RelativeRect.fromRect(
        Rect.fromPoints(
          box.localToGlobal(Offset.zero),
          box.localToGlobal(box.size.bottomRight(Offset.zero)),
        ),
        Offset.zero & overlay.context.size!,
      ),
      items: [
        PopupMenuItem(
          value: _PurchaseRowAction.view,
          child: Row(
            children: [
              const Icon(Icons.visibility_outlined, size: 18),
              const SizedBox(width: 8),
              Text(l10n.commonView),
            ],
          ),
        ),
      ],
    );
    if (action != null && mounted) {
      _viewPurchase(purchase);
    }
  }
}
