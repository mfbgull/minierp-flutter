import 'package:flutter/material.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:minierp_app/core/theme/app_border_radius.dart';

import '../../core/utils/expense_status.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/expense.dart' show Expense;
import '../../l10n/app_localizations.dart';
import '../../widgets/pluto_grid_screen.dart'
    show serialGridColumn, withSerialCell;
import '../../widgets/status_badge.dart';

/// Column set — dense data-screen conventions (PORTING.md §6), read-only
/// with the id column hidden.
List<PlutoColumn> buildExpenseColumns({
  required AppLocalizations l10n,
  required void Function(BuildContext cellContext, Expense? expense)
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
    textColumn('expense_no', l10n.expensesExpenseno, 140),
    PlutoColumn(
      title: l10n.fieldsDate,
      field: 'expense_date',
      type: PlutoColumnType.text(),
      width: 110,
      readOnly: true,
      enableContextMenu: false,
      renderer: (ctx) => Align(
        alignment: Alignment.centerLeft,
        child: Text(Formatters.date(ctx.cell.value as String? ?? '')),
      ),
    ),
    textColumn('category', l10n.fieldsCategory, 140),
    textColumn('description', l10n.expensesDescription, 220),
    textColumn('vendor', l10n.expensesVendor, 140),
    textColumn('reference_no', l10n.expensesReferenceno, 120),
    textColumn('payment_method', l10n.expensesPaymentmethod, 140),
    textColumn('project', l10n.expensesProject, 110),
    PlutoColumn(
      title: l10n.fieldsAmount,
      field: 'amount',
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
              status: expenseStatusLabel(l10n, status),
              color: expenseStatusColor(
                  Theme.of(cellContext).colorScheme, status),
            ),
          );
        },
      ),
    ),
    textColumn('created_by', l10n.expensesCreatedby, 130),
    PlutoColumn(
      title: l10n.commonActions,
      field: 'actions',
      frozen: PlutoColumnFrozen.end,
      type: PlutoColumnType.text(),
      width: 64,
      readOnly: true,
      enableContextMenu: false,
      enableFilterMenuItem: false,
      enableHideColumnMenuItem: false,
      enableSetColumnsMenuItem: false,
      renderer: (ctx) {
        final expense = ctx.cell.row.cells['data']?.value as Expense?;
        return Builder(
          builder: (cellContext) => Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => onOpenRowMenu(cellContext, expense),
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

/// Grid field → server sort column (whitelist in sqlSanitizer.ts).
String? expenseSortColumnFor(String field) {
  switch (field) {
    case 'expense_no':
      return 'e.expense_no';
    case 'expense_date':
      return 'e.expense_date';
    case 'category':
      return 'e.expense_category';
    case 'amount':
      return 'e.amount';
    case 'status':
      return 'e.status';
    case 'vendor':
      return 'e.vendor_name';
    case 'payment_method':
      return 'e.payment_method';
    case 'project':
      return 'e.project';
    case 'created_by':
      return 'e.created_at';
    default:
      return null;
  }
}

/// Builds a PlutoRow for an [Expense] at the given [index], wrapping it
/// with the serial-number cell.
PlutoRow buildExpenseRow(Expense expense, int index) => withSerialCell(
  PlutoRow(
    cells: {
      'data': PlutoCell(value: expense),
      'id': PlutoCell(value: expense.id),
      'expense_no': PlutoCell(value: expense.expenseNo),
      'expense_date': PlutoCell(value: expense.expenseDate),
      'category': PlutoCell(value: expense.expenseCategory),
      'description': PlutoCell(value: expense.description ?? ''),
      'vendor': PlutoCell(value: expense.vendorName ?? ''),
      'reference_no': PlutoCell(value: expense.referenceNo ?? ''),
      'payment_method': PlutoCell(value: expense.paymentMethod ?? ''),
      'project': PlutoCell(value: expense.project ?? ''),
      'amount': PlutoCell(value: expense.amount),
      'status': PlutoCell(value: expense.status),
      'created_by': PlutoCell(value: expense.createdByName ?? ''),
    },
  ),
  index,
);

/// Summary strip showing total amount and count for the filtered expenses.
Widget buildExpensesSummaryStrip(
  BuildContext context,
  AppLocalizations l10n,
  List<Expense> rows,
) {
  final scheme = Theme.of(context).colorScheme;
  final total = rows.fold<num>(0, (sum, e) => sum + e.amount);
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
        const SizedBox(width: 8),
        Text(l10n.commonTotal, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(width: 6),
        Text(
          Formatters.currency(total),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: scheme.primary,
          ),
        ),
        const SizedBox(width: 14),
        Text(
          '${rows.length} ${l10n.expensesCount}',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    ),
  );
}
