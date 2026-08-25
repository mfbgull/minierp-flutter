import 'json_helpers.dart';

/// Report result models — port of the exact response shapes from
/// `server-reference/Reports.ts` (PORTING.md §11: report screens consume
/// these endpoints and render the shapes; the SQL stays server-side).
///
/// All report endpoints return `{success, data}` envelopes; the classes
/// below model the `data` payload of each.

// ── AR aging (GET /reports/ar-aging) ────────────────────────────────

/// One per-customer aging bucket row.
class ArAgingBucket {
  const ArAgingBucket({
    required this.customerName,
    required this.customerCode,
    required this.totalOutstanding,
    required this.currentAmount,
    required this.days1_30,
    required this.days31_60,
    required this.days61_90,
    required this.daysOver90,
  });

  factory ArAgingBucket.fromJson(Map<String, dynamic> json) => ArAgingBucket(
    customerName: asString(json['customer_name']) ?? '',
    customerCode: asString(json['customer_code']) ?? '',
    totalOutstanding: asNum(json['total_outstanding']) ?? 0,
    currentAmount: asNum(json['current_amount']) ?? 0,
    days1_30: asNum(json['days_1_30']) ?? 0,
    days31_60: asNum(json['days_31_60']) ?? 0,
    days61_90: asNum(json['days_61_90']) ?? 0,
    daysOver90: asNum(json['days_over_90']) ?? 0,
  );

  final String customerName;
  final String customerCode;
  final num totalOutstanding;
  final num currentAmount;
  final num days1_30;
  final num days31_60;
  final num days61_90;
  final num daysOver90;
}

/// Column totals across every bucket row.
class ArAgingSummary {
  const ArAgingSummary({
    required this.totalReceivables,
    required this.currentAmount,
    required this.total1_30,
    required this.total31_60,
    required this.total61_90,
    required this.totalOver90,
  });

  factory ArAgingSummary.fromJson(Map<String, dynamic> json) => ArAgingSummary(
    totalReceivables: asNum(json['totalReceivables']) ?? 0,
    currentAmount: asNum(json['current_amount']) ?? 0,
    total1_30: asNum(json['total_1_30']) ?? 0,
    total31_60: asNum(json['total_31_60']) ?? 0,
    total61_90: asNum(json['total_61_90']) ?? 0,
    totalOver90: asNum(json['total_over_90']) ?? 0,
  );

  final num totalReceivables;
  final num currentAmount;
  final num total1_30;
  final num total31_60;
  final num total61_90;
  final num totalOver90;
}

class ArAgingReport {
  const ArAgingReport({
    required this.asOfDate,
    required this.buckets,
    required this.summary,
  });

  factory ArAgingReport.fromJson(Map<String, dynamic> json) => ArAgingReport(
    asOfDate: asString(json['asOfDate']) ?? '',
    buckets: [
      for (final row in json['agingBuckets'] as List? ?? const [])
        ArAgingBucket.fromJson(row as Map<String, dynamic>),
    ],
    summary: ArAgingSummary.fromJson(
      json['summary'] as Map<String, dynamic>? ?? const {},
    ),
  );

  final String asOfDate;
  final List<ArAgingBucket> buckets;
  final ArAgingSummary summary;
}

/// One invoice row of the sales-summary detail grid.

// ── Low stock (GET /reports/low-stock) ──────────────────────────────

/// One low-stock row — the reports endpoint enriches each item with
/// `minimum_stock`, `shortage`, `stock_status` and the selling price
/// (distinct from the dashboard's `LowStockItem`).

// ── Stock level (GET /reports/stock-level) ──────────────────────────

/// One item row of the stock-level report. The server reuses
/// `standard_cost` as `standard_selling_price` (matching its SQL
/// select), so the price column shows the cost basis, as on the web.

// ── Stock valuation (GET /reports/stock-valuation) ──────────────────

/// One item row of the stock-valuation report. The server SQL aliases
/// the quantity as `total_stock` and the cost basis as `standard_cost`
/// (not `unit_cost`), so those exact keys are modeled here.

// ── Sales by customer (GET /reports/sales-by-customer) ───────────────

/// One customer row of the sales-by-customer report — the endpoint
/// returns a **bare array** (no wrapper object), so the model is a
/// single row and the repository parses the list directly.

// ── DSO (GET /reports/dso) ──────────────────────────────────────────

/// Days Sales Outstanding — `getDSOMetric` in `server-reference/Reports.ts`:
/// `{ dso, avgReceivables, totalCreditSales, totalSales, totalAR,
/// avgInvoiceValue, period: { startDate, endDate } }`. The endpoint
/// defaults to the last 30 days when no dates are supplied.
class DSOMetric {
  const DSOMetric({
    required this.dso,
    required this.avgReceivables,
    required this.totalCreditSales,
    required this.totalSales,
    required this.totalAR,
    required this.avgInvoiceValue,
    required this.startDate,
    required this.endDate,
  });

