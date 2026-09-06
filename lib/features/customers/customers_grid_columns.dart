// Column definitions for the Customers grid (extracted from
// customers_screen.dart, spec 1.3). Contains [buildCustomerColumns] which
// returns the full [PlutoColumn] list, plus the per-cell color helpers
// [utilizationColor] and [balanceColor].

import 'package:flutter/material.dart';
import 'package:minierp_app/core/theme/status_colors.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/customer.dart' show Customer;
import '../../l10n/app_localizations.dart';
import '../../widgets/status_badge.dart';

/// Credit-utilization cell color — web `cell-credit-high` (red ≥90%) /
/// `cell-credit-warn` (amber ≥75%); null = neutral (no credit limit or
/// low utilization).
Color? utilizationColor(
  BuildContext context,
  num utilization,
  num creditLimit,
) {
  if (creditLimit <= 0) return null;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  if (utilization >= 90) {
    return isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);
  }
  if (utilization >= 75) {
    return isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
  }
  return null;
}

/// Balance cell color — web `cell-balance-due` (amber, balance > 0) /
/// `cell-balance-clear` (green, ≤ 0).
Color balanceColor(BuildContext context, num balance) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  if (balance > 0) {
    return isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
  }
  return isDark ? const Color(0xFF4ADE80) : const Color(0xFF15803D);
}

/// Builds the full set of PlutoGrid columns for the Customers grid.
///
/// Column set — order/format mirrors the web CustomersGrid: Code, Name
/// (+ contact person), Contact Info (phone + email), Address, Credit
/// Limit, Current Balance, Credit Utilization, Payment Terms, Status,
/// Actions. Balance/utilization cells carry the web's color coding
/// (due = amber, clear = green, utilization ≥90% red / ≥75% amber).
///
/// [onOpenRowMenu] is invoked when the ⋮ actions cell is tapped; it
/// receives the cell context and the row's [Customer] (nullable for
/// safety).
List<PlutoColumn> buildCustomerColumns({
  required AppLocalizations l10n,
  required void Function(BuildContext cellContext, Customer? customer)
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
    // Hidden cell carrying the full Customer for the actions menu —
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
    textColumn('code', l10n.customersCustomercode, 110),
    // Customer name + contact person sub-line.
    PlutoColumn(
      title: l10n.customersCustomername,
      field: 'name',
      type: PlutoColumnType.text(),
      width: 200,
      readOnly: true,
      enableContextMenu: false,
      renderer: (ctx) {
        final customer = ctx.cell.row.cells['data']?.value as Customer?;
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
              if (customer?.contactPerson?.isNotEmpty ?? false)
                Text(
                  customer!.contactPerson!,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
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
    // Contact info: phone + email sub-line.
    PlutoColumn(
      title: l10n.customersContactinfo,
      field: 'phone',
      type: PlutoColumnType.text(),
      width: 180,
      readOnly: true,
      enableContextMenu: false,
      renderer: (ctx) {
        final email = ctx.cell.row.cells['email']?.value?.toString() ?? '';
        return Builder(
          builder: (cellContext) => Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${ctx.cell.value}',
                overflow: TextOverflow.ellipsis,
                // height keeps the two-line cell inside the 34px row.
                style: const TextStyle(height: 1.1),
              ),
              if (email.isNotEmpty)
                Text(
                  email,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
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
    // Address — up to 3 lines, ellipsized.
    PlutoColumn(
      title: l10n.customersAddress,
      field: 'address',
      type: PlutoColumnType.text(),
      width: 200,
      readOnly: true,
      enableContextMenu: false,
      renderer: (ctx) {
        final lines = '${ctx.cell.value}'
            .split('\n')
            .where((line) => line.isNotEmpty)
            .take(3)
            .toList();
        return Builder(
          builder: (cellContext) => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in lines)
                Text(
                  line,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
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
    // Credit limit — colored by utilization (web getCreditUtilizationClass).
    PlutoColumn(
      title: l10n.customersCreditlimit,
      field: 'creditLimit',
      type: PlutoColumnType.number(format: '#,###.00'),
      width: 120,
      readOnly: true,
      textAlign: PlutoColumnTextAlign.end,
      titleTextAlign: PlutoColumnTextAlign.end,
      enableContextMenu: false,
      renderer: (ctx) {
        final customer = ctx.cell.row.cells['data']?.value as Customer?;
        final limit = (ctx.cell.value as num?) ?? 0;
        final utilization = customer?.creditUtilizationPercent ??
            ((customer?.currentBalance ?? 0) / (limit == 0 ? 1 : limit)) *
                100;
        return Builder(
          builder: (cellContext) {
            final color = utilizationColor(
              cellContext,
              utilization,
              limit,
            );
            return Align(
              alignment: Alignment.centerRight,
              child: Text(
                Formatters.currency(limit),
                style: color == null ? null : TextStyle(color: color),
              ),
            );
          },
        );
      },
    ),
    // Current balance — due (amber) when positive, clear (green) when
    // zero/negative (web getBalanceCellClass).
    PlutoColumn(
      title: l10n.customersCurrentbalance,
      field: 'balance',
      type: PlutoColumnType.number(format: '#,###.00'),
      width: 140,
      readOnly: true,
      textAlign: PlutoColumnTextAlign.end,
      titleTextAlign: PlutoColumnTextAlign.end,
      enableContextMenu: false,
      renderer: (ctx) {
        final balance = (ctx.cell.value as num?) ?? 0;
        return Builder(
          builder: (cellContext) => Align(
            alignment: Alignment.centerRight,
            child: Text(
              Formatters.currency(balance),
              style: TextStyle(
                color: balanceColor(cellContext, balance),
              ),
            ),
          ),
        );
      },
    ),
    // Credit utilization % — N/A when no credit limit; colored ≥90% red,
    // ≥75% amber, else low (web credit-utilization classes).
    PlutoColumn(
      title: l10n.customersCreditutilization,
      field: 'utilization',
      type: PlutoColumnType.number(format: '#,###.00'),
      width: 140,
      readOnly: true,
      textAlign: PlutoColumnTextAlign.end,
      titleTextAlign: PlutoColumnTextAlign.end,
      enableContextMenu: false,
      renderer: (ctx) {
        final customer = ctx.cell.row.cells['data']?.value as Customer?;
        final limit = customer?.creditLimit ?? 0;
        final utilization = (ctx.cell.value as num?) ?? 0;
        return Builder(
          builder: (cellContext) {
            if (limit <= 0) {
              return Align(
                alignment: Alignment.centerRight,
                child: Text(
                  l10n.customersNotapplicable,
                  style: TextStyle(
                    color: Theme.of(
                      cellContext,
                    ).colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            }
            final color = utilizationColor(
              cellContext,
              utilization,
              limit,
            );
            return Align(
              alignment: Alignment.centerRight,
              child: Text(
                // Two decimals like the web (`(value || 0).toFixed(2)`).
                '${utilization.toStringAsFixed(2)}%',
                style: color == null ? null : TextStyle(color: color),
              ),
            );
          },
        );
      },
    ),
    // Payment terms in days (e.g. "14 days").
    PlutoColumn(
      title: l10n.customersPaymenttermsdays,
      field: 'terms',
      type: PlutoColumnType.number(),
      width: 120,
      readOnly: true,
      enableContextMenu: false,
      renderer: (ctx) {
        final days = (ctx.cell.value as num?) ?? 0;
        return Text(l10n.customersDays(days));
      },
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
        final customer = ctx.cell.row.cells['data']?.value as Customer?;
        return Builder(
          builder: (cellContext) => Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => onOpenRowMenu(cellContext, customer),
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