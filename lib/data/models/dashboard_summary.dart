import 'json_helpers.dart';

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

/// Aggregated dashboard KPIs — `GET /dashboard/summary`
/// (server/src/models/Dashboard.ts `getSummary`).
class DashboardSummary {
  const DashboardSummary({
    required this.totalItems,
    required this.totalStockValue,
    required this.totalSalesRevenue,
    required this.totalPurchases,
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