  factory DSOMetric.fromJson(Map<String, dynamic> json) => DSOMetric(
    dso: asNum(json['dso']) ?? 0,
    avgReceivables: asNum(json['avgReceivables']) ?? 0,
    totalCreditSales: asNum(json['totalCreditSales']) ?? 0,
    totalSales: asNum(json['totalSales']) ?? 0,
    totalAR: asNum(json['totalAR']) ?? 0,
    avgInvoiceValue: asNum(json['avgInvoiceValue']) ?? 0,
    startDate: asString(json['period']?['startDate']) ?? '',
    endDate: asString(json['period']?['endDate']) ?? '',
  );

  final num dso;
  final num avgReceivables;
  final num totalCreditSales;
  final num totalSales;
  final num totalAR;
  final num avgInvoiceValue;
  final String startDate;
  final String endDate;
}

/// One row of the cash flow report's movement grid — mirrors the
/// server's `movements` array (same sources/filters as the summary
/// totals, so the grid reconciles with the cards). Signed amount:
/// positive = money in, negative = money out.
class CashFlowMovement {
  const CashFlowMovement({
    required this.date,
    required this.type,
    required this.reference,
    required this.party,
    required this.method,
    required this.description,
    required this.amount,
  });

  factory CashFlowMovement.fromJson(Map<String, dynamic> json) =>
      CashFlowMovement(
        date: asString(json['date']) ?? '',
        type: asString(json['type']) ?? '',
        reference: asString(json['reference']) ?? '',
        party: asString(json['party']) ?? '',
        method: asString(json['method']) ?? '',
        description: asString(json['description']) ?? '',
        amount: asNum(json['amount']) ?? 0,
      );

  final String date;
  /// 'payment_received' | 'refund' | 'supplier_payment' | 'expense' | 'salary'
  final String type;
  final String reference;
  final String party;
  final String method;
  final String description;
  final num amount;
}

// ── Cash flow (GET /reports/cash-flow) ──────────────────────────────

/// Cash flow summary — `getCashFlow` in `server-reference/Reports.ts`:
/// `{ startDate, endDate, totalInflow, totalOutflow, netCashFlow }`.
/// The endpoint requires both dates.
class CashFlowReport {
  const CashFlowReport({
    required this.startDate,
    required this.endDate,
    required this.totalInflow,
    required this.totalOutflow,
    required this.netCashFlow,
    this.movements = const [],
  });

  factory CashFlowReport.fromJson(Map<String, dynamic> json) => CashFlowReport(
    startDate: asString(json['startDate']) ?? '',
    endDate: asString(json['endDate']) ?? '',
    totalInflow: asNum(json['totalInflow']) ?? 0,
    totalOutflow: asNum(json['totalOutflow']) ?? 0,
    netCashFlow: asNum(json['netCashFlow']) ?? 0,
    movements: [
      for (final m in json['movements'] as List? ?? const [])
        CashFlowMovement.fromJson(m as Map<String, dynamic>),
    ],
  );

  final String startDate;
  final String endDate;
  final num totalInflow;
  final num totalOutflow;
  final num netCashFlow;
  final List<CashFlowMovement> movements;
}

// ── Profit & loss (GET /reports/profit-loss) ────────────────────────

/// One expense-category line of the P&L report's breakdown.
class ProfitLossExpense {
  const ProfitLossExpense({required this.category, required this.total});

  factory ProfitLossExpense.fromJson(Map<String, dynamic> json) =>
      ProfitLossExpense(
        category: asString(json['expense_category']) ?? '',
        total: asNum(json['total']) ?? 0,
      );

  final String category;
  final num total;
}

/// Profit & loss — `getProfitLossReport` in `server-reference/Reports.ts`:
/// `{ startDate, endDate, totalRevenue, totalCogs, grossProfit, expenses:
/// [{ expense_category, total }], totalExpenses, netProfit,
/// grossProfitMargin, netProfitMargin }`. The endpoint requires both dates.
class ProfitLossReport {
  const ProfitLossReport({
    required this.startDate,
    required this.endDate,
    required this.totalRevenue,
    required this.totalCogs,
    required this.grossProfit,
    required this.expenses,
    required this.totalExpenses,
    required this.netProfit,
    required this.grossProfitMargin,
    required this.netProfitMargin,
  });

  factory ProfitLossReport.fromJson(Map<String, dynamic> json) =>
      ProfitLossReport(
        startDate: asString(json['startDate']) ?? '',
        endDate: asString(json['endDate']) ?? '',
        totalRevenue: asNum(json['totalRevenue']) ?? 0,
        totalCogs: asNum(json['totalCogs']) ?? 0,
        grossProfit: asNum(json['grossProfit']) ?? 0,
        expenses: [
          for (final e in json['expenses'] as List? ?? const [])
            ProfitLossExpense.fromJson(e as Map<String, dynamic>),
        ],
        totalExpenses: asNum(json['totalExpenses']) ?? 0,
        netProfit: asNum(json['netProfit']) ?? 0,
        grossProfitMargin: asNum(json['grossProfitMargin']) ?? 0,
        netProfitMargin: asNum(json['netProfitMargin']) ?? 0,
      );

