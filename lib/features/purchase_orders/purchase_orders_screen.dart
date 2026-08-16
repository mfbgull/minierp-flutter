// Purchase orders list screen — a read-only grid over `GET
// /purchase-orders` (**bare array**; no search/page params, so sorting and
// filtering stay client-side like the items screen). Rendered with
// PlutoGrid via the shared [PlutoGridScreen] mixin: F2/Enter + double-tap
// open the PO detail, and the keyboard-hint status bar sits beneath the
// grid. Sits at the shell branch `/purchasing` (the web app hosts the PO
// tab inside the purchasing module).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/csv_export.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/po_status.dart';
import '../../data/models/purchase_order.dart' show PurchaseOrder;
import '../../l10n/app_localizations.dart';
import '../../widgets/pluto_grid_screen.dart';
import '../../widgets/screen_toolbar.dart';
import '../../widgets/status_badge.dart';
import 'purchase_order_detail_dialog.dart';
import 'purchase_order_form_dialog.dart';
import 'purchase_order_providers.dart';

class PurchaseOrdersScreen extends ConsumerStatefulWidget {
  const PurchaseOrdersScreen({super.key});

  @override
  ConsumerState<PurchaseOrdersScreen> createState() =>
      _PurchaseOrdersScreenState();
}

class _PurchaseOrdersScreenState extends ConsumerState<PurchaseOrdersScreen>
    with PlutoGridScreen<PurchaseOrder, PurchaseOrdersScreen> {
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
      ref.read(purchaseOrdersSearchProvider.notifier).state = value.trim();
    });
  }

  /// Client-side search over the loaded rows (the endpoint has no search
  /// param) — overrides the mixin's unfiltered clear+append.
  List<PurchaseOrder> _filteredRows(List<PurchaseOrder> orders) {
    final search = ref.read(purchaseOrdersSearchProvider).toLowerCase();
    if (search.isEmpty) return orders;
    return orders
        .where(
          (po) =>
              po.poNo.toLowerCase().contains(search) ||
              po.supplierName.toLowerCase().contains(search),
        )
        .toList();
  }

  @override
  void syncGridRows(AsyncValue<Object?> value) {
    final manager = gridStateManager;
    if (manager == null) return;
    manager.setShowLoading(value.isLoading);
    if (value.hasValue) {
      final rows = _filteredRows(value.value as List<PurchaseOrder>);
      manager.removeAllRows();
      manager.appendRows([
        for (final (index, row) in rows.indexed)
          withSerialCell(gridRowFor(row), index),
      ]);
    }
  }

  void _refilter() => syncGridRows(ref.read(purchaseOrdersProvider));

  @override
  void openRowDetail(int poId) {
    if (!mounted) return;
    showPurchaseOrderDetailDialog(context, poId: poId);
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
        onTap: () => showPurchaseOrderDetailDialog(context, poId: id),
      ),
    ];
  }

  @override
  PlutoRow gridRowFor(PurchaseOrder po) => PlutoRow(
    cells: {
      'id': PlutoCell(value: po.id),
      'poNo': PlutoCell(value: po.poNo),
      'date': PlutoCell(value: po.poDate),
      'supplier': PlutoCell(value: po.supplierName),
      'status': PlutoCell(value: po.status),
      'total': PlutoCell(value: po.totalAmount),
      'expected': PlutoCell(value: po.expectedDeliveryDate ?? ''),
    },
  );

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(purchaseOrdersProvider);
    final l10n = AppLocalizations.of(context)!;

    // Keep the grid in sync with provider transitions (loading → data).
    // The mixin listener routes through the overridden syncGridRows, so
    // the client-side search applies on every load/refresh too.
    watchGridProvider(purchaseOrdersProvider);
    // Client-side search re-runs the filter over the loaded rows without
    // refetching.
    ref.listen(purchaseOrdersSearchProvider, (previous, next) => _refilter());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Toolbar: search + CSV export + refresh + New PO.
        ScreenToolbar(
          searchController: _searchController,
          searchHint: l10n.commonSearch,
          onSearchChanged: _onSearchChanged,
          onRefresh: () => ref.invalidate(purchaseOrdersProvider),
          actions: [
            // CSV export — mirrors the sales-orders/returns grids: the
            // pure builder runs over the currently-filtered rows and
            // the shared save helper owns the FilePicker + toast.
            TextButton.icon(
              onPressed: orders.isLoading ||
                      _filteredRows(orders.valueOrNull ?? const []).isEmpty
                  ? null
                  : () => saveCsv(
                      context,
                      suggestedName: csvSuggestedName('purchase-orders'),
                      csv: buildPurchaseOrdersCsv(
                        l10n,
                        _filteredRows(orders.valueOrNull ?? const []),
                      ),
                      successMessage: l10n.purchaseordersExported,
                      errorMessage: l10n.purchaseordersExportfailed,
                    ),
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: Text(l10n.purchaseordersExportcsv),
            ),
          ],
          primaryActions: [
            FilledButton.tonalIcon(
              onPressed: () => showPurchaseOrderFormDialog(context),
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.purchaseordersNewpurchaseorder),
            ),
          ],
        ),
        Expanded(
          child: gridScreenBody(orders, provider: purchaseOrdersProvider),
        ),
      ],
    );
  }

  /// Column set — order/format mirrors the web POSTab grid (PO No, Date,
  /// Status, Total, Expected Delivery) plus Supplier for the standalone
  /// list; read-only for now.
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
      textColumn('poNo', l10n.purchaseordersPono, 110),
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
      PlutoColumn(
        title: l10n.purchasesSuppliercol,
        field: 'supplier',
        type: PlutoColumnType.text(),
        width: 220,
        readOnly: true,
        enableContextMenu: false,
      ),
      PlutoColumn(
        title: l10n.commonStatus,
        field: 'status',
        type: PlutoColumnType.text(),
        width: 140,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) => Builder(
          builder: (cellContext) {
            final status = ctx.cell.value as String? ?? '';
            final (color, darkColor) = poStatusColors(status);
            return Align(
              alignment: Alignment.centerLeft,
              child: StatusBadge(
                status: poStatusLabel(
                  AppLocalizations.of(cellContext)!,
                  status,
                ),
                color: color,
                darkColor: darkColor,
              ),
            );
          },
        ),
      ),
      PlutoColumn(
        title: l10n.commonTotal,
        field: 'total',
        type: PlutoColumnType.number(format: '#,###.00'),
        width: 110,
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
        title: l10n.purchaseordersExpecteddelivery,
        field: 'expected',
        type: PlutoColumnType.text(),
        width: 140,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) => Builder(
          builder: (cellContext) {
            final value = ctx.cell.value as String? ?? '';
            return Align(
              alignment: Alignment.centerLeft,
              child: Text(
                value.isEmpty ? '—' : Formatters.date(value),
                style: Theme.of(cellContext).textTheme.bodyMedium,
              ),
            );
          },
        ),
      ),
    ];
  }
}
