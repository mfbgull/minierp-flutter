import 'json_helpers.dart';

/// Stock movement types — matches the server enum used in
/// `StockMovementModel` and the docs/API.md values.
enum MovementType {
  purchase('PURCHASE'),
  sale('SALE'),
  transfer('TRANSFER'),
  production('PRODUCTION'),
  adjustment('ADJUSTMENT');

  const MovementType(this.value);

  final String value;

  static MovementType fromString(Object? value) => values.firstWhere(
        (e) => e.value == value,
        orElse: () => MovementType.adjustment,
      );
}

/// Port of `StockMovement` (server `StockMovementModel`).
class StockMovement {
  const StockMovement({
    required this.id,
    required this.movementNo,
    required this.itemId,
    required this.warehouseId,
    required this.movementType,
    required this.quantity,
    this.unitCost,
    this.referenceDocType,
    this.referenceDocNo,
    this.remarks,
    required this.movementDate,
    this.createdBy,
    this.createdAt,
    this.itemCode,
    this.itemName,
    this.unitOfMeasure,
    this.warehouseCode,
    this.warehouseName,
    this.createdByName,
  });

  factory StockMovement.fromJson(Map<String, dynamic> json) => StockMovement(
        id: asInt(json['id']) ?? 0,
        movementNo: asString(json['movement_no']) ?? '',
        itemId: asInt(json['item_id']) ?? 0,
        warehouseId: asInt(json['warehouse_id']) ?? 0,
        movementType: MovementType.fromString(json['movement_type']).value,
        quantity: (json['quantity'] as num?) ?? 0,
        unitCost: asNum(json['unit_cost']),
        referenceDocType: asString(json['reference_doctype']),
        referenceDocNo: asString(json['reference_docno']),
        remarks: asString(json['remarks']),
        movementDate: asString(json['movement_date']) ?? '',
        createdBy: asInt(json['created_by']),
        createdAt: asString(json['created_at']),
        itemCode: asString(json['item_code']),
        itemName: asString(json['item_name']),
        unitOfMeasure: asString(json['unit_of_measure']),
        warehouseCode: asString(json['warehouse_code']),
        warehouseName: asString(json['warehouse_name']),
        createdByName: asString(json['created_by_name']),
      );

  final int id;
  final String movementNo;
  final int itemId;
  final int warehouseId;
  final String movementType;
  final num quantity;
  final num? unitCost;
  final String? referenceDocType;
  final String? referenceDocNo;
  final String? remarks;
  final String movementDate;
  final int? createdBy;
  final String? createdAt;
  final String? itemCode;
  final String? itemName;
  final String? unitOfMeasure;
  final String? warehouseCode;
  final String? warehouseName;
  final String? createdByName;

  Map<String, dynamic> toJson() => {
        'id': id,
        'movement_no': movementNo,
        'item_id': itemId,
        'warehouse_id': warehouseId,
        'movement_type': movementType,
        'quantity': quantity,
        if (unitCost != null) 'unit_cost': unitCost,
        if (referenceDocType != null) 'reference_doctype': referenceDocType,
        if (referenceDocNo != null) 'reference_docno': referenceDocNo,
        if (remarks != null) 'remarks': remarks,
        'movement_date': movementDate,
        if (createdBy != null) 'created_by': createdBy,
        if (createdAt != null) 'created_at': createdAt,
      };
}
