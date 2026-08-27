// Stock ledger + invoice/purchase returns + sales/purchase orders CSV
// export.
//
// The builders are pure functions (no context, no plugins) so the row
// logic is unit-testable in isolation; the save helper owns the platform
// interaction (FilePicker save dialog + toast feedback).
// - [buildStockLedgerCsv] mirrors the ledger dialog table: signed
//   quantity → In/Out columns, Balance = running total after each
//   movement (oldest-first walk of the newest-first API list).
// - [buildInvoiceReturnsCsv] mirrors the invoice-returns grid columns.
// - [buildPurchaseReturnsCsv] mirrors the purchase-returns grid columns.
// - [buildSalesOrdersCsv] mirrors the sales-orders grid columns.
// - [buildPurchaseOrdersCsv] mirrors the purchase-orders grid columns.
// - [buildQuotationsCsv] mirrors the quotations grid columns.
// - [buildInvoicesCsv] mirrors the sales-invoices grid columns.
// - [buildExpensesCsv] mirrors the expenses grid columns.
//
// All grid-style builders share the same shape — a localized header row
// followed by one row per record — so every builder routes through the
// parameterized [_buildGridCsv] helper, passing its headers and a
// per-record row mapping (the ledger/returns/production/BOM builders
// keep any precomputed values — e.g. running balances — captured by
// their row mapper).
//
// CSV-injection hardening: user-controlled string cells (doc numbers,
// names, remarks, …) are run through [sanitizeCsvCell], which strips
// leading spreadsheet-formula characters so a value typed as `=cmd(...)`
// cannot execute when the file is opened in a spreadsheet app. Computed
// numeric cells (qty/cost/total/balance) are left untouched — a negative
// balance must keep its minus sign.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/models/activity_log.dart' show ActivityLog;
import '../../data/models/bom.dart' show Bom;
import '../../data/models/expense.dart' show Expense;
import '../../data/models/invoice.dart' show Invoice;
import '../../data/models/owner_equity.dart'
    show OwnerCapitalEntry, OwnerWithdrawal;
import '../../data/models/production.dart' show Production;
import '../../data/models/purchase_order.dart' show PurchaseOrder;
import '../../data/models/purchase_return.dart' show PurchaseReturn;
import '../../data/models/quotation.dart' show Quotation;
import '../../data/models/report.dart'
    show
        ApAgingReport,
        ArAgingReport,
        BalanceSheetReport,
        BatchTraceabilityReport,
        CashFlowReport,
        CashReconciliation,
        CustomerStatementRow,
        DSOMetric,
        ExpiryReportRow,
        GeneralLedgerRow,
        ProfitLossReport,
        TopDebtorRow,
        TrialBalanceReport;
import '../../data/models/sales_order.dart' show SalesOrder;
import '../../data/models/sales_return.dart' show SalesReturn;
import '../../data/models/stock_movement.dart' show StockMovement;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import 'formatters.dart';
import 'cash_movement_labels.dart';
import 'expense_status.dart';
import 'invoice_status.dart';
import 'movement_type_label.dart';
import 'po_status.dart';
import 'purchase_return_type.dart';
import 'quotation_status.dart';
import 'so_status.dart';

/// Strips leading spreadsheet-formula characters (`=`, `+`, `-`, `@`)
/// from a user-controlled cell value (CSV/formula-injection hardening).
/// The rest of the value is preserved verbatim — e.g. `=1+1` → `1+1`,
/// `+HYPERLINK(...)` → `HYPERLINK(...)`. Values not starting with a
/// formula character are returned unchanged.
///
/// Tradeoff (deliberate): a user text that *legitimately* starts with a
/// hyphen, e.g. an item name like `-bolts`, also loses its leading `-`.
/// Stripping — rather than quoting/prefixing — is what the product asked
/// for, and hyphens at the start of doc numbers/names are not a real
/// pattern in this domain; the alternative (prefixing a `'`) would be
/// the choice if that ever becomes a concern.
String sanitizeCsvCell(String value) {
  var start = 0;
  while (start < value.length) {
    final c = value.codeUnitAt(start);
    if (c == 0x3D /* = */ ||
        c == 0x2B /* + */ ||
        c == 0x2D /* - */ ||
        c == 0x40 /* @ */ ) {
      start++;
    } else {
      break;
    }
  }
  return start == 0 ? value : value.substring(start);
}

/// The running balance after each movement — keyed by movement id. The
/// API returns newest-first, so walk the reversed (oldest-first) list.
Map<int, num> stockLedgerBalances(List<StockMovement> movements) {
  final balances = <int, num>{};
  var running = 0.0;
  for (final m in movements.reversed) {
    running += m.quantity;
    balances[m.id] = running;
  }
  return balances;
}

