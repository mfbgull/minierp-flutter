import 'json_helpers.dart';

enum ReservationStatus {
  active('ACTIVE'),
  released('RELEASED'),
  consumed('CONSUMED'),
  expired('EXPIRED');

  const ReservationStatus(this.value);
  final String value;
  static ReservationStatus fromString(Object? value) =>
      values.firstWhere((e) => e.value == value, orElse: () => ReservationStatus.active);
}

class StockReservation {
  const StockReservation({
    required this.id,
    required this.itemId,
    required this.warehouseId,
    this.locationId,
    this.batchId,
    required this.quantityReserved,
    required this.referenceDocType,
    required this.referenceDocNo,
    this.referenceLineId,
    required this.status,
    required this.createdAt,
    this.releasedAt,
    this.consumedAt,
    // Joined fields
    this.itemCode,
    this.itemName,
    this.locationCode,
    this.batchNo,
  });

  factory StockReservation.fromJson(Map<String, dynamic> json) => StockReservation(
    id: asInt(json['id']) ?? 0,
    itemId: asInt(json['item_id']) ?? 0,
    warehouseId: asInt(json['warehouse_id']) ?? 0,
    locationId: asInt(json['location_id']),
    batchId: asInt(json['batch_id']),
    quantityReserved: asNum(json['quantity_reserved']) ?? 0,
    referenceDocType: asString(json['reference_doctype']) ?? '',
    referenceDocNo: asString(json['reference_docno']) ?? '',
    referenceLineId: asInt(json['reference_line_id']),
    status: ReservationStatus.fromString(json['status']).value,
    createdAt: asString(json['created_at']) ?? '',
    releasedAt: asString(json['released_at']),
    consumedAt: asString(json['consumed_at']),
    itemCode: asString(json['item_code']),
    itemName: asString(json['item_name']),
    locationCode: asString(json['location_code']),
    batchNo: asString(json['batch_no']),
  );

  final int id;
  final int itemId;
  final int warehouseId;
  final int? locationId;
  final int? batchId;
  final num quantityReserved;
  final String referenceDocType;
  final String referenceDocNo;
  final int? referenceLineId;
  final String status;
  final String createdAt;
  final String? releasedAt;
  final String? consumedAt;
  final String? itemCode;
  final String? itemName;
  final String? locationCode;
  final String? batchNo;

  bool get isActive => status == ReservationStatus.active.value;

  Map<String, dynamic> toJson() => {
    'id': id,
    'item_id': itemId,
    'warehouse_id': warehouseId,
    if (locationId != null) 'location_id': locationId,
    if (batchId != null) 'batch_id': batchId,
    'quantity_reserved': quantityReserved,
    'reference_doctype': referenceDocType,
    'reference_docno': referenceDocNo,
    if (referenceLineId != null) 'reference_line_id': referenceLineId,
    'status': status,
    'created_at': createdAt,
    if (releasedAt != null) 'released_at': releasedAt,
    if (consumedAt != null) 'consumed_at': consumedAt,
  };
}
