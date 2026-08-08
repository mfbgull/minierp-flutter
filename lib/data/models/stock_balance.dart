import 'json_helpers.dart';

/// Row of `GET /inventory/stock-balances` and the `stock_by_warehouse`
/// breakdown on item detail.
class StockBalance {
  const StockBalance({
    required this.itemId,
    required this.itemCode,
    required this.itemName,
    required this.warehouseId,
    required this.warehouseCode,
    required this.warehouseName,
    required this.quantity,
    this.lastUpdated,
  });

  factory StockBalance.fromJson(Map<String, dynamic> json) => StockBalance(
    itemId: asInt(json['item_id']) ?? 0,
    itemCode: asString(json['item_code']) ?? '',
    itemName: asString(json['item_name']) ?? '',
    warehouseId: asInt(json['warehouse_id']) ?? 0,
    warehouseCode: asString(json['warehouse_code']) ?? '',
    warehouseName: asString(json['warehouse_name']) ?? '',
    quantity: (json['quantity'] as num?) ?? 0,
    lastUpdated: asString(json['last_updated']),
  );

  final int itemId;
  final String itemCode;
  final String itemName;
  final int warehouseId;
  final String warehouseCode;
  final String warehouseName;
  final num quantity;
  final String? lastUpdated;

  Map<String, dynamic> toJson() => {
    'item_id': itemId,
    'item_code': itemCode,
    'item_name': itemName,
    'warehouse_id': warehouseId,
    'warehouse_code': warehouseCode,
    'warehouse_name': warehouseName,
    'quantity': quantity,
    if (lastUpdated != null) 'last_updated': lastUpdated,
  };
}