/// Builds the CSV text for [movements] (newest-first display, matching
/// the ledger dialog table): Date | Type | Reference | Warehouse | In |
/// Out | Balance.
String buildStockLedgerCsv(
  AppLocalizations l10n,
  List<StockMovement> movements,
) {
  final balances = stockLedgerBalances(movements);
  return _buildGridCsv(
    [
      l10n.commonDate,
      l10n.inventoryStockledgerType,
      l10n.fieldsReference,
      l10n.fieldsWarehouse,
      l10n.inventoryStockledgerIn,
      l10n.inventoryStockledgerOut,
      l10n.inventoryStockledgerBalance,
    ],
    movements,
    (m) {
      final qty = m.quantity;
      final inQty = qty > 0 ? qty : null;
      final outQty = qty < 0 ? -qty : null;
      return [
        m.movementDate.isEmpty ? '—' : Formatters.date(m.movementDate),
        sanitizeCsvCell(movementTypeLabel(l10n, m.movementType)),
        sanitizeCsvCell(m.referenceDocNo ?? '—'),
        sanitizeCsvCell(m.warehouseCode ?? '—'),
        inQty == null ? '—' : Formatters.number(inQty),
        outQty == null ? '—' : Formatters.number(outQty),
        Formatters.number(balances[m.id] ?? 0),
      ];
    },
  );
}

/// Builds the CSV text for the invoice-returns grid (Return No | Date |
/// Item | Qty | Unit Cost | Total | Customer | Warehouse | Remarks —
/// mirroring the grid's columns).
String buildInvoiceReturnsCsv(
  AppLocalizations l10n,
  List<SalesReturn> returns,
) {
  return _buildGridCsv(
    [
      l10n.salesreturnsReturnno,
      l10n.salesreturnsReturndate,
      l10n.fieldsItem,
      l10n.salesreturnsReturnqty,
      l10n.fieldsCost,
      l10n.salesreturnsReturnvalue,
      l10n.fieldsCustomer,
      l10n.fieldsWarehouse,
      l10n.fieldsNotes,
    ],
    returns,
    (r) => [
      sanitizeCsvCell(r.movementNo.isEmpty ? '—' : r.movementNo),
      r.returnDate.isEmpty ? '—' : Formatters.date(r.returnDate),
      sanitizeCsvCell(r.itemName.isEmpty ? '—' : r.itemName),
      Formatters.number(r.quantity),
      Formatters.currency(r.unitCost),
      Formatters.currency(r.returnValue),
      sanitizeCsvCell(
        (r.customerName?.isEmpty ?? true) ? '—' : r.customerName!,
      ),
      sanitizeCsvCell(r.warehouseName.isEmpty ? '—' : r.warehouseName),
      sanitizeCsvCell((r.remarks?.isEmpty ?? true) ? '—' : r.remarks!),
    ],
  );
}

/// Builds the CSV text for the purchase-returns grid (Return No | Date |
/// Reference | Qty | Value | Type | Status — mirroring the grid's
/// columns; the Type/Status columns use the same localized badge labels
/// as the grid).
String buildPurchaseReturnsCsv(
  AppLocalizations l10n,
  List<PurchaseReturn> returns,
) {
  return _buildGridCsv(
    [
      l10n.purchasesReturnno,
      l10n.purchasesReturndate,
      l10n.fieldsReference,
      l10n.purchasesReturnqty,
      l10n.purchasesReturnvalue,
      l10n.purchasesReturntype,
      l10n.fieldsStatus,
    ],
    returns,
    (r) => [
      sanitizeCsvCell(r.returnNo.isEmpty ? '—' : r.returnNo),
      r.returnDate.isEmpty ? '—' : Formatters.date(r.returnDate),
      sanitizeCsvCell(r.sourceNo.isEmpty ? '—' : r.sourceNo),
      Formatters.number(r.totalQty),
      Formatters.currency(r.totalAmount),
      sanitizeCsvCell(returnTypeLabel(l10n, r.returnType)),
      sanitizeCsvCell(r.status.isEmpty ? '—' : r.status),
    ],
  );
}

/// The shared date-stamped suggested filename for an export —
/// `<stem>-<yyyy-mm-dd>.csv`, e.g. `sales-orders-2026-08-08.csv`.
String csvSuggestedName(String stem) =>
    '$stem-${DateTime.now().toIso8601String().split('T').first}.csv';

/// Builds the CSV text for the sales-orders grid (SO # | Date | Customer
/// | Status | Total | Delivery — mirroring the grid's columns; the
/// Status column uses the same localized label as the grid's badge).
String buildSalesOrdersCsv(AppLocalizations l10n, List<SalesOrder> orders) {
  return _buildGridCsv(
    [
      l10n.salesordersSono,
      l10n.salesordersDate,
      l10n.salesordersCustomer,
      l10n.salesordersStatus,
      l10n.commonTotal,
      l10n.salesordersDelivery,
    ],
    orders,
    (o) => [
      sanitizeCsvCell(o.soNo.isEmpty ? '—' : o.soNo),
      o.soDate.isEmpty ? '—' : Formatters.date(o.soDate),
      sanitizeCsvCell(o.customerName.isEmpty ? '—' : o.customerName),
      sanitizeCsvCell(soStatusLabel(l10n, o.status)),
      Formatters.currency(o.totalAmount),
      (o.deliveryDate?.isEmpty ?? true)
          ? '—'
          : Formatters.date(o.deliveryDate!),
    ],
  );
}

