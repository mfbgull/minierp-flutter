import 'package:flutter/material.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:minierp_app/core/theme/app_border_radius.dart';

import '../../core/utils/formatters.dart';
import '../../core/utils/invoice_status.dart';
import '../../data/models/invoice.dart' show Invoice;
import '../../l10n/app_localizations.dart';
import '../../widgets/pluto_grid_screen.dart' show serialGridColumn;
import '../../widgets/status_badge.dart';

/// Column set — dense data-screen conventions (PORTING.md §6), read-only
/// with the id column hidden (it carries the row's invoice id to the
/// double-tap handler). Top-level so it can be imported independently.
///
/// [onOpenRowMenu] is called when the per-row ⋮ actions button is tapped;
/// the caller supplies the callback that actually opens the popup menu.
List<PlutoColumn> buildSalesColumns({
  required AppLocalizations l10n,
  required void Function(BuildContext cellContext, Invoice? invoice)
      onOpenRowMenu,
}) {
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
    serialGridColumn(),
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
    textColumn('invoice_no', l10n.salesInvoiceno, 150),
    PlutoColumn(
      title: l10n.fieldsDate,
      field: 'invoice_date',
      type: PlutoColumnType.text(),
      width: 110,
      readOnly: true,
      enableContextMenu: false,
      renderer: (ctx) => Align(
        alignment: Alignment.centerLeft,
        child: Text(Formatters.date(ctx.cell.value as String? ?? '')),
      ),
    ),
    textColumn('customer_name', l10n.fieldsCustomer, 200),
    PlutoColumn(
      title: l10n.fieldsStatus,
      field: 'status',
      type: PlutoColumnType.text(),
      width: 120,
      readOnly: true,
      enableContextMenu: false,
      renderer: (ctx) => Builder(
        builder: (cellContext) {
          final status = ctx.cell.value as String? ?? '';
          final l10n = AppLocalizations.of(cellContext)!;
          return Align(
            alignment: Alignment.centerLeft,
            child: StatusBadge(
              status: invoiceStatusLabel(l10n, status),
              color: invoiceStatusColor(
                Theme.of(cellContext).colorScheme,
                status,
              ),
            ),
          );
        },
      ),
    ),
    PlutoColumn(
      title: '',
      field: 'override_sale',
      type: PlutoColumnType.text(),
      width: 40,
      readOnly: true,
      enableContextMenu: false,
      enableFilterMenuItem: false,
      enableHideColumnMenuItem: false,
      enableSetColumnsMenuItem: false,
      renderer: (ctx) {
        final isOverride = ctx.cell.value == true || ctx.cell.value == 1;
        if (!isOverride) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.center,
          child: Tooltip(
            message: 'Override Sale',
            child: Icon(
              Icons.warning_amber_rounded,
              size: 16,
              color: Colors.amber.shade700,
            ),
          ),
        );
      },
    ),
    PlutoColumn(
      title: l10n.salesTotalsales,
      field: 'total_amount',
      type: PlutoColumnType.number(format: '#,###.##'),
      width: 120,
      readOnly: true,
      textAlign: PlutoColumnTextAlign.end,
      titleTextAlign: PlutoColumnTextAlign.end,
      enableContextMenu: false,
      renderer: (ctx) => Align(
        alignment: Alignment.centerRight,
        child: Text(
          Formatters.currency(ctx.cell.value as num? ?? 0),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    ),
    PlutoColumn(
      title: l10n.salesTotalpaid,
      field: 'paid_amount',
      type: PlutoColumnType.number(format: '#,###.##'),
      width: 120,
      readOnly: true,
      textAlign: PlutoColumnTextAlign.end,
      titleTextAlign: PlutoColumnTextAlign.end,
      enableContextMenu: false,
      renderer: (ctx) => Align(
        alignment: Alignment.centerRight,
        child: Text(
          Formatters.currency(ctx.cell.value as num? ?? 0),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    ),
    PlutoColumn(
      title: l10n.salesTotaldue,
      field: 'balance_amount',
      type: PlutoColumnType.number(format: '#,###.##'),
      width: 120,
      readOnly: true,
      textAlign: PlutoColumnTextAlign.end,
      titleTextAlign: PlutoColumnTextAlign.end,
      enableContextMenu: false,
      renderer: (ctx) => Align(
        alignment: Alignment.centerRight,
        child: Text(
          Formatters.currency(ctx.cell.value as num? ?? 0),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    ),
    textColumn('created_by', l10n.expensesCreatedby, 130),
    // Per-row actions menu — the ⋮ dropdown (View / Edit / Payment /
    // Print / Delete), same Listener + showMenu pattern as the
    // customers grid. The full Invoice rides in the hidden `data`
    // cell so the menu can guard on status + amounts.
    PlutoColumn(
      title: l10n.customersActions,
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
        final invoice = ctx.cell.row.cells['data']?.value as Invoice?;
        return Builder(
          builder: (cellContext) => Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => onOpenRowMenu(cellContext, invoice),
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

/// Summary strip showing Total Sales / Total Paid / Total Due computed from
/// the filtered invoice rows.
Widget buildSalesSummaryStrip(
  BuildContext context,
  AppLocalizations l10n,
  List<Invoice> rows,
) {
  final scheme = Theme.of(context).colorScheme;
  final totalSales = rows.fold<num>(0, (sum, i) => sum + i.totalAmount);
  final totalPaid = rows.fold<num>(0, (sum, i) => sum + i.paidAmount);
  final totalDue = rows.fold<num>(0, (sum, i) => sum + i.balanceAmount);

  Widget stat(String label, num value, Color color) {
    return Expanded(
      child: Row(
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              Formatters.currency(value),
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: AppBorderRadius.smRadius,
      border: Border.all(color: scheme.outlineVariant),
    ),
    child: Row(
      children: [
        Icon(Icons.receipt_long_outlined, size: 18, color: scheme.primary),
        const SizedBox(width: 14),
        stat(l10n.salesTotalsales, totalSales, scheme.primary),
        stat(l10n.salesTotalpaid, totalPaid, scheme.primary),
        stat(l10n.salesTotaldue, totalDue, scheme.error),
      ],
    ),
  );
}