  final String startDate;
  final String endDate;
  final num totalRevenue;
  final num totalCogs;
  final num grossProfit;
  final List<ProfitLossExpense> expenses;
  final num totalExpenses;
  final num netProfit;
  final num grossProfitMargin;
  final num netProfitMargin;
}

// ── Inventory movement (GET /reports/inventory-movement) ────────────

/// One stock-movement row of the inventory movement report.

/// Inbound/outbound tallies for the inventory movement report.

// ── Purchase summary (GET /reports/purchase-summary) ────────────────

/// One purchase-order row of the purchase summary report.

/// Period totals + return metrics for the purchase summary report.

// ── Customer statements (GET /reports/customer-statements) ──────────

/// One customer row of the customer statements report — the endpoint
/// returns `{ statements: [...] }`, so the model is a single row and
/// the repository parses `data['statements']` into a list.
class CustomerStatementRow {
  const CustomerStatementRow({
    required this.customerId,
    required this.customerName,
    required this.customerCode,
    required this.openingBalance,
    required this.totalDebits,
    required this.totalCredits,
    required this.closingBalance,
    required this.invoiceCount,
    required this.totalAmount,
    required this.paidAmount,
    required this.balance,
    required this.lastInvoiceDate,
  });

  factory CustomerStatementRow.fromJson(Map<String, dynamic> json) =>
      CustomerStatementRow(
        customerId: asInt(json['customer_id']) ?? 0,
        customerName: asString(json['customer_name']) ?? '',
        customerCode: asString(json['customer_code']) ?? '',
        openingBalance: asNum(json['opening_balance']) ?? 0,
        totalDebits: asNum(json['total_debits']) ?? 0,
        totalCredits: asNum(json['total_credits']) ?? 0,
        closingBalance: asNum(json['closing_balance']) ?? 0,
        invoiceCount: asInt(json['invoice_count']) ?? 0,
        totalAmount: asNum(json['total_amount']) ?? 0,
        paidAmount: asNum(json['paid_amount']) ?? 0,
        balance: asNum(json['balance']) ?? 0,
        lastInvoiceDate: asString(json['last_invoice_date']),
      );

  final int customerId;
  final String customerName;
  final String customerCode;
  final num openingBalance;
  final num totalDebits;
  final num totalCredits;
  final num closingBalance;
  final int invoiceCount;
  final num totalAmount;
  final num paidAmount;
  final num balance;
  final String? lastInvoiceDate;
}

// ── Top debtors (GET /reports/top-debtors) ──────────────────────────

/// One customer row of the top-debtors report — the endpoint returns a
/// **bare array** (no wrapper object), so the model is a single row and
/// the repository parses the list directly.
class TopDebtorRow {
  const TopDebtorRow({
    required this.customerName,
    required this.customerCode,
    required this.totalOutstanding,
    required this.outstandingBalance,
    required this.totalInvoiced,
    required this.invoiceCount,
  });

  factory TopDebtorRow.fromJson(Map<String, dynamic> json) => TopDebtorRow(
    customerName: asString(json['customer_name']) ?? '',
    customerCode: asString(json['customer_code']) ?? '',
    totalOutstanding: asNum(json['total_outstanding']) ?? 0,
    outstandingBalance: asNum(json['outstanding_balance']) ?? 0,
    totalInvoiced: asNum(json['total_invoiced']) ?? 0,
    invoiceCount: asNum(json['invoice_count']) ?? 0,
  );

  final String customerName;
  final String customerCode;
  final num totalOutstanding;
  final num outstandingBalance;
  final num totalInvoiced;
  final num invoiceCount;
}

// ── Expenses report (GET /reports/expenses) ─────────────────────────

/// One expense row of the expenses report grid — the report's own
/// immutable row shape. Field names match the API JSON exactly
/// (snake_case); unlike the CRUD [Expense] model there is no
/// created_at/updated_at/created_by_name (the report never returns
/// them).

/// One category bucket of the report's `categoryBreakdown` — name,
/// expense count and summed amount (server-computed).

/// Summary block of the expenses report (camelCase keys; the server
/// computes these from the same rows its grid shows).

// ── Sales by item (GET /reports/sales-by-item) ──────────────────────

/// One item row of the sales-by-item report — the endpoint returns a
/// **bare array** (no wrapper object), so the model is a single row and
/// the repository parses the list directly. Both dates are required
/// (the server 400s without them).

// ── Supplier analysis (GET /reports/supplier-analysis) ──────────────

/// One supplier row of the supplier-analysis report — the endpoint
/// returns a **bare array** (no wrapper object). Both dates are required
/// (the server 400s without them). `on_time_delivery_rate` is always 100
/// server-side (the web's delivery-rate column shows it verbatim).