/// Builds the CSV text for the purchase-orders grid (PO No | Date |
/// Supplier | Status | Total | Expected Delivery — mirroring the grid's
/// columns; the Status column uses the same localized label as the
/// grid's badge).
String buildPurchaseOrdersCsv(
  AppLocalizations l10n,
  List<PurchaseOrder> orders,
) {
  return _buildGridCsv(
    [
      l10n.purchaseordersPono,
      l10n.commonDate,
      l10n.purchasesSuppliercol,
      l10n.commonStatus,
      l10n.commonTotal,
      l10n.purchaseordersExpecteddelivery,
    ],
    orders,
    (o) => [
      sanitizeCsvCell(o.poNo.isEmpty ? '—' : o.poNo),
      o.poDate.isEmpty ? '—' : Formatters.date(o.poDate),
      sanitizeCsvCell(o.supplierName.isEmpty ? '—' : o.supplierName),
      sanitizeCsvCell(poStatusLabel(l10n, o.status)),
      Formatters.currency(o.totalAmount),
      (o.expectedDeliveryDate?.isEmpty ?? true)
          ? '—'
          : Formatters.date(o.expectedDeliveryDate!),
    ],
  );
}

/// Builds the CSV text for the quotations grid (Quotation # | Date |
/// Customer | Status | Total | Expiry — mirroring the grid's columns;
/// the Status column uses the same localized label as the grid's badge).
String buildQuotationsCsv(AppLocalizations l10n, List<Quotation> quotations) {
  return _buildGridCsv(
    [
      l10n.quotationsQuotation,
      l10n.quotationsDate,
      l10n.quotationsCustomer,
      l10n.quotationsStatus,
      l10n.commonTotal,
      l10n.quotationsExpiry,
    ],
    quotations,
    (q) => [
      sanitizeCsvCell(q.quotationNo.isEmpty ? '—' : q.quotationNo),
      q.quotationDate.isEmpty ? '—' : Formatters.date(q.quotationDate),
      sanitizeCsvCell(q.customerName.isEmpty ? '—' : q.customerName),
      sanitizeCsvCell(quotationStatusLabel(l10n, q.status)),
      Formatters.currency(q.totalAmount),
      (q.expiryDate?.isEmpty ?? true) ? '—' : Formatters.date(q.expiryDate!),
    ],
  );
}

/// Builds the CSV text for the sales-invoices grid (Invoice No | Date |
/// Customer | Status | Total | Paid | Due | Created By — mirroring the
/// grid's columns; the Status column uses the same localized label as
/// the grid's badge).
/// Builds the CSV text for the expenses grid (Expense No | Date |
/// Category | Description | Vendor | Reference No | Payment Method |
/// Activity-log export — Timestamp | User | Action | Entity | Description
/// | Level, mirroring the activity grid's columns (description and the
/// free-text fields go through the CSV-injection sanitizer).
String buildActivityLogCsv(AppLocalizations l10n, List<ActivityLog> logs) {
  return _buildGridCsv(
    [
      l10n.activitylogTimestamp,
      l10n.activitylogUser,
      l10n.activitylogAction,
      l10n.activitylogEntity,
      l10n.commonDescription,
      l10n.activitylogLevel,
    ],
    logs,
    (log) => [
      sanitizeCsvCell(log.createdAt.isEmpty ? '—' : log.createdAt),
      sanitizeCsvCell(log.username?.isEmpty ?? true ? '—' : log.username!),
      sanitizeCsvCell(log.action.isEmpty ? '—' : log.action),
      sanitizeCsvCell(log.entityLabel),
      sanitizeCsvCell(log.description.isEmpty ? '—' : log.description),
      sanitizeCsvCell(log.logLevel.isEmpty ? '—' : log.logLevel),
    ],
  );
}

/// Project | Amount | Status | Created By — mirroring the grid's
/// columns; the Status column uses the same localized label as the
/// grid's badge).
String buildExpensesCsv(AppLocalizations l10n, List<Expense> expenses) {
  return _buildGridCsv(
    [
      l10n.expensesExpenseno,
      l10n.fieldsDate,
      l10n.fieldsCategory,
      l10n.expensesDescription,
      l10n.expensesVendor,
      l10n.expensesReferenceno,
      l10n.expensesPaymentmethod,
      l10n.expensesProject,
      l10n.fieldsAmount,
      l10n.fieldsStatus,
      l10n.expensesCreatedby,
    ],
    expenses,
    (e) => [
      sanitizeCsvCell(e.expenseNo.isEmpty ? '—' : e.expenseNo),
      e.expenseDate.isEmpty ? '—' : Formatters.date(e.expenseDate),
      sanitizeCsvCell(e.expenseCategory.isEmpty ? '—' : e.expenseCategory),
      sanitizeCsvCell((e.description?.isEmpty ?? true) ? '—' : e.description!),
      sanitizeCsvCell((e.vendorName?.isEmpty ?? true) ? '—' : e.vendorName!),
      sanitizeCsvCell((e.referenceNo?.isEmpty ?? true) ? '—' : e.referenceNo!),
      sanitizeCsvCell(
        (e.paymentMethod?.isEmpty ?? true) ? '—' : e.paymentMethod!,
      ),
      sanitizeCsvCell((e.project?.isEmpty ?? true) ? '—' : e.project!),
      Formatters.currency(e.amount),
      sanitizeCsvCell(expenseStatusLabel(l10n, e.status)),
      sanitizeCsvCell(
        (e.createdByName?.isEmpty ?? true) ? '—' : e.createdByName!,
      ),
    ],
  );
}

