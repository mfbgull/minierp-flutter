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

// ── Sales summary (GET /reports/sales-summary) ──────────────────────

class SalesSummaryPeriod {
  const SalesSummaryPeriod({required this.startDate, required this.endDate});

  factory SalesSummaryPeriod.fromJson(Map<String, dynamic> json) =>
      SalesSummaryPeriod(
        startDate: asString(json['startDate']) ?? '',
        endDate: asString(json['endDate']) ?? '',
      );

  final String startDate;
  final String endDate;
}

class SalesSummaryStats {
  const SalesSummaryStats({
    required this.totalInvoices,
    required this.totalSales,
    required this.totalItemsSold,
    required this.averageInvoiceValue,
    required this.totalPaid,
    required this.totalBalance,
  });

  factory SalesSummaryStats.fromJson(Map<String, dynamic> json) =>
      SalesSummaryStats(
        totalInvoices: asNum(json['totalInvoices']) ?? 0,
        totalSales: asNum(json['totalSales']) ?? 0,
        totalItemsSold: asNum(json['totalItemsSold']) ?? 0,
        averageInvoiceValue: asNum(json['averageInvoiceValue']) ?? 0,
        totalPaid: asNum(json['totalPaid']) ?? 0,
        totalBalance: asNum(json['totalBalance']) ?? 0,
      );

  final num totalInvoices;
  final num totalSales;
  final num totalItemsSold;
  final num averageInvoiceValue;
  final num totalPaid;
  final num totalBalance;
}

/// One invoice row of the sales-summary detail grid.
class SalesSummaryRow {
  const SalesSummaryRow({
    required this.invoiceDate,
    required this.invoiceNo,
    required this.customerName,
    required this.totalSales,
    required this.totalItems,
    required this.paidAmount,
    required this.balanceAmount,
    required this.status,
  });

  factory SalesSummaryRow.fromJson(Map<String, dynamic> json) =>
      SalesSummaryRow(
        invoiceDate: asString(json['invoice_date']) ?? '',
        invoiceNo: asString(json['invoice_no']) ?? '',
        customerName: asString(json['customer_name']) ?? '',
        totalSales: asNum(json['total_sales']) ?? 0,
        totalItems: asNum(json['total_items']) ?? 0,
        paidAmount: asNum(json['paid_amount']) ?? 0,
        balanceAmount: asNum(json['balance_amount']) ?? 0,
        status: asString(json['status']) ?? '',
      );

  final String invoiceDate;
  final String invoiceNo;
  final String customerName;
  final num totalSales;
  final num totalItems;
  final num paidAmount;
  final num balanceAmount;
  final String status;
}

class SalesSummaryReport {
  const SalesSummaryReport({
    required this.summary,
    required this.sales,
    this.period,
  });

  factory SalesSummaryReport.fromJson(Map<String, dynamic> json) =>
      SalesSummaryReport(
        period: json['period'] is Map<String, dynamic>
            ? SalesSummaryPeriod.fromJson(
                json['period'] as Map<String, dynamic>,
              )
            : null,
        summary: SalesSummaryStats.fromJson(
          json['summary'] as Map<String, dynamic>? ?? const {},
        ),
        sales: [
          for (final row in json['sales'] as List? ?? const [])
            SalesSummaryRow.fromJson(row as Map<String, dynamic>),
        ],
      );

  final SalesSummaryPeriod? period;
  final SalesSummaryStats summary;
  final List<SalesSummaryRow> sales;
}

// ── Low stock (GET /reports/low-stock) ──────────────────────────────

/// One low-stock row — the reports endpoint enriches each item with
/// `minimum_stock`, `shortage`, `stock_status` and the selling price
/// (distinct from the dashboard's `LowStockItem`).
class LowStockReportRow {
  const LowStockReportRow({
    required this.id,
    required this.itemCode,
    required this.itemName,
    required this.itemCategory,
    required this.unitOfMeasure,
    required this.currentStock,
    required this.minimumStock,
    required this.shortage,
    required this.reorderLevel,
    required this.standardSellingPrice,
    required this.stockStatus,
  });

