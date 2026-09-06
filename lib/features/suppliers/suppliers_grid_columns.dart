// Column definitions for the Suppliers grid (extracted from
// suppliers_screen.dart, spec 1.3). Contains [buildSupplierColumns] which
// returns the full [PlutoColumn] list.

import 'package:flutter/material.dart';
import 'package:minierp_app/core/theme/status_colors.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/supplier.dart' show Supplier;
import '../../l10n/app_localizations.dart';
import '../../widgets/status_badge.dart';

/// Builds the full set of PlutoGrid columns for the Suppliers grid.
///
/// Column set — order/format mirrors the web SuppliersGrid: Code, Name
/// (+ contact person), Contact Info (phone + email), Payment Terms,
/// Balance (amber when positive / green when ≤ 0), Status, Actions.
///
/// [onOpenRowMenu] is invoked when the ⋮ actions cell is tapped; it
/// receives the cell context and the row's [Supplier] (nullable for
/// safety).
List<PlutoColumn> buildSupplierColumns({
  required AppLocalizations l10n,
  required void Function(BuildContext cellContext, Supplier? supplier)
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
    // Hidden record-id cell (the mixin's id pattern) — never revealed.
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
    // Hidden cell carrying the full Supplier for the actions menu —
    // hidden with the id column in onLoaded.
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
    textColumn('code', l10n.suppliersSuppliercode, 110),
    // Supplier name + contact person sub-line.
    PlutoColumn(
      title: l10n.suppliersSuppliername,
      field: 'name',
      type: PlutoColumnType.text(),
      width: 200,
      readOnly: true,
      enableContextMenu: false,
      renderer: (ctx) {
        final supplier = ctx.cell.row.cells['data']?.value as Supplier?;
        return Builder(
          builder: (cellContext) => Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${ctx.cell.value}',
                overflow: TextOverflow.ellipsis,
                // height keeps the two-line cell inside the 34px row
                // (default line height overflows the grid cell by 1px).
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                ),
              ),
              if (supplier?.contactPerson?.isNotEmpty ?? false)
                Text(
                  supplier!.contactPerson!,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.1,
                    color: Theme.of(
                      cellContext,
                    ).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        );
      },
    ),
    // Contact info (phone + email sub-line, web's Contact Info column).
    PlutoColumn(
      title: l10n.suppliersContactinfo,
      field: 'phone',
      type: PlutoColumnType.text(),
      width: 190,
      readOnly: true,
      enableContextMenu: false,
      renderer: (ctx) {
        final supplier = ctx.cell.row.cells['data']?.value as Supplier?;
        return Builder(
          builder: (cellContext) => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${ctx.cell.value}',
                overflow: TextOverflow.ellipsis,
                // height keeps the two-line cell inside the 34px row
                // (default line height overflows the grid cell by 1px).
                style: const TextStyle(fontSize: 13, height: 1.1),
              ),
              if (supplier?.email?.isNotEmpty ?? false)
                Text(
                  supplier!.email!,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.1,
                    color: Theme.of(
                      cellContext,
                    ).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        );
      },
    ),
    textColumn('terms', l10n.suppliersPaymentterms, 120),
    PlutoColumn(
      title: l10n.suppliersBalance,
      field: 'balance',
      type: PlutoColumnType.number(format: '#,###.00'),
      width: 120,
      readOnly: true,
      textAlign: PlutoColumnTextAlign.end,
      titleTextAlign: PlutoColumnTextAlign.end,
      enableContextMenu: false,
      renderer: (ctx) => Builder(
        builder: (cellContext) {
          final balance = ctx.cell.value as num? ?? 0;
          final isDark = Theme.of(cellContext).brightness == Brightness.dark;
          final color = balance > 0
              ? (isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706))
              : (isDark ? const Color(0xFF4ADE80) : const Color(0xFF15803D));
          return Align(
            alignment: Alignment.centerRight,
            child: Text(
              Formatters.currency(balance),
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          );
        },
      ),
    ),
    PlutoColumn(
      title: l10n.commonStatus,
      field: 'active',
      type: PlutoColumnType.text(),
      width: 110,
      readOnly: true,
      enableContextMenu: false,
      renderer: (ctx) {
        final active = ctx.cell.value == true;
        return Builder(
          builder: (cellContext) => Align(
            alignment: Alignment.centerLeft,
            child: StatusBadge(
              status: active ? l10n.statusActive : l10n.statusInactive,
              color: StatusColors.of(cellContext).active(active),
            ),
          ),
        );
      },
    ),
    // Per-row actions menu — the web's ⋮ dropdown (View/Edit/Delete).
    // A raw Listener opens the menu: PlutoGrid's cell gesture handler
    // competes in the gesture arena and swallows an IconButton/InkWell
    // tap, but a Listener receives pointer events regardless of the
    // arena, so the menu opens reliably (and in widget tests).
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
        final supplier = ctx.cell.row.cells['data']?.value as Supplier?;
        return Builder(
          builder: (cellContext) => Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => onOpenRowMenu(cellContext, supplier),
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