// ── Production summary (GET /reports/production-summary) ────────────

/// One production-run row of the production summary report.

/// Period totals for the production summary report (camelCase keys;
/// the server computes them from the same rows its grid shows).

// ── BOM usage (GET /reports/bom-usage) ──────────────────────────────

/// One BOM row of the bom-usage report. The endpoint returns
/// `{ usage: [...] }`; dates default to all-time and an optional
/// `itemId` narrows to a finished item.

// ── Cash reconciliation (GET/POST /reports/cash-reconciliation) ─────

/// One tracked cash account of the end-of-day reconciliation
/// (Cash, Bank, Easypaisa, JazzCash, UPaisa).
class CashReconciliationAccount {
  const CashReconciliationAccount({
    required this.key,
    required this.name,
    required this.openingBalance,
    required this.inflow,
    required this.outflow,
    required this.net,
    required this.expectedBalance,
    required this.countedBalance,
    required this.variance,
    required this.notes,
    required this.reconciled,
    required this.reconciledAt,
  });

  factory CashReconciliationAccount.fromJson(Map<String, dynamic> json) =>
      CashReconciliationAccount(
        key: asString(json['key']) ?? '',
        name: asString(json['name']) ?? '',
        openingBalance: asNum(json['opening_balance']) ?? 0,
        inflow: asNum(json['inflow']) ?? 0,
        outflow: asNum(json['outflow']) ?? 0,
        net: asNum(json['net']) ?? 0,
        expectedBalance: asNum(json['expected_balance']) ?? 0,
        countedBalance: asNum(json['counted_balance']),
        variance: asNum(json['variance']),
        notes: asString(json['notes']),
        reconciled: json['reconciled'] == true,
        reconciledAt: asString(json['reconciled_at']),
      );

  final String key;
  final String name;
  final num openingBalance;
  final num inflow;
  final num outflow;
  final num net;
  final num expectedBalance;
  final num? countedBalance;
  final num? variance;
  final String? notes;
  final bool reconciled;
  final String? reconciledAt;
}

/// Totals across all accounts for the reconciliation date.
class CashReconciliationTotals {
  const CashReconciliationTotals({
    required this.opening,
    required this.inflow,
    required this.outflow,
    required this.closing,
  });

  factory CashReconciliationTotals.fromJson(Map<String, dynamic> json) =>
      CashReconciliationTotals(
        opening: asNum(json['total_opening']) ?? 0,
        inflow: asNum(json['total_inflow']) ?? 0,
        outflow: asNum(json['total_outflow']) ?? 0,
        closing: asNum(json['total_closing']) ?? 0,
      );

  final num opening;
  final num inflow;
  final num outflow;
  final num closing;
}

/// End-of-day cash/till reconciliation — `GET /reports/cash-reconciliation`.
class CashReconciliation {
  const CashReconciliation({
    required this.date,
    required this.accounts,
    required this.totals,
  });

  factory CashReconciliation.fromJson(Map<String, dynamic> json) =>
      CashReconciliation(
        date: asString(json['date']) ?? '',
        accounts: [
          for (final row in json['accounts'] as List? ?? const [])
            CashReconciliationAccount.fromJson(row as Map<String, dynamic>),
        ],
        totals: CashReconciliationTotals.fromJson(
          json['totals'] as Map<String, dynamic>? ?? const {},
        ),
      );

  final String date;
  final List<CashReconciliationAccount> accounts;
  final CashReconciliationTotals totals;
}

// ── AR summary (GET /reports/ar-summary) ────────────────────────────

/// One item of the status breakdown (count + amount for a given status).
class ArSummaryStatusBucket {
  const ArSummaryStatusBucket({required this.count, required this.amount});

  factory ArSummaryStatusBucket.fromJson(Map<String, dynamic> json) =>
      ArSummaryStatusBucket(
        count: asNum(json['count']) ?? 0,
        amount: asNum(json['amount']) ?? 0,
      );

  final num count;
  final num amount;
}

/// Status breakdown of outstanding invoices (unpaid / partially paid /
/// overdue). Keys are camelCase (server-side `getReceivablesSummary`).
class ArSummaryStatusBreakdown {
  const ArSummaryStatusBreakdown({
    required this.unpaid,
    required this.partiallyPaid,
    required this.overdue,
  });

  factory ArSummaryStatusBreakdown.fromJson(Map<String, dynamic> json) =>
      ArSummaryStatusBreakdown(
        unpaid: ArSummaryStatusBucket.fromJson(
          json['unpaid'] as Map<String, dynamic>? ?? const {},
        ),
        partiallyPaid: ArSummaryStatusBucket.fromJson(
          json['partiallyPaid'] as Map<String, dynamic>? ?? const {},
        ),
        overdue: ArSummaryStatusBucket.fromJson(
          json['overdue'] as Map<String, dynamic>? ?? const {},
        ),
      );

  final ArSummaryStatusBucket unpaid;
  final ArSummaryStatusBucket partiallyPaid;
  final ArSummaryStatusBucket overdue;
}