  factory LowStockReportRow.fromJson(Map<String, dynamic> json) =>
      LowStockReportRow(
        id: asInt(json['id']) ?? 0,
        itemCode: asString(json['item_code']) ?? '',
        itemName: asString(json['item_name']) ?? '',
        itemCategory: asString(json['item_category']) ?? '',
        unitOfMeasure: asString(json['unit_of_measure']) ?? '',
        currentStock: asNum(json['current_stock']) ?? 0,
        minimumStock: asNum(json['minimum_stock']) ?? 0,
        shortage: asNum(json['shortage']) ?? 0,
        reorderLevel: asNum(json['reorder_level']) ?? 0,
        standardSellingPrice: asNum(json['standard_selling_price']) ?? 0,
        stockStatus: asString(json['stock_status']) ?? '',
      );

  final int id;
  final String itemCode;
  final String itemName;
  final String itemCategory;
  final String unitOfMeasure;
  final num currentStock;
  final num minimumStock;
  final num shortage;
  final num reorderLevel;
  final num standardSellingPrice;

  /// Out of Stock | Low Stock | In Stock.
  final String stockStatus;
}

// ── Stock level (GET /reports/stock-level) ──────────────────────────

/// One item row of the stock-level report. The server reuses
/// `standard_cost` as `standard_selling_price` (matching its SQL
/// select), so the price column shows the cost basis, as on the web.
class StockLevelRow {
  const StockLevelRow({
    required this.id,
    required this.itemCode,
    required this.itemName,
    required this.itemCategory,
    required this.unitOfMeasure,
    required this.currentStock,
    required this.minimumStock,
    required this.reorderLevel,
    required this.standardSellingPrice,
    required this.stockStatus,
  });

  factory StockLevelRow.fromJson(Map<String, dynamic> json) => StockLevelRow(
    id: asInt(json['id']) ?? 0,
    itemCode: asString(json['item_code']) ?? '',
    itemName: asString(json['item_name']) ?? '',
    itemCategory: asString(json['item_category']) ?? '',
    unitOfMeasure: asString(json['unit_of_measure']) ?? '',
    currentStock: asNum(json['current_stock']) ?? 0,
    minimumStock: asNum(json['minimum_stock']) ?? 0,
    reorderLevel: asNum(json['reorder_level']) ?? 0,
    standardSellingPrice: asNum(json['standard_selling_price']) ?? 0,
    stockStatus: asString(json['stock_status']) ?? '',
  );

  final int id;
  final String itemCode;
  final String itemName;
  final String itemCategory;
  final String unitOfMeasure;
  final num currentStock;
  final num minimumStock;
  final num reorderLevel;
  final num standardSellingPrice;
  final String stockStatus;
}

class StockLevelSummary {
  const StockLevelSummary({
    required this.totalItems,
    required this.inStock,
    required this.lowStock,
    required this.outOfStock,
  });

  factory StockLevelSummary.fromJson(Map<String, dynamic> json) =>
      StockLevelSummary(
        totalItems: asNum(json['totalItems']) ?? 0,
        inStock: asNum(json['inStock']) ?? 0,
        lowStock: asNum(json['lowStock']) ?? 0,
        outOfStock: asNum(json['outOfStock']) ?? 0,
      );

  final num totalItems;
  final num inStock;
  final num lowStock;
  final num outOfStock;
}

class StockLevelReport {
  const StockLevelReport({required this.rows, required this.summary});

  factory StockLevelReport.fromJson(Map<String, dynamic> json) =>
      StockLevelReport(
        rows: [
          for (final row in json['stockLevels'] as List? ?? const [])
            StockLevelRow.fromJson(row as Map<String, dynamic>),
        ],
        summary: StockLevelSummary.fromJson(
          json['summary'] as Map<String, dynamic>? ?? const {},
        ),
      );

  final List<StockLevelRow> rows;
  final StockLevelSummary summary;
}

// ── Stock valuation (GET /reports/stock-valuation) ──────────────────

/// One item row of the stock-valuation report. The server SQL aliases
/// the quantity as `total_stock` and the cost basis as `standard_cost`
/// (not `unit_cost`), so those exact keys are modeled here.
class StockValuationRow {
  const StockValuationRow({
    required this.id,
    required this.itemCode,
    required this.itemName,
    required this.itemCategory,
    required this.unitOfMeasure,
    required this.currentStock,
    required this.unitCost,
    required this.totalValue,
    required this.valuationMethod,
  });

