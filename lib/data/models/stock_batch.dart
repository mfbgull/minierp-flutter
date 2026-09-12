import '../models/json_helpers.dart';

enum BatchStatus {
  active('ACTIVE'),
  blocked('BLOCKED'),
  quarantined('QUARANTINED'),
  expired('EXPIRED'),
  damaged('DAMAGED'),
  rejected('REJECTED'),
  nearExpiry('near_expiry'),
  normal('normal'),
  halted('halted');

  const BatchStatus(this.value);
  final String value;
  static BatchStatus fromString(Object? value) =>
      values.firstWhere((e) => e.value == value, orElse: () => BatchStatus.normal);
}

class StockBatch {
  const StockBatch({
    required this.id,
    required this.batchNo,
    required this.itemId,
    required this.warehouseId,
    required this.sourceType,
    required this.sourceId,
    required this.quantityOriginal,
    required this.quantityRemaining,
    required this.unitCost,
    required this.receivedDate,
    this.expiryDate,
    this.halted = false,
    this.haltedReason,
    // Joined fields
    this.itemCode,
    this.itemName,
    this.warehouseCode,
    this.warehouseName,
    this.sourceNo,
    this.locations,
    this.effectiveStatus,
  });

  factory StockBatch.fromJson(Map<String, dynamic> json) => StockBatch(
    id: asInt(json['id']) ?? 0,
    batchNo: asString(json['batch_no']) ?? '',
    itemId: asInt(json['item_id']) ?? 0,
    warehouseId: asInt(json['warehouse_id']) ?? 0,
    sourceType: asString(json['source_type']) ?? '',
    sourceId: asInt(json['source_id']) ?? 0,
    quantityOriginal: asNum(json['quantity_original']) ?? 0,
    quantityRemaining: asNum(json['quantity_remaining']) ?? 0,
    unitCost: asNum(json['unit_cost']) ?? 0,
    receivedDate: asString(json['received_date']) ?? '',
    expiryDate: asString(json['expiry_date']),
    halted: asBool(json['halted']),
    haltedReason: asString(json['halted_reason']),
    itemCode: asString(json['item_code']),
    itemName: asString(json['item_name']),
    warehouseCode: asString(json['warehouse_code']),
    warehouseName: asString(json['warehouse_name']),
    sourceNo: asString(json['source_no']),
    locations: json['locations'] is List
        ? (json['locations'] as List).map((e) => BatchLocation.fromJson(e as Map<String, dynamic>)).toList()
        : null,
    effectiveStatus: asString(json['effective_status']),
  );

  // Computed status — requires knowing today's date and a threshold
  BatchStatus computeStatus({num nearExpiryThresholdDays = 30}) {
    if (halted) return BatchStatus.halted;
    if (expiryDate == null) return BatchStatus.normal;
    final expiry = DateTime.tryParse(expiryDate!);
    if (expiry == null) return BatchStatus.normal;
    final now = DateTime.now();
    if (expiry.isBefore(now)) return BatchStatus.expired;
    if (expiry.difference(now).inDays <= nearExpiryThresholdDays) {
      return BatchStatus.nearExpiry;
    }
    return BatchStatus.normal;
  }

  bool get isExpired {
    if (expiryDate == null) return false;
    final expiry = DateTime.tryParse(expiryDate!);
    return expiry != null && expiry.isBefore(DateTime.now());
  }

  final int id;
  final String batchNo;
  final int itemId;
  final int warehouseId;
  final String sourceType;
  final int sourceId;
  final num quantityOriginal;
  final num quantityRemaining;
  final num unitCost;
  final String receivedDate;
  final String? expiryDate;
  final bool halted;
  final String? haltedReason;
  final String? itemCode;
  final String? itemName;
  final String? warehouseCode;
  final String? warehouseName;
  final String? sourceNo;
  final List<BatchLocation>? locations;
  final String? effectiveStatus;

  Map<String, dynamic> toJson() => {
    'id': id,
    'batch_no': batchNo,
    'item_id': itemId,
    'warehouse_id': warehouseId,
    'source_type': sourceType,
    'source_id': sourceId,
    'quantity_original': quantityOriginal,
    'quantity_remaining': quantityRemaining,
    'unit_cost': unitCost,
    'received_date': receivedDate,
    if (expiryDate != null) 'expiry_date': expiryDate,
    'halted': halted,
    if (haltedReason != null) 'halted_reason': haltedReason,
    if (itemCode != null) 'item_code': itemCode,
    if (itemName != null) 'item_name': itemName,
    if (warehouseCode != null) 'warehouse_code': warehouseCode,
    if (warehouseName != null) 'warehouse_name': warehouseName,
    if (sourceNo != null) 'source_no': sourceNo,
    if (locations != null) 'locations': locations!.map((e) => e.toJson()).toList(),
    if (effectiveStatus != null) 'effective_status': effectiveStatus,
  };
}

class BatchLocation {
  const BatchLocation({
    required this.locationId,
    required this.locationCode,
    this.locationName,
    required this.quantityPhysical,
    required this.quantityReserved,
    required this.quantityAvailable,
    this.statusOverride,
    this.effectiveStatus,
  });

  factory BatchLocation.fromJson(Map<String, dynamic> json) => BatchLocation(
    locationId: asInt(json['location_id']) ?? 0,
    locationCode: asString(json['location_code']) ?? '',
    locationName: asString(json['location_name']),
    quantityPhysical: asNum(json['quantity_physical']) ?? 0,
    quantityReserved: asNum(json['quantity_reserved']) ?? 0,
    quantityAvailable: asNum(json['quantity_available']) ?? 0,
    statusOverride: asString(json['status_override']),
    effectiveStatus: asString(json['effective_status']),
  );

  final int locationId;
  final String locationCode;
  final String? locationName;
  final num quantityPhysical;
  final num quantityReserved;
  final num quantityAvailable;
  final String? statusOverride;
  final String? effectiveStatus;

  Map<String, dynamic> toJson() => {
    'location_id': locationId,
    'location_code': locationCode,
    if (locationName != null) 'location_name': locationName,
    'quantity_physical': quantityPhysical,
    'quantity_reserved': quantityReserved,
    'quantity_available': quantityAvailable,
    if (statusOverride != null) 'status_override': statusOverride,
    if (effectiveStatus != null) 'effective_status': effectiveStatus,
  };
}
