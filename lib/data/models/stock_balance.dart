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
    this.quantityPhysical,
    this.quantityReserved,
    this.quantityAvailable,
    this.locations,
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
    quantityPhysical: asNum(json['quantity_physical']),
    quantityReserved: asNum(json['quantity_reserved']),
    quantityAvailable: asNum(json['quantity_available']),
    locations: json['locations'] is List
        ? (json['locations'] as List).map((e) => BalanceLocation.fromJson(e as Map<String, dynamic>)).toList()
        : null,
    lastUpdated: asString(json['last_updated']),
  );

  final int itemId;
  final String itemCode;
  final String itemName;
  final int warehouseId;
  final String warehouseCode;
  final String warehouseName;
  final num quantity;
  final num? quantityPhysical;
  final num? quantityReserved;
  final num? quantityAvailable;
  final List<BalanceLocation>? locations;
  final String? lastUpdated;

  Map<String, dynamic> toJson() => {
    'item_id': itemId,
    'item_code': itemCode,
    'item_name': itemName,
    'warehouse_id': warehouseId,
    'warehouse_code': warehouseCode,
    'warehouse_name': warehouseName,
    'quantity': quantity,
    if (quantityPhysical != null) 'quantity_physical': quantityPhysical,
    if (quantityReserved != null) 'quantity_reserved': quantityReserved,
    if (quantityAvailable != null) 'quantity_available': quantityAvailable,
    if (locations != null) 'locations': locations!.map((e) => e.toJson()).toList(),
    if (lastUpdated != null) 'last_updated': lastUpdated,
  };
}

class BalanceLocation {
  const BalanceLocation({
    required this.locationId,
    required this.locationCode,
    this.locationName,
    this.quantityPhysical,
    this.quantityReserved,
    this.quantityAvailable,
  });

  factory BalanceLocation.fromJson(Map<String, dynamic> json) => BalanceLocation(
    locationId: asInt(json['location_id']) ?? 0,
    locationCode: asString(json['location_code']) ?? '',
    locationName: asString(json['location_name']),
    quantityPhysical: asNum(json['quantity_physical']),
    quantityReserved: asNum(json['quantity_reserved']),
    quantityAvailable: asNum(json['quantity_available']),
  );

  final int locationId;
  final String locationCode;
  final String? locationName;
  final num? quantityPhysical;
  final num? quantityReserved;
  final num? quantityAvailable;

  Map<String, dynamic> toJson() => {
    'location_id': locationId,
    'location_code': locationCode,
    if (locationName != null) 'location_name': locationName,
    if (quantityPhysical != null) 'quantity_physical': quantityPhysical,
    if (quantityReserved != null) 'quantity_reserved': quantityReserved,
    if (quantityAvailable != null) 'quantity_available': quantityAvailable,
  };
}