  factory StockValuationRow.fromJson(Map<String, dynamic> json) =>
      StockValuationRow(
        id: asInt(json['id']) ?? 0,
        itemCode: asString(json['item_code']) ?? '',
        itemName: asString(json['item_name']) ?? '',
        itemCategory: asString(json['category']) ?? '',
        unitOfMeasure: asString(json['unit_of_measure']) ?? '',
        currentStock: asNum(json['total_stock']) ?? 0,
        unitCost: asNum(json['standard_cost']) ?? 0,
        totalValue: asNum(json['total_value']) ?? 0,
        valuationMethod: asString(json['valuation_method']) ?? '',
      );

  final int id;
  final String itemCode;
  final String itemName;
  final String itemCategory;
  final String unitOfMeasure;
  final num currentStock;
  final num unitCost;
  final num totalValue;

  /// batch | standard_cost_fallback
  final String valuationMethod;
}

class StockValuationSummary {
  const StockValuationSummary({
    required this.totalValue,
    required this.totalItems,
    required this.batchTrackedItems,
    required this.legacyItems,
  });

  factory StockValuationSummary.fromJson(Map<String, dynamic> json) =>
      StockValuationSummary(
        totalValue: asNum(json['totalValue']) ?? 0,
        totalItems: asNum(json['totalItems']) ?? 0,
        batchTrackedItems: asNum(json['batchTrackedItems']) ?? 0,
        legacyItems: asNum(json['legacyItems']) ?? 0,
      );

  final num totalValue;
  final num totalItems;
  final num batchTrackedItems;
  final num legacyItems;
}

class StockValuationReport {
  const StockValuationReport({required this.rows, required this.summary});

  factory StockValuationReport.fromJson(Map<String, dynamic> json) =>
      StockValuationReport(
        rows: [
          for (final row in json['stockValuation'] as List? ?? const [])
            StockValuationRow.fromJson(row as Map<String, dynamic>),
        ],
        summary: StockValuationSummary.fromJson(
          json['summary'] as Map<String, dynamic>? ?? const {},
        ),
      );

  final List<StockValuationRow> rows;
  final StockValuationSummary summary;
}

// ── Sales by customer (GET /reports/sales-by-customer) ───────────────

/// One customer row of the sales-by-customer report — the endpoint
/// returns a **bare array** (no wrapper object), so the model is a
/// single row and the repository parses the list directly.
class SalesByCustomerRow {
  const SalesByCustomerRow({
    required this.customerName,
    required this.customerCode,
    required this.email,
    required this.phone,
    required this.totalInvoices,
    required this.totalSales,
    required this.totalItems,
    required this.averageOrderValue,
    required this.lastPurchaseDate,
  });

  factory SalesByCustomerRow.fromJson(Map<String, dynamic> json) =>
      SalesByCustomerRow(
        customerName: asString(json['customer_name']) ?? '',
        customerCode: asString(json['customer_code']) ?? '',
        email: asString(json['email']) ?? '',
        phone: asString(json['phone']) ?? '',
        totalInvoices: asNum(json['total_invoices']) ?? 0,
        totalSales: asNum(json['total_sales']) ?? 0,
        totalItems: asNum(json['total_items']) ?? 0,
        averageOrderValue: asNum(json['average_order_value']) ?? 0,
        lastPurchaseDate: asString(json['last_purchase_date']) ?? '',
      );

  final String customerName;
  final String customerCode;
  final String email;
  final String phone;
  final num totalInvoices;
  final num totalSales;
  final num totalItems;
  final num averageOrderValue;
  final String lastPurchaseDate;
}

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
  });

  factory CashFlowReport.fromJson(Map<String, dynamic> json) => CashFlowReport(
    startDate: asString(json['startDate']) ?? '',
    endDate: asString(json['endDate']) ?? '',
    totalInflow: asNum(json['totalInflow']) ?? 0,
    totalOutflow: asNum(json['totalOutflow']) ?? 0,
    netCashFlow: asNum(json['netCashFlow']) ?? 0,
  );

  final String startDate;
  final String endDate;
  final num totalInflow;
  final num totalOutflow;
  final num netCashFlow;
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
class InventoryMovementRow {
  const InventoryMovementRow({
    required this.movementNo,
    required this.movementType,
    required this.quantity,
    required this.unitCost,
    required this.movementDate,
    required this.referenceDoctype,
    required this.referenceDocno,
    required this.remarks,
    required this.itemCode,
    required this.itemName,
    required this.warehouseName,
  });

