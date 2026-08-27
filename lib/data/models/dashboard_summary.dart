import 'json_helpers.dart';

// ============================================================
//  DASHBOARD BLOCK ENDPOINT MODELS (PORTING.md §10)
//  Each maps a `GET /dashboard/<block>` response `data` object.
// ============================================================

/// `GET /dashboard/top-customers` row.
class TopCustomer {
  const TopCustomer({
    required this.customerName,
    required this.totalRevenue,
    required this.invoiceCount,
  });

  factory TopCustomer.fromJson(Map<String, dynamic> json) => TopCustomer(
    customerName: asString(json['customer_name']) ?? '',
    totalRevenue: asNum(json['total_revenue']) ?? 0,
    invoiceCount: asInt(json['invoice_count']) ?? 0,
  );

  final String customerName;
  final num totalRevenue;
  final int invoiceCount;
}

/// `GET /dashboard/sales-summary` (period: today|week|month).
class SalesSummaryResult {
  const SalesSummaryResult({required this.periodTotal, required this.count});

  factory SalesSummaryResult.fromJson(Map<String, dynamic> json) =>
      SalesSummaryResult(
        periodTotal: asNum(json['period_total']) ?? 0,
        count: asInt(json['count']) ?? 0,
      );

  final num periodTotal;
  final int count;
}

/// `GET /dashboard/expense-summary` (period: week|month).
class ExpenseSummaryResult {
  const ExpenseSummaryResult({required this.periodTotal, required this.count});

  factory ExpenseSummaryResult.fromJson(Map<String, dynamic> json) =>
      ExpenseSummaryResult(
        periodTotal: asNum(json['period_total']) ?? 0,
        count: asInt(json['count']) ?? 0,
      );

  final num periodTotal;
  final int count;
}

/// `GET /dashboard/production-status`.
class ProductionStatusResult {
  const ProductionStatusResult({
    required this.total,
    required this.active,
    required this.completed,
    required this.cancelled,
  });

  factory ProductionStatusResult.fromJson(Map<String, dynamic> json) =>
      ProductionStatusResult(
        total: asInt(json['total']) ?? 0,
        active: asInt(json['active']) ?? 0,
        completed: asInt(json['completed']) ?? 0,
        cancelled: asInt(json['cancelled']) ?? 0,
      );

  final int total;
  final int active;
  final int completed;
  final int cancelled;
}

/// `GET /dashboard/stock-movement-summary` (days param).
class StockMovementSummaryResult {
  const StockMovementSummaryResult({
    required this.inboundQty,
    required this.outboundQty,
    required this.net,
  });

  factory StockMovementSummaryResult.fromJson(Map<String, dynamic> json) =>
      StockMovementSummaryResult(
        inboundQty: asNum(json['inbound_qty']) ?? 0,
        outboundQty: asNum(json['outbound_qty']) ?? 0,
        net: asNum(json['net']) ?? 0,
      );

  final num inboundQty;
  final num outboundQty;
  final num net;
}

/// `GET /dashboard/kpi?metric=`.
class KpiResult {
  const KpiResult({
    required this.metric,
    required this.value,
    required this.unit,
    required this.label,
  });

  factory KpiResult.fromJson(Map<String, dynamic> json) => KpiResult(
    metric: asString(json['metric']) ?? '',
    value: asNum(json['value']) ?? 0,
    unit: asString(json['unit']) ?? '',
    label: asString(json['label']) ?? '',
  );

  final String metric;
  final num value;
  final String unit;
  final String label;
}

/// `GET /dashboard/ar-summary` — AR total + aging buckets.
class ArSummaryResult {
  const ArSummaryResult({
    required this.totalAr,
    required this.currentAmount,
    required this.amount130,
    required this.amount3160,
    required this.amount6190,
    required this.amountOver90,
    required this.customerCount,
  });

