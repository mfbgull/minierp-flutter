import '../models/json_helpers.dart';

enum BatchStatus {
  normal('normal'),
  nearExpiry('near_expiry'),
  expired('expired'),
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
}