  factory InventoryMovementRow.fromJson(Map<String, dynamic> json) =>
      InventoryMovementRow(
        movementNo: asString(json['movement_no']) ?? '',
        movementType: asString(json['movement_type']) ?? '',
        quantity: asNum(json['quantity']) ?? 0,
        unitCost: asNum(json['unit_cost']) ?? 0,
        movementDate: asString(json['movement_date']) ?? '',
        referenceDoctype: asString(json['reference_doctype']) ?? '',
        referenceDocno: asString(json['reference_docno']) ?? '',
        remarks: asString(json['remarks']) ?? '',
        itemCode: asString(json['item_code']) ?? '',
        itemName: asString(json['item_name']) ?? '',
        warehouseName: asString(json['warehouse_name']) ?? '',
      );

  final String movementNo;
  final String movementType;
  final num quantity;
  final num unitCost;
  final String movementDate;
  final String referenceDoctype;
  final String referenceDocno;
  final String remarks;
  final String itemCode;
  final String itemName;
  final String warehouseName;
}

/// Inbound/outbound tallies for the inventory movement report.
class InventoryMovementSummary {
  const InventoryMovementSummary({
    required this.totalInbound,
    required this.totalOutbound,
    required this.netMovement,
  });

  factory InventoryMovementSummary.fromJson(Map<String, dynamic> json) =>
      InventoryMovementSummary(
        totalInbound: asNum(json['totalInbound']) ?? 0,
        totalOutbound: asNum(json['totalOutbound']) ?? 0,
        netMovement: asNum(json['netMovement']) ?? 0,
      );

  final num totalInbound;
  final num totalOutbound;
  final num netMovement;
}

class InventoryMovementReport {
  const InventoryMovementReport({required this.rows, required this.summary});

  factory InventoryMovementReport.fromJson(Map<String, dynamic> json) =>
      InventoryMovementReport(
        rows: [
          for (final row in json['movements'] as List? ?? const [])
            InventoryMovementRow.fromJson(row as Map<String, dynamic>),
        ],
        summary: InventoryMovementSummary.fromJson(
          json['summary'] as Map<String, dynamic>? ?? const {},
        ),
      );

  final List<InventoryMovementRow> rows;
  final InventoryMovementSummary summary;
}

// ── Purchase summary (GET /reports/purchase-summary) ────────────────

/// One purchase-order row of the purchase summary report.
class PurchaseSummaryRow {
  const PurchaseSummaryRow({
    required this.poId,
    required this.purchaseOrderNumber,
    required this.purchaseDate,
    required this.supplierName,
    required this.totalCost,
    required this.status,
    required this.totalItems,
    required this.receivedAmount,
    required this.balanceAmount,
  });

  factory PurchaseSummaryRow.fromJson(Map<String, dynamic> json) =>
      PurchaseSummaryRow(
        poId: asInt(json['po_id']) ?? 0,
        purchaseOrderNumber: asString(json['purchase_order_number']) ?? '',
        purchaseDate: asString(json['purchase_date']) ?? '',
        supplierName: asString(json['supplier_name']) ?? '',
        totalCost: asNum(json['total_cost']) ?? 0,
        status: asString(json['status']) ?? '',
        totalItems: asNum(json['total_items']) ?? 0,
        receivedAmount: asNum(json['received_amount']) ?? 0,
        balanceAmount: asNum(json['balance_amount']) ?? 0,
      );

  final int poId;
  final String purchaseOrderNumber;
  final String purchaseDate;
  final String supplierName;
  final num totalCost;
  final String status;
  final num totalItems;
  final num receivedAmount;
  final num balanceAmount;
}