/// Rolling receivables summary — `getReceivablesSummary` in
/// `server-reference/Reports.ts`. The endpoint returns an envelope with
/// `asOfDate` plus the fields below as a flat object.
class ArSummaryReport {
  const ArSummaryReport({
    required this.asOfDate,
    required this.totalInvoices,
    required this.totalOutstanding,
    required this.totalPaid,
    required this.totalInvoiced,
    required this.totalCurrent,
    required this.total130,
    required this.total3160,
    required this.total6190,
    required this.totalOver90,
    required this.statusBreakdown,
  });

  factory ArSummaryReport.fromJson(Map<String, dynamic> json) =>
      ArSummaryReport(
        asOfDate: asString(json['asOfDate']) ?? '',
        totalInvoices: asNum(json['total_invoices']) ?? 0,
        totalOutstanding: asNum(json['total_outstanding']) ?? 0,
        totalPaid: asNum(json['total_paid']) ?? 0,
        totalInvoiced: asNum(json['total_invoiced']) ?? 0,
        totalCurrent: asNum(json['total_current']) ?? 0,
        total130: asNum(json['total_1_30']) ?? 0,
        total3160: asNum(json['total_31_60']) ?? 0,
        total6190: asNum(json['total_61_90']) ?? 0,
        totalOver90: asNum(json['total_over_90']) ?? 0,
        statusBreakdown: ArSummaryStatusBreakdown.fromJson(
          json['statusBreakdown'] as Map<String, dynamic>? ?? const {},
        ),
      );

  final String asOfDate;
  final num totalInvoices;
  final num totalOutstanding;
  final num totalPaid;
  final num totalInvoiced;
  final num totalCurrent;
  final num total130;
  final num total3160;
  final num total6190;
  final num totalOver90;
  final ArSummaryStatusBreakdown statusBreakdown;
}

// ── AP aging (GET /reports/ap-aging) ────────────────────────────────

class ApAgingBucket {
  const ApAgingBucket({
    required this.supplierName,
    required this.supplierCode,
    required this.totalOutstanding,
    required this.currentAmount,
    required this.days1_30,
    required this.days31_60,
    required this.days61_90,
    required this.daysOver90,
  });

  factory ApAgingBucket.fromJson(Map<String, dynamic> json) => ApAgingBucket(
    supplierName: asString(json['supplier_name']) ?? '',
    supplierCode: asString(json['supplier_code']) ?? '',
    totalOutstanding: asNum(json['total_outstanding']) ?? 0,
    currentAmount: asNum(json['current_amount']) ?? 0,
    days1_30: asNum(json['days_1_30']) ?? 0,
    days31_60: asNum(json['days_31_60']) ?? 0,
    days61_90: asNum(json['days_61_90']) ?? 0,
    daysOver90: asNum(json['days_over_90']) ?? 0,
  );

  final String supplierName;
  final String supplierCode;
  final num totalOutstanding;
  final num currentAmount;
  final num days1_30;
  final num days31_60;
  final num days61_90;
  final num daysOver90;
}

class ApAgingSummary {
  const ApAgingSummary({
    required this.totalPayables,
    required this.currentAmount,
    required this.total1_30,
    required this.total31_60,
    required this.total61_90,
    required this.totalOver90,
  });

  factory ApAgingSummary.fromJson(Map<String, dynamic> json) => ApAgingSummary(
    totalPayables: asNum(json['totalPayables']) ?? 0,
    currentAmount: asNum(json['current_amount']) ?? 0,
    total1_30: asNum(json['total_1_30']) ?? 0,
    total31_60: asNum(json['total_31_60']) ?? 0,
    total61_90: asNum(json['total_61_90']) ?? 0,
    totalOver90: asNum(json['total_over_90']) ?? 0,
  );

  final num totalPayables;
  final num currentAmount;
  final num total1_30;
  final num total31_60;
  final num total61_90;
  final num totalOver90;
}

class ApAgingReport {
  const ApAgingReport({
    required this.asOfDate,
    required this.buckets,
    required this.summary,
  });

  factory ApAgingReport.fromJson(Map<String, dynamic> json) => ApAgingReport(
    asOfDate: asString(json['asOfDate']) ?? '',
    buckets: [
      for (final row in json['agingBuckets'] as List? ?? const [])
        ApAgingBucket.fromJson(row as Map<String, dynamic>),
    ],
    summary: ApAgingSummary.fromJson(
      json['summary'] as Map<String, dynamic>? ?? const {},
    ),
  );

  final String asOfDate;
  final List<ApAgingBucket> buckets;
  final ApAgingSummary summary;
}

// ── Balance sheet (GET /reports/balance-sheet) ──────────────────────

class BalanceSheetAssets {
  const BalanceSheetAssets({
    required this.inventory,
    required this.accountsReceivable,
    required this.cash,
    required this.total,
  });

