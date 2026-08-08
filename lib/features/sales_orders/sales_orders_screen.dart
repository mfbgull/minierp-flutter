// Sales orders list screen — a read-only grid over `GET /sales-orders`
// (**bare array**; no search/page params, so sorting and filtering stay
// client-side like the items screen). Rendered with PlutoGrid via the
// shared [PlutoGridScreen] mixin: F2/Enter + double-tap open the SO
// detail, and the keyboard-hint status bar sits beneath the grid. Sits
// in the `/sales` branch's Sales Orders tab (the web app hosts the list
// at `/sales-orders` inside the sales module).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/csv_export.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/so_status.dart';
import '../../data/models/sales_order.dart' show SalesOrder;
import '../../l10n/app_localizations.dart';
import '../../widgets/pluto_grid_screen.dart';
import '../../widgets/status_badge.dart';
import 'sales_order_detail_dialog.dart';
import 'sales_order_form_dialog.dart';
import 'sales_order_providers.dart';

class SalesOrdersScreen extends ConsumerStatefulWidget {
  const SalesOrdersScreen({super.key});

  @override
  ConsumerState<SalesOrdersScreen> createState() => _SalesOrdersScreenState();
}

class _SalesOrdersScreenState extends ConsumerState<SalesOrdersScreen>
    with PlutoGridScreen<SalesOrder, SalesOrdersScreen> {
  @override
  void openRowDetail(int soId) {
    if (!mounted) return;
    showSalesOrderDetailDialog(context, soId: soId);
  }

  @override
  PlutoRow gridRowFor(SalesOrder so) => PlutoRow(
    cells: {
      'id': PlutoCell(value: so.id),
      'soNo': PlutoCell(value: so.soNo),
      'date': PlutoCell(value: so.soDate),
      'customer': PlutoCell(value: so.customerName),
      'status': PlutoCell(value: so.status),
      'total': PlutoCell(value: so.totalAmount),
      'delivery': PlutoCell(value: so.deliveryDate ?? ''),
    },
  );

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(salesOrdersProvider);
    final l10n = AppLocalizations.of(context)!;

    // Keep the grid in sync with provider transitions (loading → data).
    watchGridProvider(salesOrdersProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => showSalesOrderFormDialog(context),
                icon: const Icon(Icons.add, size: 18),
                label: Text(l10n.salesordersNewsalesorder),
              ),
              const SizedBox(width: 4),
              // CSV export — mirrors the returns grids: the pure builder
              // runs here and the shared save helper owns the FilePicker
              // + toast. Disabled until rows are loaded.
              TextButton.icon(
                onPressed:
                    orders.isLoading || (orders.valueOrNull?.isEmpty ?? true)
                    ? null
                    : () => saveCsv(
                        context,
                        suggestedName: csvSuggestedName('sales-orders'),
                        csv: buildSalesOrdersCsv(l10n, orders.valueOrNull!),
                        successMessage: l10n.salesordersExported,
                        errorMessage: l10n.salesordersExportfailed,
                      ),
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: Text(l10n.salesordersExportcsv),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: l10n.commonRefresh,
                icon: const Icon(Icons.refresh),
                onPressed: () => ref.invalidate(salesOrdersProvider),
              ),
            ],
          ),
        ),
        Expanded(child: gridScreenBody(orders, provider: salesOrdersProvider)),
      ],
    );
  }

  /// Column set — order/format mirrors the web SalesOrdersPage grid (SO
  /// No, Date, Customer, Status, Total, Delivery); read-only for now.
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
      textColumn('soNo', l10n.salesordersSono, 110),
      PlutoColumn(
        title: l10n.salesordersDate,
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
      textColumn('customer', l10n.salesordersCustomer, 220),
      PlutoColumn(
        title: l10n.salesordersStatus,
        field: 'status',
        type: PlutoColumnType.text(),
        width: 140,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) => Builder(
          builder: (cellContext) {
            final status = ctx.cell.value as String? ?? '';
            final (color, darkColor) = soStatusColors(status);
            return Align(
              alignment: Alignment.centerLeft,
              child: StatusBadge(
                status: soStatusLabel(
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
        title: l10n.salesordersDelivery,
        field: 'delivery',
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