/// Period totals + return metrics for the purchase summary report.
class PurchaseSummaryStats {
  const PurchaseSummaryStats({
    required this.totalOrders,
    required this.totalCost,
    required this.totalItems,
    required this.averageOrderValue,
    required this.returnCount,
    required this.returnQuantity,
    required this.returnValue,
  });

  factory PurchaseSummaryStats.fromJson(Map<String, dynamic> json) =>
      PurchaseSummaryStats(
        totalOrders: asNum(json['totalOrders']) ?? 0,
        totalCost: asNum(json['totalCost']) ?? 0,
        totalItems: asNum(json['totalItems']) ?? 0,
        averageOrderValue: asNum(json['averageOrderValue']) ?? 0,
        returnCount: asNum(json['returnCount']) ?? 0,
        returnQuantity: asNum(json['returnQuantity']) ?? 0,
        returnValue: asNum(json['returnValue']) ?? 0,
      );

  final num totalOrders;
  final num totalCost;
  final num totalItems;
  final num averageOrderValue;
  final num returnCount;
  final num returnQuantity;
  final num returnValue;
}

class PurchaseSummaryReport {
  const PurchaseSummaryReport({required this.rows, required this.summary});

  factory PurchaseSummaryReport.fromJson(Map<String, dynamic> json) =>
      PurchaseSummaryReport(
        rows: [
          for (final row in json['purchases'] as List? ?? const [])
            PurchaseSummaryRow.fromJson(row as Map<String, dynamic>),
        ],
        summary: PurchaseSummaryStats.fromJson(
          json['summary'] as Map<String, dynamic>? ?? const {},
        ),
      );

  final List<PurchaseSummaryRow> rows;
  final PurchaseSummaryStats summary;
}

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
class ExpensesReportRow {
  const ExpensesReportRow({
    required this.id,
    required this.expenseNo,
    required this.expenseCategory,
    this.description,
    required this.amount,
    required this.expenseDate,
    this.paymentMethod,
    this.referenceNo,
    this.vendorName,
    this.project,
    required this.status,
  });

  factory ExpensesReportRow.fromJson(Map<String, dynamic> json) =>
      ExpensesReportRow(
        id: asInt(json['id']) ?? 0,
        expenseNo: asString(json['expense_no']) ?? '',
        expenseCategory: asString(json['expense_category']) ?? '',
        description: asString(json['description']),
        amount: asNum(json['amount']) ?? 0,
        expenseDate: asString(json['expense_date']) ?? '',
        paymentMethod: asString(json['payment_method']),
        referenceNo: asString(json['reference_no']),
        vendorName: asString(json['vendor_name']),
        project: asString(json['project']),
        status: asString(json['status']) ?? 'Approved',
      );

  final int id;
  final String expenseNo;
  final String expenseCategory;
  final String? description;
  final num amount;
  final String expenseDate;
  final String? paymentMethod;
  final String? referenceNo;
  final String? vendorName;
  final String? project;
  final String status;
}

/// One category bucket of the report's `categoryBreakdown` — name,
/// expense count and summed amount (server-computed).
class ExpenseCategoryBreakdown {
  const ExpenseCategoryBreakdown({
    required this.category,
    required this.count,
    required this.totalAmount,
  });

  factory ExpenseCategoryBreakdown.fromJson(Map<String, dynamic> json) =>
      ExpenseCategoryBreakdown(
        category: asString(json['expense_category']) ?? '',
        count: asNum(json['count']) ?? 0,
        totalAmount: asNum(json['total_amount']) ?? 0,
      );

  final String category;
  final num count;
  final num totalAmount;
}

/// Summary block of the expenses report (camelCase keys; the server
/// computes these from the same rows its grid shows).
class ExpensesReportSummary {
  const ExpensesReportSummary({
    required this.totalAmount,
    required this.totalExpenses,
    required this.averageAmount,
  });

  factory ExpensesReportSummary.fromJson(Map<String, dynamic> json) =>
      ExpensesReportSummary(
        totalAmount: asNum(json['totalAmount']) ?? 0,
        totalExpenses: asNum(json['totalExpenses']) ?? 0,
        averageAmount: asNum(json['averageAmount']) ?? 0,
      );

  final num totalAmount;
  final num totalExpenses;
  final num averageAmount;
}

