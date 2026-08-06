// PurchaseReturn — one row of `GET /purchases/returns` (the server's
// `Purchase.getReturnHistory`). The endpoint returns a **bare array** of
// stock-movement rows where `reference_doctype IN ('PURCHASE_RETURN',
// 'PO_RETURN')` and `quantity < 0` (returns leave the warehouse, hence
// the negative sign). All money/quantity fields arrive as
// `number | string` (SQLite), so they are normalised with [asNum].

import 'json_helpers.dart';

/// A purchase return row.
class PurchaseReturn {
  const PurchaseReturn({
    required this.id,
    this.movementNo = '',
    required this.itemId,
    required this.itemName,
    this.itemCode = '',
    this.unitOfMeasure = '',
    required this.warehouseId,
    this.warehouseName = '',
    required this.quantity,
    this.unitCost = 0,
    this.referenceDocType = '',
    this.referenceDocNo,
    this.remarks,
    this.returnDate = '',
    this.createdAt,
    this.createdByUsername,
  });

  factory PurchaseReturn.fromJson(Map<String, dynamic> json) =>
      PurchaseReturn(
        id: asInt(json['id']) ?? 0,
        movementNo: asString(json['movement_no']) ?? '',
        itemId: asInt(json['item_id']) ?? 0,
        itemName: asString(json['item_name']) ?? '',
        itemCode: asString(json['item_code']) ?? '',
        unitOfMeasure: asString(json['unit_of_measure']) ?? '',
        warehouseId: asInt(json['warehouse_id']) ?? 0,
        warehouseName: asString(json['warehouse_name']) ?? '',
        quantity: asNum(json['quantity']) ?? 0,
        unitCost: asNum(json['unit_cost']) ?? 0,
        referenceDocType: asString(json['reference_doctype']) ?? '',
        referenceDocNo: asString(json['reference_docno']),
        remarks: asString(json['remarks']),
        returnDate: asString(json['return_date']) ?? '',
        createdAt: asString(json['created_at']),
        createdByUsername: asString(json['created_by_username']),
      );

  final int id;
  final String movementNo;
  final int itemId;
  final String itemName;
  final String itemCode;
  final String unitOfMeasure;
  final int warehouseId;
  final String warehouseName;

  /// Negative on the wire (returns reduce stock) — the UI always renders
  /// the magnitude via [returnQty].
  final num quantity;
  final num unitCost;
  final String referenceDocType;

  /// The original purchase / PO document this return came from.
  final String? referenceDocNo;
  final String? remarks;
  final String returnDate;
  final String? createdAt;
  final String? createdByUsername;

  /// Display quantity (the server stores returns as negative movements).
  num get returnQty => quantity.abs();

  /// Total value of the returned line.
  num get returnValue => returnQty * unitCost;
}
