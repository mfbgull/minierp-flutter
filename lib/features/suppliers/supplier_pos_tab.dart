// POs tab — web supplier `POSTab` parity: the supplier's purchase-order
// grid (PO No | Date | Status | Total | Expected Delivery) with a per-row
// ⋮ menu — View (opens the shared PO detail dialog, the Flutter
// equivalent of the web's `/purchase-orders/:id` navigation).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/purchase_order.dart' show PurchaseOrder;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/detail_error.dart';
import '../../widgets/detail_tab_grid.dart';
import '../../widgets/pagination_bar.dart' show ServerPaginationBar;
import '../../widgets/status_badge.dart';
import '../purchase_orders/purchase_order_detail_dialog.dart'
    show showPurchaseOrderDetailDialog;
import 'supplier_providers.dart';

enum _PoRowAction { view }

class SupplierPosTab extends ConsumerStatefulWidget {
  const SupplierPosTab({super.key, required this.supplierId});

  final int supplierId;

  @override
  ConsumerState<SupplierPosTab> createState() => _SupplierPosTabState();
}

class _SupplierPosTabState extends ConsumerState<SupplierPosTab> {
  /// Current page / per-page size for the server-side pagination.
  int _page = 1;
  int _limit = 10;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final pos = ref.watch(
      supplierPurchaseOrdersPagedProvider(
        SupplierPurchaseOrdersArgs(
          supplierId: widget.supplierId,
          page: _page,
          limit: _limit,
        ),
      ),
    );

    // After a status change / deletion the current page can fall past the
    // last page — clamp back so the tab doesn't strand the user on an
    // empty page.
    ref.listen(
      supplierPurchaseOrdersPagedProvider(
        SupplierPurchaseOrdersArgs(
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

    return switch (pos) {
      AsyncData(:final value) => value.items.isEmpty
          ? _empty(context, l10n.suppliersNopos)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: DetailTabGrid<PurchaseOrder>(
                    data: value.items,
                    buildColumns: (l10n) => _columns(context, l10n),
                    gridRowFor: _gridRowFor,
                    hiddenFields: const ['data'],
                    widthKey: 'supplier_pos',
                  ),
                ),
                ServerPaginationBar(
                  page: value.currentPage,
                  totalPages: value.totalPages,
                  totalItems: value.totalItems,
                  hasNext: value.hasNext,
                  hasPrev: value.hasPrev,
                  limit: _limit,
                  itemLabel: l10n.purchaseordersPurchaseorders,
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
          supplierPurchaseOrdersPagedProvider(
            SupplierPurchaseOrdersArgs(
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

  void _viewPo(PurchaseOrder? po) {
    if (po == null || !mounted) return;
    showPurchaseOrderDetailDialog(context, poId: po.id);
  }

  PlutoRow _gridRowFor(PurchaseOrder po) => PlutoRow(
    cells: {
      'data': PlutoCell(value: po),
      'poNo': PlutoCell(value: po.poNo),
      'date': PlutoCell(value: Formatters.date(po.poDate)),
      'status': PlutoCell(value: po.status),
      'total': PlutoCell(value: po.totalAmount),
      'expected': PlutoCell(
        value: po.expectedDeliveryDate?.isEmpty ?? true
            ? ''
            : Formatters.date(po.expectedDeliveryDate!),
      ),
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
      // Hidden cell carrying the row's PurchaseOrder for the actions menu.
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
      // Link-style PO No (web's invoice-link column).
      PlutoColumn(
        title: l10n.suppliersPono,
        field: 'poNo',
        type: PlutoColumnType.text(),
        width: 130,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) => Builder(
          builder: (cellContext) => GestureDetector(
            onTap: () =>
                _viewPo(ctx.cell.row.cells['data']?.value as PurchaseOrder?),
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
      textCol('date', l10n.commonDate, 110),
      PlutoColumn(
        title: l10n.commonStatus,
        field: 'status',
        type: PlutoColumnType.text(),
        width: 130,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) {
          final status = '${ctx.cell.value}';
          return Align(
            alignment: Alignment.centerLeft,
            child: StatusBadge(
              status: status.isEmpty ? '—' : status,
              color: _statusColor(context, status),
            ),
          );
        },
      ),
      textCol(
        'total',
        l10n.suppliersTotal,
        120,
        align: PlutoColumnTextAlign.end,
      ),
      textCol('expected', l10n.suppliersExpecteddelivery, 130),
      // Per-row actions menu (web ⋮ dropdown with View).
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
          final po = ctx.cell.row.cells['data']?.value as PurchaseOrder?;
          return Builder(
            builder: (cellContext) => Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) => _openRowMenu(cellContext, po),
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

  Color _statusColor(BuildContext context, String status) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return switch (status) {
      'Completed' => isDark ? const Color(0xFF4ADE80) : const Color(0xFF15803D),
      'Partially Received' ||
      'PartiallyReceived' =>
        isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
      'Cancelled' => Theme.of(context).colorScheme.error,
      _ => Theme.of(context).colorScheme.primary,
    };
  }

  Future<void> _openRowMenu(
    BuildContext cellContext,
    PurchaseOrder? po,
  ) async {
    if (po == null || !mounted) return;
    final box = cellContext.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final overlay = Overlay.of(cellContext, rootOverlay: true);
    final l10n = AppLocalizations.of(cellContext)!;
    final action = await showMenu<_PoRowAction>(
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
          value: _PoRowAction.view,
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
      _viewPo(po);
    }
  }
}