class ExpensesReport {
  const ExpensesReport({
    required this.rows,
    required this.summary,
    required this.categoryBreakdown,
  });

  factory ExpensesReport.fromJson(Map<String, dynamic> json) => ExpensesReport(
    rows: [
      for (final row in json['expenses'] as List? ?? const [])
        ExpensesReportRow.fromJson(row as Map<String, dynamic>),
    ],
    summary: ExpensesReportSummary.fromJson(
      json['summary'] as Map<String, dynamic>? ?? const {},
    ),
    categoryBreakdown: [
      for (final row in json['categoryBreakdown'] as List? ?? const [])
        ExpenseCategoryBreakdown.fromJson(row as Map<String, dynamic>),
    ],
  );

  final List<ExpensesReportRow> rows;
  final ExpensesReportSummary summary;
  final List<ExpenseCategoryBreakdown> categoryBreakdown;
}

// ── Sales by item (GET /reports/sales-by-item) ──────────────────────

/// One item row of the sales-by-item report — the endpoint returns a
/// **bare array** (no wrapper object), so the model is a single row and
/// the repository parses the list directly. Both dates are required
/// (the server 400s without them).
class SalesByItemRow {
  const SalesByItemRow({
    required this.itemCode,
    required this.itemName,
    required this.itemCategory,
    required this.totalQuantitySold,
    required this.totalSales,
    required this.averageSellingPrice,
  });

  factory SalesByItemRow.fromJson(Map<String, dynamic> json) =>
      SalesByItemRow(
        itemCode: asString(json['item_code']) ?? '',
        itemName: asString(json['item_name']) ?? '',
        itemCategory: asString(json['item_category']) ?? '',
        totalQuantitySold: asNum(json['total_quantity_sold']) ?? 0,
        totalSales: asNum(json['total_sales']) ?? 0,
        averageSellingPrice: asNum(json['avg_selling_price']) ?? 0,
      );

  final String itemCode;
  final String itemName;
  final String itemCategory;
  final num totalQuantitySold;
  final num totalSales;
  final num averageSellingPrice;
}

// ── Supplier analysis (GET /reports/supplier-analysis) ──────────────

/// One supplier row of the supplier-analysis report — the endpoint
/// returns a **bare array** (no wrapper object). Both dates are required
/// (the server 400s without them). `on_time_delivery_rate` is always 100
/// server-side (the web's delivery-rate column shows it verbatim).
class SupplierAnalysisRow {
  const SupplierAnalysisRow({
    required this.supplierId,
    required this.supplierName,
    required this.supplierCode,
    required this.email,
    required this.phone,
    required this.totalOrders,
    required this.totalPurchaseValue,
    required this.averageOrderValue,
    required this.lastPurchaseDate,
    required this.totalItems,
    required this.onTimeDeliveryRate,
  });

  factory SupplierAnalysisRow.fromJson(Map<String, dynamic> json) =>
      SupplierAnalysisRow(
        supplierId: asInt(json['supplier_id']) ?? 0,
        supplierName: asString(json['supplier_name']) ?? '',
        supplierCode: asString(json['supplier_code']) ?? '',
        email: asString(json['email']) ?? '',
        phone: asString(json['phone']) ?? '',
        totalOrders: asNum(json['total_orders']) ?? 0,
        totalPurchaseValue: asNum(json['total_purchase_value']) ?? 0,
        averageOrderValue: asNum(json['average_order_value']) ?? 0,
        lastPurchaseDate: asString(json['last_purchase_date']) ?? '',
        totalItems: asNum(json['total_items']) ?? 0,
        onTimeDeliveryRate: asNum(json['on_time_delivery_rate']) ?? 0,
      );

  final int supplierId;
  final String supplierName;
  final String supplierCode;
  final String email;
  final String phone;
  final num totalOrders;
  final num totalPurchaseValue;
  final num averageOrderValue;
  final String lastPurchaseDate;
  final num totalItems;
  final num onTimeDeliveryRate;
}

// ── Production summary (GET /reports/production-summary) ────────────

/// One production-run row of the production summary report.
class ProductionSummaryRow {
  const ProductionSummaryRow({
    required this.workOrderNumber,
    required this.productionDate,
    required this.productionOrderNumber,
    required this.outputItemName,
    required this.outputQuantity,
    required this.completedQuantity,
    required this.scrappedQuantity,
    required this.plannedQuantity,
    required this.itemName,
    required this.status,
  });