  factory ArSummaryResult.fromJson(Map<String, dynamic> json) =>
      ArSummaryResult(
        totalAr: asNum(json['total_ar']) ?? 0,
        currentAmount: asNum(json['current_amount']) ?? 0,
        amount130: asNum(json['amount_1_30']) ?? 0,
        amount3160: asNum(json['amount_31_60']) ?? 0,
        amount6190: asNum(json['amount_61_90']) ?? 0,
        amountOver90: asNum(json['amount_over_90']) ?? 0,
        customerCount: asInt(json['customer_count']) ?? 0,
      );

  final num totalAr;
  final num currentAmount;
  final num amount130;
  final num amount3160;
  final num amount6190;
  final num amountOver90;
  final int customerCount;
}

/// A low-stock alert row — `GET /dashboard/summary` `lowStockItems`.
class LowStockItem {
  const LowStockItem({
    required this.id,
    required this.itemCode,
    required this.itemName,
    required this.currentStock,
    required this.reorderLevel,
    this.category,
  });

  factory LowStockItem.fromJson(Map<String, dynamic> json) => LowStockItem(
    id: asInt(json['id']) ?? 0,
    itemCode: asString(json['item_code']) ?? '',
    itemName: asString(json['item_name']) ?? '',
    currentStock: asNum(json['current_stock']) ?? 0,
    reorderLevel: asNum(json['reorder_level']) ?? 0,
    category: asString(json['category']),
  );

  final int id;
  final String itemCode;
  final String itemName;
  final num currentStock;
  final num reorderLevel;
  final String? category;
}

/// `stockByCategory` row.
class StockByCategory {
  const StockByCategory({required this.category, required this.totalStock});

  factory StockByCategory.fromJson(Map<String, dynamic> json) =>
      StockByCategory(
        category: asString(json['category']) ?? '',
        totalStock: asNum(json['total_stock']) ?? 0,
      );

  final String category;
  final num totalStock;
}

/// `salesByDay` / `purchasesByDay` row (`{date: YYYY-MM-DD, total}`).
class DayTotal {
  const DayTotal({required this.date, required this.total});

  factory DayTotal.fromJson(Map<String, dynamic> json) => DayTotal(
    date: asString(json['date']) ?? '',
    total: asNum(json['total']) ?? 0,
  );

  final String date;
  final num total;
}

/// One individual money movement behind a cash-account balance.
class CashPositionTransaction {
  const CashPositionTransaction({
    required this.date,
    required this.type,
    required this.reference,
    required this.description,
    required this.amount,
  });

  factory CashPositionTransaction.fromJson(Map<String, dynamic> json) =>
      CashPositionTransaction(
        date: asString(json['date']) ?? '',
        type: asString(json['type']) ?? '',
        reference: asString(json['reference']),
        description: asString(json['description']),
        amount: asNum(json['amount']) ?? 0,
      );

  final String date;

  /// 'payment_received' | 'supplier_payment' | 'expense' | 'salary' |
  /// 'refund' | 'owner_capital' | 'owner_withdrawal'.
  final String type;
  final String? reference;
  final String? description;

  /// Signed: positive = money in, negative = money out.
  final num amount;
}

/// One cash-account row — `GET /dashboard/cash-position` `accounts`.
class CashAccountPosition {
  const CashAccountPosition({
    required this.key,
    required this.name,
    required this.balance,
    required this.opening,
    required this.inflow,
    required this.outflow,
    required this.net,
    required this.transactions,
  });

  factory CashAccountPosition.fromJson(Map<String, dynamic> json) =>
      CashAccountPosition(
        key: asString(json['key']) ?? '',
        name: asString(json['name']) ?? '',
        balance: asNum(json['balance']) ?? 0,
        opening: asNum(json['opening']) ?? 0,
        inflow: asNum(json['inflow']) ?? 0,
        outflow: asNum(json['outflow']) ?? 0,
        net: asNum(json['net']) ?? 0,
        transactions: [
          for (final row in json['transactions'] as List? ?? const [])
            CashPositionTransaction.fromJson(row as Map<String, dynamic>),
        ],
      );

  final String key;
  final String name;
  final num balance;
  final num opening;
  final num inflow;
  final num outflow;
  final num net;
  final List<CashPositionTransaction> transactions;
}