String buildOwnerCapitalCsv(
  AppLocalizations l10n,
  List<OwnerCapitalEntry> entries,
) {
  return _buildGridCsv(
    [
      l10n.equityCapitalno,
      l10n.fieldsDate,
      l10n.expensesPaymentmethod,
      l10n.fieldsNote,
      l10n.fieldsAmount,
      l10n.fieldsStatus,
      l10n.expensesCreatedby,
    ],
    entries,
    (e) => [
      sanitizeCsvCell(e.capitalNo.isEmpty ? '—' : e.capitalNo),
      e.capitalDate.isEmpty ? '—' : Formatters.date(e.capitalDate),
      sanitizeCsvCell((e.paymentMethod?.isEmpty ?? true) ? '—' : e.paymentMethod!),
      sanitizeCsvCell((e.note?.isEmpty ?? true) ? '—' : e.note!),
      Formatters.currency(e.amount),
      sanitizeCsvCell(e.status),
      sanitizeCsvCell((e.createdByName?.isEmpty ?? true) ? '—' : e.createdByName!),
    ],
  );
}

String buildOwnerWithdrawalsCsv(
  AppLocalizations l10n,
  List<OwnerWithdrawal> rows,
) {
  return _buildGridCsv(
    [
      l10n.equityWithdrawalno,
      l10n.fieldsDate,
      l10n.equityKind,
      l10n.fieldsAmount,
      l10n.equityItems,
      l10n.expensesPaymentmethod,
      l10n.fieldsNote,
      l10n.fieldsStatus,
      l10n.expensesCreatedby,
    ],
    rows,
    (r) => [
      sanitizeCsvCell(r.withdrawalNo.isEmpty ? '—' : r.withdrawalNo),
      r.withdrawalDate.isEmpty ? '—' : Formatters.date(r.withdrawalDate),
      sanitizeCsvCell(r.kind == 'goods' ? l10n.equityKindgoods : l10n.equityKindcash),
      Formatters.currency(r.amount),
      r.kind == 'goods' ? r.itemLineCount.toString() : '—',
      sanitizeCsvCell((r.paymentMethod?.isEmpty ?? true) ? '—' : r.paymentMethod!),
      sanitizeCsvCell((r.note?.isEmpty ?? true) ? '—' : r.note!),
      sanitizeCsvCell(r.status),
      sanitizeCsvCell((r.createdByName?.isEmpty ?? true) ? '—' : r.createdByName!),
    ],
  );
}

String buildArAgingCsv(AppLocalizations l10n, ArAgingReport report) {
  return _buildGridCsv(
    [
      l10n.fieldsCustomer,
      l10n.fieldsCustomerCode,
      l10n.reportsTotaloutstanding,
      l10n.reportsCurrent,
      l10n.reportsDays1_30,
      l10n.reportsDays31_60,
      l10n.reportsDays61_90,
      l10n.reportsDays90plus,
    ],
    report.buckets,
    (b) => [
      sanitizeCsvCell(b.customerName.isEmpty ? '—' : b.customerName),
      sanitizeCsvCell(b.customerCode.isEmpty ? '—' : b.customerCode),
      Formatters.currency(b.totalOutstanding),
      Formatters.currency(b.currentAmount),
      Formatters.currency(b.days1_30),
      Formatters.currency(b.days31_60),
      Formatters.currency(b.days61_90),
      Formatters.currency(b.daysOver90),
    ],
  );
}

String buildApAgingCsv(AppLocalizations l10n, ApAgingReport report) {
  return _buildGridCsv(
    [
      l10n.fieldsSupplier,
      'Supplier Code',
      l10n.reportsTotaloutstanding,
      l10n.reportsCurrent,
      l10n.reportsDays1_30,
      l10n.reportsDays31_60,
      l10n.reportsDays61_90,
      l10n.reportsDays90plus,
    ],
    report.buckets,
    (b) => [
      sanitizeCsvCell(b.supplierName.isEmpty ? '—' : b.supplierName),
      sanitizeCsvCell(b.supplierCode.isEmpty ? '—' : b.supplierCode),
      Formatters.currency(b.totalOutstanding),
      Formatters.currency(b.currentAmount),
      Formatters.currency(b.days1_30),
      Formatters.currency(b.days31_60),
      Formatters.currency(b.days61_90),
      Formatters.currency(b.daysOver90),
    ],
  );
}