  factory BalanceSheetAssets.fromJson(Map<String, dynamic> json) =>
      BalanceSheetAssets(
        inventory: asNum(json['inventory']) ?? 0,
        accountsReceivable: asNum(json['accounts_receivable']) ?? 0,
        cash: asNum(json['cash']) ?? 0,
        total: asNum(json['total']) ?? 0,
      );

  final num inventory;
  final num accountsReceivable;
  final num cash;
  final num total;
}

class BalanceSheetLiabilities {
  const BalanceSheetLiabilities({
    required this.accountsPayable,
    required this.total,
  });

  factory BalanceSheetLiabilities.fromJson(Map<String, dynamic> json) =>
      BalanceSheetLiabilities(
        accountsPayable: asNum(json['accounts_payable']) ?? 0,
        total: asNum(json['total']) ?? 0,
      );

  final num accountsPayable;
  final num total;
}

class BalanceSheetEquity {
  const BalanceSheetEquity({
    required this.openingRetainedEarnings,
    required this.netIncomeYtd,
    required this.revenueYtd,
    required this.cogsYtd,
    required this.expensesYtd,
    required this.total,
  });

  factory BalanceSheetEquity.fromJson(Map<String, dynamic> json) =>
      BalanceSheetEquity(
        openingRetainedEarnings:
            asNum(json['opening_retained_earnings']) ?? 0,
        netIncomeYtd: asNum(json['net_income_ytd']) ?? 0,
        revenueYtd: asNum(json['revenue_ytd']) ?? 0,
        cogsYtd: asNum(json['cogs_ytd']) ?? 0,
        expensesYtd: asNum(json['expenses_ytd']) ?? 0,
        total: asNum(json['total']) ?? 0,
      );

  final num openingRetainedEarnings;
  final num netIncomeYtd;
  final num revenueYtd;
  final num cogsYtd;
  final num expensesYtd;
  final num total;
}

class BalanceSheetTotals {
  const BalanceSheetTotals({
    required this.totalAssets,
    required this.totalLiabilities,
    required this.totalEquity,
    required this.totalLiabAndEquity,
    required this.balanced,
  });

  factory BalanceSheetTotals.fromJson(Map<String, dynamic> json) =>
      BalanceSheetTotals(
        totalAssets: asNum(json['total_assets']) ?? 0,
        totalLiabilities: asNum(json['total_liabilities']) ?? 0,
        totalEquity: asNum(json['total_equity']) ?? 0,
        totalLiabAndEquity: asNum(json['total_liab_and_equity']) ?? 0,
        balanced: json['balanced'] == true,
      );

  final num totalAssets;
  final num totalLiabilities;
  final num totalEquity;
  final num totalLiabAndEquity;
  final bool balanced;
}

class BalanceSheetReport {
  const BalanceSheetReport({
    required this.asOfDate,
    required this.assets,
    required this.liabilities,
    required this.equity,
    required this.totals,
  });

  factory BalanceSheetReport.fromJson(Map<String, dynamic> json) =>
      BalanceSheetReport(
        asOfDate: asString(json['asOfDate']) ?? '',
        assets: BalanceSheetAssets.fromJson(
          json['assets'] as Map<String, dynamic>? ?? const {},
        ),
        liabilities: BalanceSheetLiabilities.fromJson(
          json['liabilities'] as Map<String, dynamic>? ?? const {},
        ),
        equity: BalanceSheetEquity.fromJson(
          json['equity'] as Map<String, dynamic>? ?? const {},
        ),
        totals: BalanceSheetTotals.fromJson(
          json['totals'] as Map<String, dynamic>? ?? const {},
        ),
      );

  final String asOfDate;
  final BalanceSheetAssets assets;
  final BalanceSheetLiabilities liabilities;
  final BalanceSheetEquity equity;
  final BalanceSheetTotals totals;
}

// ── Trial Balance (GET /reports/trial-balance) ──────────────────────

class TrialBalanceAccount {
  const TrialBalanceAccount({
    required this.accountCode,
    required this.accountName,
    required this.accountType,
    required this.totalDebit,
    required this.totalCredit,
    required this.balance,
    required this.isZero,
  });

  factory TrialBalanceAccount.fromJson(Map<String, dynamic> json) => TrialBalanceAccount(
    accountCode: asString(json['account_code']) ?? '',
    accountName: asString(json['account_name']) ?? '',
    accountType: asString(json['account_type']) ?? '',
    totalDebit: asNum(json['total_debit']) ?? 0,
    totalCredit: asNum(json['total_credit']) ?? 0,
    balance: asNum(json['balance']) ?? 0,
    isZero: json['is_zero'] == true,
  );

  final String accountCode;
  final String accountName;
  final String accountType;
  final num totalDebit;
  final num totalCredit;
  final num balance;
  final bool isZero;
}

class TrialBalanceReport {
  const TrialBalanceReport({
    required this.asOfDate,
    required this.accounts,
    required this.totalDebit,
    required this.totalCredit,
    required this.balanced,
    this.note,
  });