/// One cash-account opening (seed) balance —
/// `GET/PUT /dashboard/cash-opening-balances` `accounts` row.
class CashOpeningBalance {
  const CashOpeningBalance({
    required this.key,
    required this.name,
    required this.amount,
  });

  factory CashOpeningBalance.fromJson(Map<String, dynamic> json) =>
      CashOpeningBalance(
        key: asString(json['key']) ?? '',
        name: asString(json['name']) ?? '',
        amount: asNum(json['amount']) ?? 0,
      );

  final String key;
  final String name;

  /// The starting (seed) balance the business was founded with.
  final num amount;
}

/// `GET/PUT /dashboard/cash-opening-balances` — the opening balances a
/// new business starts with (seeded into the cash-position accounts).
class CashOpeningBalances {
  const CashOpeningBalances({required this.accounts});

  factory CashOpeningBalances.fromJson(Map<String, dynamic> json) =>
      CashOpeningBalances(
        accounts: [
          for (final row in json['accounts'] as List? ?? const [])
            CashOpeningBalance.fromJson(row as Map<String, dynamic>),
        ],
      );

  final List<CashOpeningBalance> accounts;
}

/// Closing balances per cash account as of today —
/// `GET /dashboard/cash-position`.
class CashPositionSummary {
  const CashPositionSummary({
    required this.date,
    required this.accounts,
    required this.total,
  });

  factory CashPositionSummary.fromJson(Map<String, dynamic> json) =>
      CashPositionSummary(
        date: asString(json['date']) ?? '',
        accounts: [
          for (final row in json['accounts'] as List? ?? const [])
            CashAccountPosition.fromJson(row as Map<String, dynamic>),
        ],
        total: asNum(json['total']) ?? 0,
      );

  final String date;
  final List<CashAccountPosition> accounts;
  final num total;
}

/// Aggregated dashboard KPIs — `GET /dashboard/summary`
/// (server/src/models/Dashboard.ts `getSummary`).
class DashboardSummary {
  const DashboardSummary({
    required this.totalItems,
    required this.totalStockValue,
    required this.totalSalesRevenue,
    required this.totalPurchases,
    required this.totalGrossProfit,
    required this.warehouseStockCount,
    required this.lowStockItems,
    required this.stockByCategory,
    required this.salesByDay,
    required this.purchasesByDay,
    required this.recentProductions,
  });

  factory DashboardSummary.fromJson(Map<String, dynamic> json) =>
      DashboardSummary(
        totalItems: asInt(json['totalItems']) ?? 0,
        totalStockValue: asNum(json['totalStockValue']) ?? 0,
        totalSalesRevenue: asNum(json['totalSalesRevenue']) ?? 0,
        totalPurchases: asNum(json['totalPurchases']) ?? 0,
        totalGrossProfit: asNum(json['totalProfit']) ?? 0,
        warehouseStockCount: asInt(json['warehouseStockCount']) ?? 0,
        lowStockItems: _parseList(json['lowStockItems'], LowStockItem.fromJson),
        stockByCategory: _parseList(
          json['stockByCategory'],
          StockByCategory.fromJson,
        ),
        salesByDay: _parseList(json['salesByDay'], DayTotal.fromJson),
        purchasesByDay: _parseList(json['purchasesByDay'], DayTotal.fromJson),
        recentProductions: asInt(json['recentProductions']) ?? 0,
      );

  final int totalItems;
  final num totalStockValue;
  final num totalSalesRevenue;
  final num totalPurchases;
  final num totalGrossProfit;
  final int warehouseStockCount;
  final List<LowStockItem> lowStockItems;
  final List<StockByCategory> stockByCategory;
  final List<DayTotal> salesByDay;
  final List<DayTotal> purchasesByDay;
  final int recentProductions;

  /// Parses a JSON array of objects into typed items, skipping junk rows.
  static List<T> _parseList<T>(
    Object? value,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item is Map<String, dynamic>) fromJson(item),
    ];
  }
}