String buildBalanceSheetCsv(
  AppLocalizations l10n,
  BalanceSheetReport report,
) {
  final buf = StringBuffer();
  buf.writeln('Balance Sheet,,${Formatters.date(report.asOfDate)}');
  buf.writeln();
  buf.writeln('Assets,,');
  buf.writeln('Inventory,,${Formatters.currency(report.assets.inventory)}');
  buf.writeln('Accounts Receivable,,${Formatters.currency(report.assets.accountsReceivable)}');
  buf.writeln('Cash,,${Formatters.currency(report.assets.cash)}');
  buf.writeln('${l10n.commonTotal},,${Formatters.currency(report.assets.total)}');
  buf.writeln();
  buf.writeln('Liabilities,,');
  buf.writeln('Accounts Payable,,${Formatters.currency(report.liabilities.accountsPayable)}');
  buf.writeln('${l10n.commonTotal},,${Formatters.currency(report.liabilities.total)}');
  buf.writeln();
  buf.writeln('Equity,,');
  buf.writeln('Opening Retained Earnings,,${Formatters.currency(report.equity.openingRetainedEarnings)}');
  if (report.equity.ownerCapital != null) {
    buf.writeln('Owner Capital,,${Formatters.currency(report.equity.ownerCapital!)}');
  }
  if (report.equity.ownerDrawings != null) {
    buf.writeln('Owner Drawings,,${Formatters.currency(report.equity.ownerDrawings!)}');
  }
  buf.writeln('Net Income (YTD),,${Formatters.currency(report.equity.netIncomeYtd)}');
  buf.writeln('Revenue (YTD),,${Formatters.currency(report.equity.revenueYtd)}');
  buf.writeln('COGS (YTD),,${Formatters.currency(report.equity.cogsYtd)}');
  buf.writeln('Expenses (YTD),,${Formatters.currency(report.equity.expensesYtd)}');
  buf.writeln('${l10n.commonTotal},,${Formatters.currency(report.equity.total)}');
  buf.writeln();
  buf.writeln('Total Assets,,${Formatters.currency(report.totals.totalAssets)}');
  buf.writeln('Total Liabilities & Equity,,${Formatters.currency(report.totals.totalLiabAndEquity)}');
  buf.writeln('Balanced,,${report.totals.balanced ? "Yes" : "No"}');
  return buf.toString();
}

/// Builds the CSV text for the DSO report — a Metric | Value table
/// mirroring the web page's export (DSO days, period, total sales,
/// total AR, avg invoice value).
String buildDsoCsv(AppLocalizations l10n, DSOMetric metric) {
  return _buildGridCsv(
    [l10n.fieldsMetric, l10n.fieldsValue],
    [
      (l10n.reportsDsodays, Formatters.number(metric.dso)),
      (
        l10n.reportsPeriod,
        metric.startDate.isEmpty
            ? '—'
            : '${Formatters.date(metric.startDate)} ${l10n.commonTo} ${Formatters.date(metric.endDate)}',
      ),
      (l10n.reportsTotalsales, Formatters.currency(metric.totalSales)),
      (l10n.reportsTotalar, Formatters.currency(metric.totalAR)),
      (
        l10n.reportsAvginvoicevalue,
        Formatters.currency(metric.avgInvoiceValue),
      ),
    ],
    (row) => [sanitizeCsvCell(row.$1), row.$2],
  );
}

/// Builds the CSV text for the cash flow report — a Metric | Value
/// table (total inflow, total outflow, net cash flow).
String buildCashFlowCsv(AppLocalizations l10n, CashFlowReport report) {
  final summary = _buildGridCsv(
    [l10n.fieldsMetric, l10n.fieldsValue],
    [
      (l10n.reportsTotalinflow, Formatters.currency(report.totalInflow)),
      (l10n.reportsTotaloutflow, Formatters.currency(report.totalOutflow)),
      (l10n.reportsNetcashflow, Formatters.currency(report.netCashFlow)),
    ],
    (row) => [sanitizeCsvCell(row.$1), row.$2],
  );
  if (report.movements.isEmpty) return summary;
  final movements = _buildGridCsv(
    [
      l10n.commonDate,
      l10n.fieldsType,
      l10n.fieldsReference,
      l10n.paymentsParty,
      l10n.expensesPaymentmethod,
      l10n.fieldsNotes,
      l10n.fieldsAmount,
    ],
    report.movements,
    (m) => [
      sanitizeCsvCell(m.date),
      sanitizeCsvCell(cashMovementLabel(l10n, m.type)),
      sanitizeCsvCell(m.reference),
      sanitizeCsvCell(m.party),
      sanitizeCsvCell(m.method),
      sanitizeCsvCell(m.description),
      // Signed numeric cell — keep the sign; not injection-safe concern.
      m.amount,
    ],
  );
  return '$summary\n$movements';
}

