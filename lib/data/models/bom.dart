import 'json_helpers.dart';

/// Port of the BOM types (`BOMListItem` / `BOMDetail` / `BOMItemData` in
/// types/client-types.ts) plus the server `BOMModel` shapes.
///
/// `is_active` arrives as a SQLite 0/1 integer — `fromJson` parses both
/// booleans and ints. Decimal fields are JSON numbers.

/// One material line on a `bom_items` row (joined with the item).
class BomItem {
  const BomItem({
    required this.id,
    required this.itemId,
    this.itemCode = '',
    this.itemName = '',
    this.unitOfMeasure,
    this.currentStock,
    required this.quantity,
    this.standardCost,
    this.lineCost,
  });

  factory BomItem.fromJson(Map<String, dynamic> json) => BomItem(
    id: asInt(json['id']) ?? 0,
    itemId: asInt(json['item_id']) ?? 0,
    itemCode: asString(json['item_code']) ?? '',
    itemName: asString(json['item_name']) ?? '',
    unitOfMeasure: asString(json['unit_of_measure']),
    currentStock: asNum(json['current_stock']),
    quantity: asNum(json['quantity']) ?? 0,
    standardCost: asNum(json['standard_cost']),
    lineCost: asNum(json['line_cost']),
  );

  final int id;

  /// The material item id (may be 0 on form lines not yet persisted).
  final int itemId;
  final String itemCode;
  final String itemName;
  final String? unitOfMeasure;

  /// Item quantity-hand at query time (detail endpoint only).
  final num? currentStock;
  final num quantity;

  /// The item's standard cost at query time (detail endpoint only).
  final num? standardCost;

  /// Quantity × standard cost, computed server-side (detail only).
  final num? lineCost;
}

/// A BOM header — one row of `GET /boms`. The list payload carries the
/// joined finished-item fields and the aggregates ([itemCount],
/// [totalMaterialCost]); the detail endpoint adds `items`.
class Bom {
  const Bom({
    required this.id,
    required this.bomNo,
    required this.bomName,
    required this.finishedItemId,
    this.finishedItemCode,
    this.finishedItemName,
    this.finishedUom,
    required this.quantity,
    this.description,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
    this.itemCount,
    this.totalMaterialCost,
  });

  factory Bom.fromJson(Map<String, dynamic> json) => Bom(
    id: asInt(json['id']) ?? 0,
    bomNo: asString(json['bom_no']) ?? '',
    bomName: asString(json['bom_name']) ?? '',
    finishedItemId: asInt(json['finished_item_id']) ?? 0,
    finishedItemCode: asString(json['finished_item_code']),
    finishedItemName: asString(json['finished_item_name']),
    finishedUom: asString(json['finished_uom']),
    quantity: asNum(json['quantity']) ?? 1,
    description: asString(json['description']),
    isActive: asBool(json['is_active'], fallback: true),
    createdAt: asString(json['created_at']),
    updatedAt: asString(json['updated_at']),
    itemCount: asInt(json['item_count']),
    totalMaterialCost: asNum(json['total_material_cost']),
  );

  final int id;
  final String bomNo;
  final String bomName;
  final int finishedItemId;
  final String? finishedItemCode;
  final String? finishedItemName;
  final String? finishedUom;

  /// Finished-good quantity one batch of this BOM produces.
  final num quantity;
  final String? description;
  final bool isActive;
  final String? createdAt;
  final String? updatedAt;
  final int? itemCount;
  final num? totalMaterialCost;
}

/// A BOM plus its material lines — `GET /boms/:id` (and the create /
/// update / toggle endpoints' return values).
class BomDetail extends Bom {
  const BomDetail({
    required super.id,
    required super.bomNo,
    required super.bomName,
    required super.finishedItemId,
    super.finishedItemCode,
    super.finishedItemName,
    super.finishedUom,
    required super.quantity,
    super.description,
    super.isActive,
    super.createdAt,
    super.updatedAt,
    super.itemCount,
    super.totalMaterialCost,
    required this.items,
  });

  factory BomDetail.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    return BomDetail(
      id: asInt(json['id']) ?? 0,
      bomNo: asString(json['bom_no']) ?? '',
      bomName: asString(json['bom_name']) ?? '',
      finishedItemId: asInt(json['finished_item_id']) ?? 0,
      finishedItemCode: asString(json['finished_item_code']),
      finishedItemName: asString(json['finished_item_name']),
      finishedUom: asString(json['finished_uom']),
      quantity: asNum(json['quantity']) ?? 1,
      description: asString(json['description']),
      isActive: asBool(json['is_active'], fallback: true),
      createdAt: asString(json['created_at']),
      updatedAt: asString(json['updated_at']),
      itemCount: asInt(json['item_count']),
      totalMaterialCost: asNum(json['total_material_cost']),
      items: raw is List
          ? [
              for (final row in raw)
                if (row is Map<String, dynamic>) BomItem.fromJson(row),
            ]
          : const [],
    );
  }

  final List<BomItem> items;
}