  factory TrialBalanceReport.fromJson(Map<String, dynamic> json) => TrialBalanceReport(
    asOfDate: asString(json['asOfDate']) ?? '',
    accounts: [
      for (final row in json['accounts'] as List? ?? const [])
        TrialBalanceAccount.fromJson(row as Map<String, dynamic>),
    ],
    totalDebit: asNum(json['total_debit']) ?? 0,
    totalCredit: asNum(json['total_credit']) ?? 0,
    balanced: json['balanced'] == true,
    note: asString(json['note']),
  );

  final String asOfDate;
  final List<TrialBalanceAccount> accounts;
  final num totalDebit;
  final num totalCredit;
  final bool balanced;
  final String? note;
}

// ── General Ledger (GET /reports/general-ledger) ─────────────────────

class GeneralLedgerRow {
  const GeneralLedgerRow({
    required this.id,
    this.customerId,
    this.accountCode,
    this.accountName,
    required this.transactionType,
    required this.referenceNo,
    required this.debit,
    required this.credit,
    required this.balance,
    required this.transactionDate,
    this.remarks,
  });

  factory GeneralLedgerRow.fromJson(Map<String, dynamic> json) => GeneralLedgerRow(
    id: asInt(json['id']) ?? 0,
    customerId: asInt(json['customer_id']),
    accountCode: asString(json['account_code']),
    accountName: asString(json['account_name']),
    transactionType: asString(json['transaction_type']) ?? '',
    referenceNo: asString(json['reference_no']) ?? '',
    debit: asNum(json['debit']) ?? 0,
    credit: asNum(json['credit']) ?? 0,
    balance: asNum(json['balance']) ?? 0,
    transactionDate: asString(json['transaction_date']) ?? '',
    remarks: asString(json['remarks']),
  );

  final int id;
  final int? customerId;
  final String? accountCode;
  final String? accountName;
  final String transactionType;
  final String referenceNo;
  final num debit;
  final num credit;
  final num balance;
  final String transactionDate;
  final String? remarks;
}

// ── Income Statement (GET /reports/income-statement) ─────────────────

class IncomeStatementReport {
  const IncomeStatementReport({
    required this.startDate,
    required this.endDate,
    required this.revenue,
    required this.cogs,
    required this.expenses,
    required this.netIncome,
    required this.grossProfit,
  });

  factory IncomeStatementReport.fromJson(Map<String, dynamic> json) => IncomeStatementReport(
    startDate: asString(json['startDate']) ?? '',
    endDate: asString(json['endDate']) ?? '',
    revenue: asNum(json['revenue']) ?? 0,
    cogs: asNum(json['cogs']) ?? 0,
    expenses: asNum(json['expenses']) ?? 0,
    netIncome: asNum(json['netIncome']) ?? 0,
    grossProfit: asNum(json['grossProfit']) ?? 0,
  );

  final String startDate;
  final String endDate;
  final num revenue;
  final num cogs;
  final num expenses;
  final num netIncome;
  final num grossProfit;
}

// ── Tax Summary (GET /reports/tax-summary) ───────────────────────────

class TaxSummaryReport {
  const TaxSummaryReport({
    required this.totalTax,
  });

  factory TaxSummaryReport.fromJson(Map<String, dynamic> json) => TaxSummaryReport(
    totalTax: asNum(json['total_tax']) ?? 0,
  );

  final num totalTax;
}

// ── Batch Traceability (GET /reports/batch-traceability/:itemId) ─────

class BatchTraceabilityItem {
  const BatchTraceabilityItem({
    required this.id,
    required this.itemCode,
    required this.itemName,
    required this.unitOfMeasure,
  });

  factory BatchTraceabilityItem.fromJson(Map<String, dynamic> json) => BatchTraceabilityItem(
    id: asInt(json['id']) ?? 0,
    itemCode: asString(json['item_code']) ?? '',
    itemName: asString(json['item_name']) ?? '',
    unitOfMeasure: asString(json['unit_of_measure']) ?? '',
  );

  final int id;
  final String itemCode;
  final String itemName;
  final String unitOfMeasure;
}

class BatchTraceabilityBatch {
  const BatchTraceabilityBatch({
    required this.id,
    required this.batchNo,
    required this.warehouseName,
    required this.sourceType,
    required this.sourceId,
    required this.quantityOriginal,
    required this.quantityRemaining,
    required this.quantitySold,
    required this.unitCost,
    required this.receivedDate,
    this.expiryDate,
    this.status,
  });