/// Builds the CSV text for the cash reconciliation — Account | Opening
/// | Inflow | Outflow | Expected | Counted | Variance | Notes, one row
/// per account, then a Total row mirroring the screen's grid.
String buildCashReconciliationCsv(
  AppLocalizations l10n,
  CashReconciliation report,
) {
  final rows = [
    for (final a in report.accounts)
      [
        sanitizeCsvCell(a.name.isEmpty ? '—' : a.name),
        Formatters.currency(a.openingBalance),
        Formatters.currency(a.inflow),
        Formatters.currency(a.outflow),
        Formatters.currency(a.expectedBalance),
        a.countedBalance == null ? '—' : Formatters.currency(a.countedBalance!),
        a.variance == null ? '—' : Formatters.currency(a.variance!),
        sanitizeCsvCell((a.notes?.isEmpty ?? true) ? '—' : a.notes!),
      ],
    [
      l10n.commonTotal,
      Formatters.currency(report.totals.opening),
      Formatters.currency(report.totals.inflow),
      Formatters.currency(report.totals.outflow),
      Formatters.currency(report.totals.closing),
      Formatters.currency(
        report.accounts.fold<num>(0, (s, a) => s + (a.countedBalance ?? 0)),
      ),
      Formatters.currency(
        report.accounts.fold<num>(0, (s, a) => s + (a.countedBalance ?? 0)) -
            report.totals.closing,
      ),
      '',
    ],
  ];
  return _buildGridCsv(
    [
      l10n.fieldsAccount,
      l10n.cashreconOpening,
      l10n.cashreconInflow,
      l10n.cashreconOutflow,
      l10n.cashreconExpected,
      l10n.cashreconCounted,
      l10n.cashreconVariance,
      l10n.cashreconNotes,
    ],
    rows,
    (row) => row,
  );
}

/// Builds the CSV text for the profit & loss report — a Metric | Value
/// table (revenue, COGS, gross profit, expenses, net profit, margins).
String buildProfitLossCsv(AppLocalizations l10n, ProfitLossReport report) {
  return _buildGridCsv(
    [l10n.fieldsMetric, l10n.fieldsValue],
    [
      (l10n.reportsTotalrevenue, Formatters.currency(report.totalRevenue)),
      (l10n.reportsTotalcogs, Formatters.currency(report.totalCogs)),
      (l10n.reportsGrossprofit, Formatters.currency(report.grossProfit)),
      (l10n.reportsTotalexpenses, Formatters.currency(report.totalExpenses)),
      (l10n.reportsNetprofit, Formatters.currency(report.netProfit)),
      (
        l10n.reportsGrossprofitmargin,
        '${Formatters.number(report.grossProfitMargin)}%',
      ),
      (
        l10n.reportsNetprofitmargin,
        '${Formatters.number(report.netProfitMargin)}%',
      ),
    ],
    (row) => [sanitizeCsvCell(row.$1), row.$2],
  );
}

/// Builds the CSV text for the top-debtors report (Customer | Code |
/// Outstanding | Invoiced | Invoice Count — mirroring the grid's
/// columns).
String buildTopDebtorsCsv(AppLocalizations l10n, List<TopDebtorRow> rows) {
  return _buildGridCsv(
    [
      l10n.fieldsCustomer,
      l10n.fieldsCustomerCode,
      l10n.reportsTotaloutstanding,
      l10n.reportsTotalinvoiced,
      l10n.reportsInvoicecount,
    ],
    rows,
    (r) => [
      sanitizeCsvCell(r.customerName.isEmpty ? '—' : r.customerName),
      sanitizeCsvCell(r.customerCode.isEmpty ? '—' : r.customerCode),
      Formatters.currency(r.totalOutstanding),
      Formatters.currency(r.totalInvoiced),
      Formatters.number(r.invoiceCount),
    ],
  );
}

/// Builds the CSV text for the customer statements report (Customer |
/// Code | Opening Balance | Total Debits | Total Credits | Closing
/// Balance — mirroring the grid's columns).
String buildCustomerStatementsCsv(
  AppLocalizations l10n,
  List<CustomerStatementRow> rows,
) {
  return _buildGridCsv(
    [
      l10n.fieldsCustomer,
      l10n.fieldsCustomerCode,
      l10n.reportsOpeningbalance,
      l10n.reportsTotaldebits,
      l10n.reportsTotalcredits,
      l10n.reportsClosingbalance,
    ],
    rows,
    (r) => [
      sanitizeCsvCell(r.customerName.isEmpty ? '—' : r.customerName),
      sanitizeCsvCell(r.customerCode.isEmpty ? '—' : r.customerCode),
      Formatters.currency(r.openingBalance),
      Formatters.currency(r.totalDebits),
      Formatters.currency(r.totalCredits),
      Formatters.currency(r.closingBalance),
    ],
  );
}

