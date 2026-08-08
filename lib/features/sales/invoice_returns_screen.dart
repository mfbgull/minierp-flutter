// Invoice returns list screen — a read-only grid over `GET
// /invoices/returns` (**bare array** of `RETURN` stock movements; no
// search/page params, so sorting and filtering stay client-side like the
// items screen). Rendered with PlutoGrid via the shared [PlutoGridScreen]
// mixin: F2/Enter + double-tap open the return detail, and the
// keyboard-hint status bar sits beneath the grid. Hosted as the
// 'Invoice Returns' tab of the sales shell (the web app pairs it with
// `/sales/returns`).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/formatters.dart';
import '../../core/utils/csv_export.dart';
import '../../data/models/sales_return.dart' show SalesReturn;
import '../../l10n/app_localizations.dart';
import '../../widgets/pluto_grid_screen.dart';
import 'invoice_return_detail_dialog.dart';
import 'invoice_return_providers.dart';

class InvoiceReturnsScreen extends ConsumerStatefulWidget {
  const InvoiceReturnsScreen({super.key});

  @override
  ConsumerState<InvoiceReturnsScreen> createState() =>
      _InvoiceReturnsScreenState();
}

class _InvoiceReturnsScreenState extends ConsumerState<InvoiceReturnsScreen>
    with PlutoGridScreen<SalesReturn, InvoiceReturnsScreen> {
  /// Row id → model for the detail dialog — there is no per-row endpoint,
  /// so the dialog renders from the row the grid was built from.
  final Map<int, SalesReturn> _returnsById = {};

  @override
  void openRowDetail(int returnId) {
    if (!mounted) return;
    final salesReturn = _returnsById[returnId];
    if (salesReturn == null) return;
    showInvoiceReturnDetailDialog(context, salesReturn: salesReturn);
  }

  @override
  PlutoRow gridRowFor(SalesReturn salesReturn) {
    // Cache the model for the F2/Enter/double-tap detail path.
    _returnsById[salesReturn.id] = salesReturn;
    return PlutoRow(
      cells: {
        'id': PlutoCell(value: salesReturn.id),
        'returnNo': PlutoCell(value: salesReturn.movementNo),
        'date': PlutoCell(value: salesReturn.returnDate),
        'item': PlutoCell(value: salesReturn.itemName),
        'qty': PlutoCell(value: salesReturn.quantity),
        'unitCost': PlutoCell(value: salesReturn.unitCost),
        'total': PlutoCell(value: salesReturn.returnValue),
        'customer': PlutoCell(value: salesReturn.customerName ?? ''),
        'warehouse': PlutoCell(value: salesReturn.warehouseName),
        'remarks': PlutoCell(value: salesReturn.remarks ?? ''),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final returns = ref.watch(invoiceReturnsProvider);
    final l10n = AppLocalizations.of(context)!;

    // Keep the grid in sync with provider transitions (loading → data).
    watchGridProvider(invoiceReturnsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // CSV export — mirrors the stock ledger dialog: the pure
              // builder runs here and the shared save helper owns the
              // FilePicker + toast. Disabled until rows are loaded.
              TextButton.icon(
                onPressed:
                    returns.isLoading || (returns.valueOrNull?.isEmpty ?? true)
                    ? null
                    : () => saveCsv(
                        context,
                        suggestedName: csvSuggestedName('invoice-returns'),
                        csv: buildInvoiceReturnsCsv(l10n, returns.valueOrNull!),
                        successMessage: l10n.salesreturnsExported,
                        errorMessage: l10n.salesreturnsExportfailed,
                      ),
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: Text(l10n.salesreturnsExportcsv),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: l10n.commonRefresh,
                icon: const Icon(Icons.refresh),
                onPressed: () => ref.invalidate(invoiceReturnsProvider),
              ),
            ],
          ),
        ),
        Expanded(
          child: gridScreenBody(returns, provider: invoiceReturnsProvider),
        ),
      ],
    );
  }

  /// Column set — mirrors the return-history columns the web app shows
  /// (Return No, Date, Item, Qty, Unit Cost, Total, Customer, Warehouse,
  /// Remarks); read-only for now (returns are created from an invoice).
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
      textColumn('returnNo', l10n.salesreturnsReturnno, 120),
      PlutoColumn(
        title: l10n.salesreturnsReturndate,
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
        title: l10n.salesreturnsReturnqty,
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
        title: l10n.fieldsCost,
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
        title: l10n.salesreturnsReturnvalue,
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
      textColumn('customer', l10n.fieldsCustomer, 160),
      textColumn('warehouse', l10n.fieldsWarehouse, 140),
      textColumn('remarks', l10n.fieldsNotes, 180),
    ];
  }
}
