// PurchaseOrder models — port of `PurchaseOrderDetail` /
// `PurchaseOrderDetailItem` (types/client-types.ts) plus the fields the
// server's `PurchaseOrderModel.getAll`/`getById` join in (supplier_name,
// warehouse_name, balance_amount).
//
// Envelope variants observed on the server (PORTING.md §2):
// - `GET /purchase-orders` → **bare array** `[PurchaseOrder]` (filters:
//   supplier_id, status, start_date, end_date, limit — no search/page)
// - `GET /purchase-orders/:id` → **bare object** `{...po, items}`

import 'json_helpers.dart';

/// A purchase order row (list or detail — the detail adds `items` via
/// [PurchaseOrderDetail]). `total_amount` arrives as `number | string`
/// (SQLite), so it is normalised with [asNum].
class PurchaseOrder {
  const PurchaseOrder({
    required this.id,
    required this.poNo,
    required this.poDate,
    required this.supplierId,
    required this.supplierName,
    this.warehouseName,
    this.totalAmount = 0,
    this.paidAmount = 0,
    this.balanceAmount = 0,
    required this.status,
    this.expectedDeliveryDate,
    this.notes,
    this.createdAt,
  });

  factory PurchaseOrder.fromJson(Map<String, dynamic> json) => PurchaseOrder(
    id: asInt(json['id']) ?? 0,
    poNo: asString(json['po_no']) ?? '',
    poDate: asString(json['po_date']) ?? '',
    supplierId: asInt(json['supplier_id']) ?? 0,
    supplierName: asString(json['supplier_name']) ?? '',
    warehouseName: asString(json['warehouse_name']),
    totalAmount: asNum(json['total_amount']) ?? 0,
    paidAmount: asNum(json['paid_amount']) ?? 0,
    balanceAmount: asNum(json['balance_amount']) ?? 0,
    status: asString(json['status']) ?? '',
    expectedDeliveryDate: asString(json['expected_delivery_date']),
    notes: asString(json['notes']),
    createdAt: asString(json['created_at']),
  );

  final int id;
  final String poNo;
  final String poDate;
  final int supplierId;
  final String supplierName;
  final String? warehouseName;
  final num totalAmount;
  final num paidAmount;
  final num balanceAmount;
  final String status;
  final String? expectedDeliveryDate;
  final String? notes;
  final String? createdAt;
}

/// One line of the `items` array on `GET /purchase-orders/:id`.
class PurchaseOrderItem {
  const PurchaseOrderItem({
    required this.id,
    required this.itemCode,
    required this.itemName,
    required this.unitOfMeasure,
    required this.quantity,
    this.unitPrice = 0,
    this.amount,
    this.receivedQuantity,
    this.pendingQuantity,
    this.returnedQuantity,
  });

  factory PurchaseOrderItem.fromJson(Map<String, dynamic> json) =>
      PurchaseOrderItem(
        id: asInt(json['id']) ?? 0,
        itemCode: asString(json['item_code']) ?? '',
        itemName: asString(json['item_name']) ?? '',
        unitOfMeasure: asString(json['unit_of_measure']) ?? '',
        quantity: asNum(json['quantity']) ?? 0,
        unitPrice: asNum(json['unit_price']) ?? 0,
        amount: asNum(json['amount']),
        receivedQuantity: asNum(json['received_quantity']),
        pendingQuantity: asNum(json['pending_quantity']),
        returnedQuantity: asNum(json['returned_quantity']),
      );

  final int id;
  final String itemCode;
  final String itemName;
  final String unitOfMeasure;
  final num quantity;
  final num unitPrice;
  final num? amount;
  final num? receivedQuantity;
  final num? pendingQuantity;
  final num? returnedQuantity;
}

/// PO detail — the bare `GET /purchase-orders/:id` response: the order
/// plus its line items (the list rows have neither). Tolerant like the
/// rest of the models: a missing/malformed `items` degrades to an empty
/// list instead of throwing.
class PurchaseOrderDetail extends PurchaseOrder {
  const PurchaseOrderDetail({
    required super.id,
    required super.poNo,
    required super.poDate,
    required super.supplierId,
    required super.supplierName,
    super.warehouseName,
    super.totalAmount,
    super.paidAmount,
    super.balanceAmount,
    required super.status,
    super.expectedDeliveryDate,
    super.notes,
    super.createdAt,
    required this.items,
  });

  factory PurchaseOrderDetail.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    return PurchaseOrderDetail(
      id: asInt(json['id']) ?? 0,
      poNo: asString(json['po_no']) ?? '',
      poDate: asString(json['po_date']) ?? '',
      supplierId: asInt(json['supplier_id']) ?? 0,
      supplierName: asString(json['supplier_name']) ?? '',
      warehouseName: asString(json['warehouse_name']),
      totalAmount: asNum(json['total_amount']) ?? 0,
      paidAmount: asNum(json['paid_amount']) ?? 0,
      balanceAmount: asNum(json['balance_amount']) ?? 0,
      status: asString(json['status']) ?? '',
      expectedDeliveryDate: asString(json['expected_delivery_date']),
      notes: asString(json['notes']),
      createdAt: asString(json['created_at']),
      items: raw is List
          ? [
              for (final row in raw)
                if (row is Map<String, dynamic>)
                  PurchaseOrderItem.fromJson(row),
            ]
          : const [],
    );
  }

  final List<PurchaseOrderItem> items;
}
