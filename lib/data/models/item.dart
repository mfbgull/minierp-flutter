import 'json_helpers.dart';

/// `'packed'` (qty drives line amount) or `'loose'` (bidirectional
/// amount-driven lines). Defaults to `packed`.
enum SaleType {
  packed('packed'),
  loose('loose');

  const SaleType(this.value);

  final String value;

  static SaleType fromString(Object? value) =>
      values.firstWhere((e) => e.value == value, orElse: () => SaleType.packed);
}

/// Port of `Item` (types/client-types.ts) + the server Item model.
///
/// `is_raw_material` / `is_finished_good` / `is_purchased` /
/// `is_manufactured` are 0/1 integers from SQLite — `fromJson` parses
/// both booleans and ints.
class Item {
  const Item({
    required this.id,
    required this.itemCode,
    required this.itemName,
    this.description,
    this.category,
    this.rackNo,
    required this.unitOfMeasure,
    this.reorderLevel,
    this.standardCost,
    this.standardSellingPrice,
    this.standardPrice,
    this.purchasePrice,
    required this.currentStock,
    this.isRawMaterial = false,
    this.isFinishedGood = false,
    this.isPurchased = false,
    this.isManufactured = false,
    this.saleType = SaleType.packed,
    this.qtyDecimalPrecision,
    this.roundingStep,
    this.isActive = true,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  factory Item.fromJson(Map<String, dynamic> json) => Item(
    id: asInt(json['id']) ?? 0,
    itemCode: asString(json['item_code']) ?? '',
    itemName: asString(json['item_name']) ?? '',
    description: asString(json['description']),
    category: asString(json['category']),
    rackNo: asString(json['rack_no']),
    unitOfMeasure: asString(json['unit_of_measure']) ?? 'Nos',
    reorderLevel: asNum(json['reorder_level']),
    standardCost: asNum(json['standard_cost']),
    standardSellingPrice: asNum(json['standard_selling_price']),
    standardPrice: asNum(json['standard_price']),
    purchasePrice: asNum(json['purchase_price']),
    currentStock: asNum(json['current_stock']) ?? 0,
    isRawMaterial: asBool(json['is_raw_material']),
    isFinishedGood: asBool(json['is_finished_good']),
    isPurchased: asBool(json['is_purchased']),
    isManufactured: asBool(json['is_manufactured']),
    saleType: SaleType.fromString(json['sale_type']),
    qtyDecimalPrecision: asNum(json['qty_decimal_precision']),
    roundingStep: asNum(json['rounding_step']),
    isActive: asBool(json['is_active'], fallback: true),
    createdBy: asInt(json['created_by']),
    createdAt: asString(json['created_at']),
    updatedAt: asString(json['updated_at']),
  );

  /// True when at/below the reorder threshold — the single low-stock rule
  /// (matches the server's items-low-stock logic and the dashboard's
  /// alerts; `reorderLevel == null` means no threshold).
  bool get isBelowReorder =>
      reorderLevel != null && currentStock <= reorderLevel!;

  final int id;
  final String itemCode;
  final String itemName;
  final String? description;
  final String? category;
  final String? rackNo;
  final String unitOfMeasure;
  final num? reorderLevel;
  final num? standardCost;
  final num? standardSellingPrice;
  final num? standardPrice;
  final num? purchasePrice;
  final num currentStock;
  final bool isRawMaterial;
  final bool isFinishedGood;
  final bool isPurchased;
  final bool isManufactured;
  final SaleType saleType;
  final num? qtyDecimalPrecision;
  final num? roundingStep;
  final bool isActive;
  final int? createdBy;
  final String? createdAt;
  final String? updatedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'item_code': itemCode,
    'item_name': itemName,
    if (description != null) 'description': description,
    if (category != null) 'category': category,
    if (rackNo != null) 'rack_no': rackNo,
    'unit_of_measure': unitOfMeasure,
    if (reorderLevel != null) 'reorder_level': reorderLevel,
    if (standardCost != null) 'standard_cost': standardCost,
    if (standardSellingPrice != null)
      'standard_selling_price': standardSellingPrice,
    if (standardPrice != null) 'standard_price': standardPrice,
    if (purchasePrice != null) 'purchase_price': purchasePrice,
    'current_stock': currentStock,
    'is_raw_material': isRawMaterial ? 1 : 0,
    'is_finished_good': isFinishedGood ? 1 : 0,
    'is_purchased': isPurchased ? 1 : 0,
    'is_manufactured': isManufactured ? 1 : 0,
    'sale_type': saleType.value,
    if (qtyDecimalPrecision != null)
      'qty_decimal_precision': qtyDecimalPrecision,
    if (roundingStep != null) 'rounding_step': roundingStep,
    'is_active': isActive ? 1 : 0,
    if (createdBy != null) 'created_by': createdBy,
    if (createdAt != null) 'created_at': createdAt,
    if (updatedAt != null) 'updated_at': updatedAt,
  };
}
