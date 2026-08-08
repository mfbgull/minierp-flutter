// Sales (invoice) return models — port of the server's
// `InvoiceModel.getReturnHistory` row + `returnInvoiceItems` result.
//
// Envelope variants observed on the server (PORTING.md §2):
// - `GET /invoices/returns` → **bare array** of `RETURN` stock-movement
//   rows (no envelope, no pagination; filters: start_date, end_date,
//   item_id, limit) — `InvoiceModel.getReturnHistory`
// - `POST /invoices/:id/return` → **enveloped** `{success, message,
//   data: {returnedItems, totalItems, disposition, returnAmount,
//   netReturn, deduction}}`

import 'json_helpers.dart';

/// One row of `GET /invoices/returns`. The endpoint returns stock-movement
/// rows where `reference_doctype = 'RETURN'` and `quantity > 0` (returns
/// put stock back into the warehouse, hence the positive sign — unlike
/// purchase returns). All money/quantity fields arrive as
/// `number | string` (SQLite), so they are normalised with [asNum].
class SalesReturn {
  const SalesReturn({
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
    this.invoiceNo,
    this.remarks,
    this.returnDate = '',
    this.createdAt,
    this.createdByUsername,
    this.customerName,
    this.customerId,
  });

  factory SalesReturn.fromJson(Map<String, dynamic> json) => SalesReturn(
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
    invoiceNo: asString(json['invoice_no']),
    remarks: asString(json['remarks']),
    returnDate: asString(json['return_date']) ?? '',
    createdAt: asString(json['created_at']),
    createdByUsername: asString(json['created_by_username']),
    customerName: asString(json['customer_name']),
    customerId: asInt(json['customer_id']),
  );

  final int id;
  final String movementNo;
  final int itemId;
  final String itemName;
  final String itemCode;
  final String unitOfMeasure;
  final int warehouseId;
  final String warehouseName;

  /// Positive on the wire (returns restock the warehouse).
  final num quantity;
  final num unitCost;
  final String referenceDocType;

  /// The invoice this return came from (`reference_docno` alias).
  final String? invoiceNo;
  final String? remarks;
  final String returnDate;
  final String? createdAt;
  final String? createdByUsername;
  final String? customerName;
  final int? customerId;

  /// Total value of the returned line.
  num get returnValue => quantity * unitCost;
}

/// The `data` payload of `POST /invoices/:id/return`.
class SalesReturnResult {
  const SalesReturnResult({
    this.returnedItems = const [],
    this.totalItems = 0,
    this.disposition,
    this.returnAmount = 0,
    this.netReturn = 0,
    this.deduction = 0,
  });

  factory SalesReturnResult.fromJson(Map<String, dynamic> json) =>
      SalesReturnResult(
        returnedItems: json['returnedItems'] is List
            ? [
                for (final row in json['returnedItems'] as List)
                  if (row is Map<String, dynamic>) row,
              ]
            : const [],
        totalItems: asInt(json['totalItems']) ?? 0,
        disposition: asString(json['disposition']),
        returnAmount: asNum(json['returnAmount']) ?? 0,
        netReturn: asNum(json['netReturn']) ?? 0,
        deduction: asNum(json['deduction']) ?? 0,
      );

  final List<Map<String, dynamic>> returnedItems;
  final int totalItems;
  final String? disposition;

  /// Gross value of the returned lines (before any restocking fee).
  final num returnAmount;

  /// Gross minus any restocking-fee deduction.
  final num netReturn;
  final num deduction;
}
