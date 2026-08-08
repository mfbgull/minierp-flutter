import 'json_helpers.dart';

/// Physical count status — matches server `PhysicalCountModel`.
enum PhysicalCountStatus { draft, inProgress, completed, cancelled }

extension PhysicalCountStatusX on PhysicalCountStatus {
  static PhysicalCountStatus fromString(String value) =>
      switch (value.toLowerCase()) {
        'completed' => PhysicalCountStatus.completed,
        'in progress' => PhysicalCountStatus.inProgress,
        'cancelled' => PhysicalCountStatus.cancelled,
        _ => PhysicalCountStatus.draft,
      };

  String get value => switch (this) {
    PhysicalCountStatus.draft => 'Draft',
    PhysicalCountStatus.inProgress => 'In Progress',
    PhysicalCountStatus.completed => 'Completed',
    PhysicalCountStatus.cancelled => 'Cancelled',
  };
}

class PhysicalCount {
  const PhysicalCount({
    required this.id,
    required this.countNo,
    required this.countDate,
    required this.warehouseId,
    required this.status,
    this.notes,
    required this.createdBy,
    this.completedBy,
    this.completedAt,
    this.createdAt,
    this.updatedAt,
    this.warehouseCode,
    this.warehouseName,
    this.createdByName,
    this.completedByName,
    this.totalItems,
    this.countedItems,
    this.varianceItems,
  });

  factory PhysicalCount.fromJson(Map<String, dynamic> json) => PhysicalCount(
    id: asInt(json['id']) ?? 0,
    countNo: asString(json['count_no']) ?? '',
    countDate: asString(json['count_date']) ?? '',
    warehouseId: asInt(json['warehouse_id']) ?? 0,
    status: PhysicalCountStatusX.fromString(
      asString(json['status']) ?? 'Draft',
    ).value,
    notes: asString(json['notes']),
    createdBy: asInt(json['created_by']) ?? 0,
    completedBy: asInt(json['completed_by']),
    completedAt: asString(json['completed_at']),
    createdAt: asString(json['created_at']),
    updatedAt: asString(json['updated_at']),
    warehouseCode: asString(json['warehouse_code']),
    warehouseName: asString(json['warehouse_name']),
    createdByName: asString(json['created_by_name']),
    completedByName: asString(json['completed_by_name']),
    totalItems: asNum(json['total_items']),
    countedItems: asNum(json['counted_items']),
    varianceItems: asNum(json['variance_items']),
  );

  final int id;
  final String countNo;
  final String countDate;
  final int warehouseId;
  final String status;
  final String? notes;
  final int createdBy;
  final int? completedBy;
  final String? completedAt;
  final String? createdAt;
  final String? updatedAt;
  final String? warehouseCode;
  final String? warehouseName;
  final String? createdByName;
  final String? completedByName;
  final num? totalItems;
  final num? countedItems;
  final num? varianceItems;

  bool get isDraft => status == PhysicalCountStatus.draft.value;
  bool get isInProgress => status == PhysicalCountStatus.inProgress.value;
  bool get isCompleted => status == PhysicalCountStatus.completed.value;
  bool get isCancelled => status == PhysicalCountStatus.cancelled.value;

  Map<String, dynamic> toJson() => {
    'id': id,
    'count_no': countNo,
    'count_date': countDate,
    'warehouse_id': warehouseId,
    'status': status,
    if (notes != null) 'notes': notes,
    'created_by': createdBy,
    if (completedBy != null) 'completed_by': completedBy,
    if (completedAt != null) 'completed_at': completedAt,
    if (createdAt != null) 'created_at': createdAt,
    if (updatedAt != null) 'updated_at': updatedAt,
  };
}

class PhysicalCountItem {
  const PhysicalCountItem({
    required this.id,
    required this.countId,
    required this.itemId,
    required this.systemQuantity,
    this.countedQuantity,
    this.variance,
    this.unitCost,
    this.varianceValue,
    required this.adjustmentPosted,
    this.adjustmentMovementId,
    this.countedAt,
    this.countedBy,
    this.notes,
    this.createdAt,
    this.itemCode,
    this.itemName,
    this.unitOfMeasure,
    this.category,
    this.countedByName,
  });

  factory PhysicalCountItem.fromJson(Map<String, dynamic> json) =>
      PhysicalCountItem(
        id: asInt(json['id']) ?? 0,
        countId: asInt(json['count_id']) ?? 0,
        itemId: asInt(json['item_id']) ?? 0,
        systemQuantity: (json['system_quantity'] as num?) ?? 0,
        countedQuantity: asNum(json['counted_quantity']),
        variance: asNum(json['variance']),
        unitCost: asNum(json['unit_cost']),
        varianceValue: asNum(json['variance_value']),
        adjustmentPosted:
            json['adjustment_posted'] == true || json['adjustment_posted'] == 1,
        adjustmentMovementId: asInt(json['adjustment_movement_id']),
        countedAt: asString(json['counted_at']),
        countedBy: asInt(json['counted_by']),
        notes: asString(json['notes']),
        createdAt: asString(json['created_at']),
        itemCode: asString(json['item_code']),
        itemName: asString(json['item_name']),
        unitOfMeasure: asString(json['unit_of_measure']),
        category: asString(json['category']),
        countedByName: asString(json['counted_by_name']),
      );

  final int id;
  final int countId;
  final int itemId;
  final num systemQuantity;
  final num? countedQuantity;
  final num? variance;
  final num? unitCost;
  final num? varianceValue;
  final bool adjustmentPosted;
  final int? adjustmentMovementId;
  final String? countedAt;
  final int? countedBy;
  final String? notes;
  final String? createdAt;
  final String? itemCode;
  final String? itemName;
  final String? unitOfMeasure;
  final String? category;
  final String? countedByName;

  Map<String, dynamic> toJson() => {
    'id': id,
    'count_id': countId,
    'item_id': itemId,
    'system_quantity': systemQuantity,
    if (countedQuantity != null) 'counted_quantity': countedQuantity,
    if (variance != null) 'variance': variance,
    if (unitCost != null) 'unit_cost': unitCost,
    if (varianceValue != null) 'variance_value': varianceValue,
    'adjustment_posted': adjustmentPosted ? 1 : 0,
    if (adjustmentMovementId != null)
      'adjustment_movement_id': adjustmentMovementId,
    if (countedAt != null) 'counted_at': countedAt,
    if (countedBy != null) 'counted_by': countedBy,
    if (notes != null) 'notes': notes,
    if (createdAt != null) 'created_at': createdAt,
  };
}
