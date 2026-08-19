// Purchase models — port of `Purchase` (types/client-types.ts) plus the
// joined fields the server's `Purchase.getAll`/`getById` add
// (item_code, item_name, unit_of_measure, warehouse_code/name,
// created_by_username) and `returned_quantity` (add-purchase-return-
// fields.sql migration). One purchase = one item line, so the list rows
// and the detail object carry the same shape.
//
// Envelope variants observed on the server (PORTING.md §2):
// - `GET /purchases` → **bare array** `[Purchase]` (filters: start_date,
//   end_date, item_id, warehouse_id, supplier_name, limit)
// - `GET /purchases/:id` → **bare object** (same joined shape)
// - `POST /purchases/:id/return` → **enveloped** `{success, message,
//   data: {returnedQuantity, totalCost}}`

import 'json_helpers.dart';

/// A direct-purchase row. Money/quantity fields arrive as
/// `number | string` (SQLite), so they are normalised with [asNum].
class Purchase {
  const Purchase({
    required this.id,
    required this.purchaseNo,
    required this.purchaseDate,
    required this.itemId,
    this.itemCode = '',
    required this.itemName,
    this.unitOfMeasure = '',
    required this.quantity,
    this.unitCost = 0,
    this.totalCost = 0,
    this.paidAmount = 0,
    this.balanceAmount = 0,
    this.supplierId,
    this.supplierName,
    required this.warehouseId,
    this.warehouseName = '',
    this.invoiceNo,
    this.remarks,
    this.returnedQuantity = 0,
    this.createdByUsername,
  });

  factory Purchase.fromJson(Map<String, dynamic> json) => Purchase(
    id: asInt(json['id']) ?? 0,
    purchaseNo: asString(json['purchase_no']) ?? '',
    purchaseDate: asString(json['purchase_date']) ?? '',
    itemId: asInt(json['item_id']) ?? 0,
    itemCode: asString(json['item_code']) ?? '',
    itemName: asString(json['item_name']) ?? '',
    unitOfMeasure: asString(json['unit_of_measure']) ?? '',
    quantity: asNum(json['quantity']) ?? 0,
    unitCost: asNum(json['unit_cost']) ?? 0,
    totalCost: asNum(json['total_cost']) ?? 0,
    paidAmount: asNum(json['paid_amount']) ?? 0,
    balanceAmount: asNum(json['balance_amount']) ?? 0,
    supplierId: asInt(json['supplier_id']),
    supplierName: asString(json['supplier_name']),
    warehouseId: asInt(json['warehouse_id']) ?? 0,
    warehouseName: asString(json['warehouse_name']) ?? '',
    invoiceNo: asString(json['invoice_no']),
    remarks: asString(json['remarks']),
    returnedQuantity: asNum(json['returned_quantity']) ?? 0,
    createdByUsername: asString(json['created_by_username']),
  );

  final int id;
  final String purchaseNo;
  final String purchaseDate;
  final int itemId;
  final String itemCode;
  final String itemName;
  final String unitOfMeasure;
  final num quantity;
  final num unitCost;
  final num totalCost;
  final num paidAmount;
  final num balanceAmount;
  final int? supplierId;
  final String? supplierName;
  final int warehouseId;
  final String warehouseName;
  final String? invoiceNo;
  final String? remarks;
  final num returnedQuantity;
  final String? createdByUsername;

  /// How much of this purchase can still be returned.
  num get returnableQty {
    final available = quantity - returnedQuantity;
    return available < 0 ? 0 : available;
  }
}