String buildInvoicesCsv(AppLocalizations l10n, List<Invoice> invoices) {
  return _buildGridCsv(
    [
      l10n.salesInvoiceno,
      l10n.fieldsDate,
      l10n.fieldsCustomer,
      l10n.fieldsStatus,
      'Override',
      l10n.salesTotalsales,
      l10n.salesTotalpaid,
      l10n.salesTotaldue,
      l10n.expensesCreatedby,
    ],
    invoices,
    (i) => [
      sanitizeCsvCell(i.invoiceNo.isEmpty ? '—' : i.invoiceNo),
      i.invoiceDate.isEmpty ? '—' : Formatters.date(i.invoiceDate),
      sanitizeCsvCell(
        (i.customerName?.isEmpty ?? true) ? '—' : i.customerName!,
      ),
      sanitizeCsvCell(invoiceStatusLabel(l10n, i.status)),
      i.overrideSale ? 'Yes' : '',
      Formatters.currency(i.totalAmount),
      Formatters.currency(i.paidAmount),
      Formatters.currency(i.balanceAmount),
      sanitizeCsvCell(
        (i.createdByUsername?.isEmpty ?? true) ? '—' : i.createdByUsername!,
      ),
    ],
  );
}

/// Parameterized grid-style CSV builder shared by every export: emits
/// [headers] followed by one row per [items] entry, mapped by [rowFor].
/// The per-record mapping keeps each builder's type-specific cell
/// logic; the header-row + encode tail is shared here.
String _buildGridCsv<T>(
  List<String> headers,
  List<T> items,
  List<dynamic> Function(T) rowFor,
) => Csv().encode([headers, for (final item in items) rowFor(item)]);

/// Prompts for a save location via the platform file picker and writes
/// [csv] to the chosen path. Shows a success toast on completion and an
/// error toast on failure (PORTING.md §9). Returns the save path, or
/// null when the user cancels or an error occurs.
Future<String?> saveCsv(
  BuildContext context, {
  required String suggestedName,
  required String csv,
  required String successMessage,
  required String errorMessage,
}) async {
  final bytes = Uint8List.fromList(utf8.encode(csv));
  try {
    final path = await FilePicker.saveFile(
      dialogTitle: suggestedName,
      fileName: suggestedName,
      type: FileType.custom,
      allowedExtensions: ['csv'],
      bytes: bytes,
    );
    if (path == null) return null; // cancelled
    await File(path).writeAsBytes(bytes, flush: true);
    if (!context.mounted) return path;
    showAppToast(context, successMessage);
    return path;
  } catch (_) {
    if (!context.mounted) return null;
    showAppToast(context, errorMessage, isError: true);
    return null;
  }
}

/// Builds the CSV text for the productions grid (Production No |
/// Date | Output Item | Qty | UOM | Warehouse | Unit Cost | Total
/// Cost | Batch No | Remarks — mirroring the grid's columns).
String buildProductionsCsv(
  AppLocalizations l10n,
  List<Production> productions,
) {
  return _buildGridCsv(
    [
      l10n.productionNo,
      l10n.commonDate,
      l10n.productionOutputitem,
      l10n.commonQuantity,
      l10n.commonUom,
      l10n.productionWarehouse,
      l10n.productionUnitcost,
      l10n.productionTotalcost,
      l10n.productionBatchno,
      l10n.purchasesRemarks,
    ],
    productions,
    (p) => [
      sanitizeCsvCell(p.productionNo.isEmpty ? '—' : p.productionNo),
      p.productionDate.isEmpty ? '—' : Formatters.date(p.productionDate),
      sanitizeCsvCell(p.outputItemName ?? p.outputItemCode ?? '—'),
      Formatters.number(p.outputQuantity),
      sanitizeCsvCell(p.outputUom ?? '—'),
      sanitizeCsvCell(p.finishedGoodsWarehouseName ?? '—'),
      Formatters.currency(p.unitCost ?? 0),
      Formatters.currency(p.totalBatchCost ?? 0),
      sanitizeCsvCell((p.batchNo?.isEmpty ?? true) ? '—' : p.batchNo!),
      sanitizeCsvCell((p.remarks?.isEmpty ?? true) ? '—' : p.remarks!),
    ],
  );
}

/// Builds the CSV text for the BOM list grid (BOM No | BOM Name |
/// Finished Item | Batch Qty | UOM | Material Lines | Material Cost
/// | Status — mirroring the grid's columns; the Status column uses
/// the same localized label as the grid's badge).
String buildBomsCsv(AppLocalizations l10n, List<Bom> boms) {
  return _buildGridCsv(
    [
      l10n.bomNo,
      l10n.bomName,
      l10n.bomFinisheditem,
      l10n.commonQuantity,
      l10n.commonUom,
      l10n.bomItems,
      l10n.bomMaterialcost,
      l10n.commonStatus,
    ],
    boms,
    (bom) => [
      sanitizeCsvCell(bom.bomNo.isEmpty ? '—' : bom.bomNo),
      sanitizeCsvCell(bom.bomName.isEmpty ? '—' : bom.bomName),
      sanitizeCsvCell(bom.finishedItemName ?? bom.finishedItemCode ?? '—'),
      Formatters.number(bom.quantity),
      sanitizeCsvCell(bom.finishedUom ?? '—'),
      Formatters.number(bom.itemCount ?? 0),
      Formatters.currency(bom.totalMaterialCost ?? 0),
      sanitizeCsvCell(bom.isActive ? l10n.statusActive : l10n.statusInactive),
    ],
  );
}

