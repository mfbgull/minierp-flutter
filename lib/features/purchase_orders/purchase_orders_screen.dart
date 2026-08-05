// Purchase orders list screen — a read-only grid over `GET
// /purchase-orders` (**bare array**; no search/page params, so sorting and
// filtering stay client-side like the items screen). Rendered with
// PlutoGrid using the shared grid scaffold: the hidden-id row pattern,
// F2/Enter + double-tap open the PO detail, and the keyboard-hint status
// bar sits beneath the grid. Sits at the shell branch `/purchasing` (the
// web app hosts the PO tab inside the purchasing module).
//
// Grid state: PlutoGrid keeps its own `PlutoGridStateManager`, so rows
// are fed through the manager (clear + append) on provider changes rather
// than by rebuilding the widget; the provider is the single source of
// truth and the screen never mutates rows directly.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/purchase_order.dart' show PurchaseOrder;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/grid_status_bar.dart';
import '../../widgets/pluto_grid_shortcuts.dart';
import '../../widgets/screen_error_panel.dart';
import '../../widgets/status_badge.dart';
import 'po_status.dart';
import 'purchase_order_detail_dialog.dart';
import 'purchase_order_providers.dart';

class PurchaseOrdersScreen extends ConsumerStatefulWidget {
  const PurchaseOrdersScreen({super.key});

  @override
  ConsumerState<PurchaseOrdersScreen> createState() =>
      _PurchaseOrdersScreenState();
}

class _PurchaseOrdersScreenState extends ConsumerState<PurchaseOrdersScreen> {
  PlutoGridStateManager? _stateManager;
  late List<PlutoColumn> _columns;
  bool _columnsReady = false;
  PlutoGridConfiguration _configuration = const PlutoGridConfiguration();
  bool _configurationReady = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Column titles are localized — build them once here (lookups of
    // inherited widgets are not allowed before initState completes).
    if (!_columnsReady) {
      _columns = _buildColumns(AppLocalizations.of(context)!);
      _columnsReady = true;
    }
    // Same for the grid configuration: F2/Enter open the focused row's
    // detail (see _OpenDetailAction). Built once — the shortcut map holds
    // a closure over this State's context, so it must not be recreated
    // after the widget is disposed.
    if (!_configurationReady) {
      _configuration = PlutoGridConfiguration(
        shortcut: PlutoGridShortcut(
          actions: rowDetailShortcutActions(_openDetail),
        ),
      );
      _configurationReady = true;
    }
  }

  void _openDetail(int poId) {
    if (!mounted) return;
    showPurchaseOrderDetailDialog(context, poId: poId);
  }

  /// Pushes the provider state into the grid manager (clear + append, with
  /// the loading overlay toggled). No-op until the grid reports `onLoaded`.
  void _applyOrders(AsyncValue<List<PurchaseOrder>> value) {
    final manager = _stateManager;
    if (manager == null) return;
    manager.setShowLoading(value.isLoading);
    if (value.hasValue) {
      manager.removeAllRows();
      manager.appendRows([
        for (final po in value.value ?? const <PurchaseOrder>[]) _rowFor(po),
      ]);
    }
  }

  static PlutoRow _rowFor(PurchaseOrder po) => PlutoRow(
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
    ref.listen(purchaseOrdersProvider, (previous, next) => _applyOrders(next));

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
                onPressed: () => ref.invalidate(purchaseOrdersProvider),
              ),
            ],
          ),
        ),
        Expanded(child: _buildBody(orders)),
      ],
    );
  }

  Widget _buildBody(AsyncValue<List<PurchaseOrder>> orders) {
    final errorMessage = switch (orders) {
      AsyncError(:final error) => error is ApiError ? error.message : null,
      _ => null,
    };
    if (errorMessage != null) {
      // The grid unmounts below — drop the manager handle so a later
      // listener callback never touches the disposed PlutoGridStateManager.
      _stateManager = null;
      return ScreenErrorPanel(
        message: errorMessage,
        onRetry: () => ref.invalidate(purchaseOrdersProvider),
      );
    }
    // Data and loading (including first load) both render the grid; the
    // loading overlay is driven through the grid manager in `_applyOrders`.
    return _grid();
  }

  Widget _grid() {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: PlutoGrid(
              columns: _columns,
              configuration: _configuration,
              // NOTE: must be a *growable* list — PlutoGrid's FilteredList
              // wraps the passed rows and appends to it.
              rows: <PlutoRow>[],
              onLoaded: (event) {
                _stateManager = event.stateManager;
                // The id column exists only to carry the row's PO id to the
                // detail handlers — hide it (cells stay readable via
                // `row.cells['id']`, so it survives client-side sorting).
                _stateManager?.hideColumn(
                  _columns.firstWhere((c) => c.field == 'id'),
                  true,
                  notify: false,
                );
                // Sync any provider state that changed before the grid
                // finished mounting (e.g. the first loading flag).
                _applyOrders(ref.read(purchaseOrdersProvider));
              },
              onRowDoubleTap: (event) {
                final id = (event.row.cells['id']?.value as num?)?.toInt();
                if (id == null || id <= 0) return;
                showPurchaseOrderDetailDialog(context, poId: id);
              },
              noRowsWidget: Center(
                child: Text(
                  l10n.commonNoresults,
                  style: TextStyle(color: scheme.outline),
                ),
              ),
            ),
          ),
        ),
        const GridStatusBar(),
      ],
    );
  }

  /// Column set — order/format mirrors the web POSTab grid (PO No, Date,
  /// Status, Total, Expected Delivery) plus Supplier for the standalone
  /// list; read-only for now.
  static List<PlutoColumn> _buildColumns(AppLocalizations l10n) {
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
