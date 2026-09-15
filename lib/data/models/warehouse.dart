import 'json_helpers.dart';

/// Port of `Warehouse` (server `WarehouseModel` + `types/client-types.ts`).
class Warehouse {
  const Warehouse({
    required this.id,
    required this.warehouseCode,
    this.warehouseName,
    this.location,
    this.isActive = true,
    this.isSystem = false,
    this.createdAt,
    this.updatedAt,
    this.totalItems = 0,
    this.uniqueItems = 0,
  });

  factory Warehouse.fromJson(Map<String, dynamic> json) => Warehouse(
    id: asInt(json['id']) ?? 0,
    warehouseCode: asString(json['warehouse_code']) ?? '',
    warehouseName: asString(json['warehouse_name']),
    location: asString(json['location']),
    isActive: asBool(json['is_active'], fallback: true),
    // System warehouses (EXPIRED / DAMAGED) are permanent infrastructure —
    // seeded by add-expired-stock.sql, guarded against deletion server-side.
    isSystem: asBool(json['is_system'], fallback: false),
    createdAt: asString(json['created_at']),
    updatedAt: asString(json['updated_at']),
    totalItems: asNum(json['total_items']) ?? 0,
    uniqueItems: asNum(json['unique_items']) ?? 0,
  );

  final int id;
  final String warehouseCode;
  final String? warehouseName;
  final String? location;
  final bool isActive;

  /// True for seeded system warehouses (EXPIRED, DAMAGED). These are
  /// non-deletable (server 400 + DB trigger) and excluded from the delete
  /// UI. Read-only in the app — never sent in create/update bodies.
  final bool isSystem;
  final String? createdAt;
  final String? updatedAt;
  final num totalItems;
  final num uniqueItems;

  Map<String, dynamic> toJson() => {
    'id': id,
    'warehouse_code': warehouseCode,
    if (warehouseName != null) 'warehouse_name': warehouseName,
    if (location != null) 'location': location,
    'is_active': isActive ? 1 : 0,
    if (createdAt != null) 'created_at': createdAt,
    if (updatedAt != null) 'updated_at': updatedAt,
  };
}