/// Builds the CSV text for the trial-balance grid (Account Code | Name
/// | Type | Debit | Credit | Balance).
String buildTrialBalanceCsv(
  AppLocalizations l10n,
  TrialBalanceReport report,
) {
  return _buildGridCsv(
    [
      l10n.reportsAccountcode,
      l10n.reportsAccountname,
      l10n.reportsAccounttype,
      l10n.reportsTotaldebit,
      l10n.reportsTotalcredit,
      l10n.reportsBalance,
    ],
    report.accounts,
    (a) => [
      sanitizeCsvCell(a.accountCode),
      sanitizeCsvCell(a.accountName),
      sanitizeCsvCell(a.accountType),
      Formatters.currency(a.totalDebit),
      Formatters.currency(a.totalCredit),
      Formatters.currency(a.balance),
    ],
  );
}

/// Builds the CSV text for the general-ledger grid (Date | Type |
/// Reference | Debit | Credit | Balance | Remarks).
String buildGeneralLedgerCsv(
  AppLocalizations l10n,
  List<GeneralLedgerRow> rows,
) {
  return _buildGridCsv(
    [
      l10n.reportsDate,
      l10n.reportsTransactiontype,
      l10n.reportsReferenceno,
      l10n.reportsDebit,
      l10n.reportsCredit,
      l10n.reportsBalance,
      l10n.fieldsNotes,
    ],
    rows,
    (r) => [
      r.transactionDate.isEmpty ? '—' : Formatters.date(r.transactionDate),
      sanitizeCsvCell(r.transactionType),
      sanitizeCsvCell(r.referenceNo),
      Formatters.currency(r.debit),
      Formatters.currency(r.credit),
      Formatters.currency(r.balance),
      sanitizeCsvCell((r.remarks?.isEmpty ?? true) ? '—' : r.remarks!),
    ],
  );
}

/// Builds the CSV text for the batch-traceability grid (batch rows
/// with original/sold/remaining quantities).
String buildBatchTraceabilityCsv(
  AppLocalizations l10n,
  BatchTraceabilityReport report,
) {
  return _buildGridCsv(
    [
      'Batch No',
      l10n.fieldsWarehouse,
      'Source',
      l10n.reportsDate,
      'Unit Cost',
      'Original',
      'Sold',
      'Remaining',
      l10n.expiryDate,
      l10n.expiryStatus,
    ],
    report.batches,
    (b) => [
      sanitizeCsvCell(b.batchNo.isEmpty ? '—' : b.batchNo),
      sanitizeCsvCell(b.warehouseName),
      sanitizeCsvCell('${b.sourceType} #${b.sourceId}'),
      b.receivedDate.isEmpty ? '—' : Formatters.date(b.receivedDate),
      Formatters.currency(b.unitCost),
      Formatters.number(b.quantityOriginal),
      Formatters.number(b.quantitySold),
      Formatters.number(b.quantityRemaining),
      b.expiryDate != null ? Formatters.date(b.expiryDate!) : '—',
      b.status ?? 'normal',
    ],
  );
}

/// Expiry report CSV — mirrors [ExpiryReportScreen]'s grid columns.
String buildExpiryReportCsv(
  AppLocalizations l10n,
  List<ExpiryReportRow> rows,
) {
  return _buildGridCsv(
    [
      l10n.inventoryItemcode,
      l10n.inventoryItemname,
      l10n.fieldsBatchno,
      l10n.fieldsWarehouse,
      l10n.inventoryQtyremaining,
      l10n.fieldsUnitcost,
      l10n.totalValue,
      l10n.fieldsDate,
      l10n.expiryDate,
      l10n.expiryStatus,
      l10n.daysUntilExpiry,
      l10n.statusHalted,
    ],
    rows,
    (r) => [
      sanitizeCsvCell(r.itemCode),
      sanitizeCsvCell(r.itemName),
      sanitizeCsvCell(r.batchNo),
      sanitizeCsvCell(r.warehouseName),
      Formatters.number(r.quantityRemaining),
      Formatters.currency(r.unitCost),
      Formatters.currency(r.totalValue),
      r.receivedDate.isEmpty ? '—' : Formatters.date(r.receivedDate),
      r.expiryDate != null ? Formatters.date(r.expiryDate!) : '—',
      r.status,
      r.daysUntilExpiry?.toString() ?? '—',
      r.halted ? l10n.statusHalted : '—',
    ],
  );
}