  factory ProductionSummaryRow.fromJson(Map<String, dynamic> json) =>
      ProductionSummaryRow(
        workOrderNumber: asString(json['work_order_number']) ?? '',
        productionDate: asString(json['production_date']) ?? '',
        productionOrderNumber: asString(json['production_order_number']) ?? '',
        outputItemName: asString(json['output_item_name']) ?? '',
        outputQuantity: asNum(json['output_quantity']) ?? 0,
        completedQuantity: asNum(json['completed_quantity']) ?? 0,
        scrappedQuantity: asNum(json['scrapped_quantity']) ?? 0,
        plannedQuantity: asNum(json['planned_quantity']) ?? 0,
        itemName: asString(json['item_name']) ?? '',
        status: asString(json['status']) ?? '',
      );

  final String workOrderNumber;
  final String productionDate;
  final String productionOrderNumber;
  final String outputItemName;
  final num outputQuantity;
  final num completedQuantity;
  final num scrappedQuantity;
  final num plannedQuantity;
  final String itemName;
  final String status;
}

/// Period totals for the production summary report (camelCase keys;
/// the server computes them from the same rows its grid shows).
class ProductionSummaryStats {
  const ProductionSummaryStats({
    required this.totalProductionOrders,
    required this.totalOutput,
    required this.totalCompleted,
    required this.totalScrapped,
  });

  factory ProductionSummaryStats.fromJson(Map<String, dynamic> json) =>
      ProductionSummaryStats(
        totalProductionOrders: asNum(json['totalProductionOrders']) ?? 0,
        totalOutput: asNum(json['totalOutput']) ?? 0,
        totalCompleted: asNum(json['totalCompleted']) ?? 0,
        totalScrapped: asNum(json['totalScrapped']) ?? 0,
      );

  final num totalProductionOrders;
  final num totalOutput;
  final num totalCompleted;
  final num totalScrapped;
}

class ProductionSummaryReport {
  const ProductionSummaryReport({required this.rows, required this.summary});

  factory ProductionSummaryReport.fromJson(Map<String, dynamic> json) =>
      ProductionSummaryReport(
        rows: [
          for (final row in json['production'] as List? ?? const [])
            ProductionSummaryRow.fromJson(row as Map<String, dynamic>),
        ],
        summary: ProductionSummaryStats.fromJson(
          json['summary'] as Map<String, dynamic>? ?? const {},
        ),
      );

  final List<ProductionSummaryRow> rows;
  final ProductionSummaryStats summary;
}

// ── BOM usage (GET /reports/bom-usage) ──────────────────────────────

/// One BOM row of the bom-usage report. The endpoint returns
/// `{ usage: [...] }`; dates default to all-time and an optional
/// `itemId` narrows to a finished item.
class BomUsageRow {
  const BomUsageRow({
    required this.bomId,
    required this.bomName,
    required this.parentItemName,
    required this.usageCount,
    required this.lastUsedDate,
    required this.totalComponents,
    required this.status,
  });

  factory BomUsageRow.fromJson(Map<String, dynamic> json) => BomUsageRow(
    bomId: asInt(json['bom_id']) ?? 0,
    bomName: asString(json['bom_name']) ?? '',
    parentItemName: asString(json['parent_item_name']) ?? '',
    usageCount: asNum(json['usage_count']) ?? 0,
    lastUsedDate: asString(json['last_used_date']),
    totalComponents: asNum(json['total_components']) ?? 0,
    status: asString(json['status']) ?? '',
  );

  final int bomId;
  final String bomName;
  final String parentItemName;
  final num usageCount;
  final String? lastUsedDate;
  final num totalComponents;
  final String status;
}

class BomUsageReport {
  const BomUsageReport({required this.rows});

  factory BomUsageReport.fromJson(Map<String, dynamic> json) => BomUsageReport(
    rows: [
      for (final row in json['usage'] as List? ?? const [])
        BomUsageRow.fromJson(row as Map<String, dynamic>),
    ],
  );

  final List<BomUsageRow> rows;
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