  factory BatchTraceabilityBatch.fromJson(Map<String, dynamic> json) => BatchTraceabilityBatch(
    id: asInt(json['id']) ?? 0,
    batchNo: asString(json['batch_no']) ?? '',
    warehouseName: asString(json['warehouse_name']) ?? '',
    sourceType: asString(json['source_type']) ?? '',
    sourceId: asInt(json['source_id']) ?? 0,
    quantityOriginal: asNum(json['quantity_original']) ?? 0,
    quantityRemaining: asNum(json['quantity_remaining']) ?? 0,
    quantitySold: asNum(json['quantity_sold']) ?? 0,
    unitCost: asNum(json['unit_cost']) ?? 0,
    receivedDate: asString(json['received_date']) ?? '',
    expiryDate: asString(json['expiry_date']),
    status: asString(json['status']),
  );

  final int id;
  final String batchNo;
  final String warehouseName;
  final String sourceType;
  final int sourceId;
  final num quantityOriginal;
  final num quantityRemaining;
  final num quantitySold;
  final num unitCost;
  final String receivedDate;
  final String? expiryDate;
  final String? status;
}

/// One row of the expiry report (`GET /reports/expiry`).
class ExpiryReportRow {
  const ExpiryReportRow({
    required this.itemCode,
    required this.itemName,
    required this.batchNo,
    required this.warehouseName,
    required this.quantityRemaining,
    required this.unitCost,
    required this.receivedDate,
    this.expiryDate,
    required this.status,
    this.halted = false,
  });

  factory ExpiryReportRow.fromJson(Map<String, dynamic> json) => ExpiryReportRow(
    itemCode: asString(json['item_code']) ?? '',
    itemName: asString(json['item_name']) ?? '',
    batchNo: asString(json['batch_no']) ?? '',
    warehouseName: asString(json['warehouse_name']) ?? '',
    quantityRemaining: asNum(json['quantity_remaining']) ?? 0,
    unitCost: asNum(json['unit_cost']) ?? 0,
    receivedDate: asString(json['received_date']) ?? '',
    expiryDate: asString(json['expiry_date']),
    status: asString(json['status']) ?? 'normal',
    halted: asBool(json['halted']),
  );

  final String itemCode;
  final String itemName;
  final String batchNo;
  final String warehouseName;
  final num quantityRemaining;
  final num unitCost;
  final String receivedDate;
  final String? expiryDate;
  final String status;
  final bool halted;

  num get totalValue => quantityRemaining * unitCost;

  /// Days until expiry (negative when already expired); null when no date.
  int? get daysUntilExpiry {
    if (expiryDate == null) return null;
    final expiry = DateTime.tryParse(expiryDate!);
    if (expiry == null) return null;
    return expiry.difference(DateTime.now()).inDays;
  }
}

/// One row of the dashboard expiry-alerts feed
/// (`GET /dashboard/expiry-alerts`).
class ExpiryAlert {
  const ExpiryAlert({
    required this.itemId,
    required this.itemName,
    required this.batchNo,
    required this.warehouseName,
    required this.expiryDate,
    required this.daysRemaining,
  });

  factory ExpiryAlert.fromJson(Map<String, dynamic> json) => ExpiryAlert(
    itemId: asInt(json['item_id']) ?? 0,
    itemName: asString(json['item_name']) ?? '',
    batchNo: asString(json['batch_no']) ?? '',
    warehouseName: asString(json['warehouse_name']) ?? '',
    expiryDate: asString(json['expiry_date']) ?? '',
    daysRemaining: asInt(json['days_remaining']) ?? 0,
  );

  final int itemId;
  final String itemName;
  final String batchNo;
  final String warehouseName;
  final String expiryDate;
  final int daysRemaining;
}

class BatchTraceabilitySummary {
  const BatchTraceabilitySummary({
    required this.totalBatches,
    required this.activeBatches,
    required this.totalOriginal,
    required this.totalSold,
    required this.totalRemaining,
  });

  factory BatchTraceabilitySummary.fromJson(Map<String, dynamic> json) => BatchTraceabilitySummary(
    totalBatches: asInt(json['totalBatches']) ?? 0,
    activeBatches: asInt(json['activeBatches']) ?? 0,
    totalOriginal: asNum(json['totalOriginal']) ?? 0,
    totalSold: asNum(json['totalSold']) ?? 0,
    totalRemaining: asNum(json['totalRemaining']) ?? 0,
  );

  final int totalBatches;
  final int activeBatches;
  final num totalOriginal;
  final num totalSold;
  final num totalRemaining;
}

class BatchTraceabilityReport {
  const BatchTraceabilityReport({
    required this.item,
    required this.batches,
    required this.summary,
  });

  factory BatchTraceabilityReport.fromJson(Map<String, dynamic> json) => BatchTraceabilityReport(
    item: BatchTraceabilityItem.fromJson(json['item'] as Map<String, dynamic>),
    batches: [
      for (final row in json['batches'] as List? ?? const [])
        BatchTraceabilityBatch.fromJson(row as Map<String, dynamic>),
    ],
    summary: BatchTraceabilitySummary.fromJson(
      json['summary'] as Map<String, dynamic>? ?? const {},
    ),
  );

  final BatchTraceabilityItem item;
  final List<BatchTraceabilityBatch> batches;
  final BatchTraceabilitySummary summary;
}
