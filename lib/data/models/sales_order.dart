// SalesOrder models — port of `SalesOrder` / `SalesOrderItem` /
// `SalesOrderDetail` (types/client-types.ts) plus the fields the server's
// `SalesOrderModel.getAll`/`getById` join in (warehouse_code,
// warehouse_name, created_by_username, quotation_no).
//
// Envelope variants observed on the server (PORTING.md §2):
// - `GET /sales-orders` → **bare array** `[SalesOrder]` (filters:
//   status, customer_id, customer_name, start_date, end_date,
//   warehouse_id, source_type, limit — no search/page)
// - `GET /sales-orders/:id` → **bare object** `{...so, items}`

import 'json_helpers.dart';

/// A sales order row (list or detail — the detail adds `items` via
/// [SalesOrderDetail]). `total_amount` arrives as `number | string`
/// (SQLite), so it is normalised with [asNum].
class SalesOrder {
  const SalesOrder({
    required this.id,
    required this.soNo,
    required this.soDate,
    required this.customerId,
    required this.customerName,
    this.deliveryDate,
    required this.status,
    this.totalAmount = 0,
    this.notes,
    this.warehouseId,
    this.warehouseCode,
    this.warehouseName,
    this.sourceType,
    this.sourceId,
    this.quotationNo,
    this.createdBy,
    this.createdByUsername,
    this.createdAt,
    this.updatedAt,
  });

  factory SalesOrder.fromJson(Map<String, dynamic> json) => SalesOrder(
    id: asInt(json['id']) ?? 0,
    soNo: asString(json['so_no']) ?? '',
    soDate: asString(json['so_date']) ?? '',
    customerId: asInt(json['customer_id']) ?? 0,
    customerName: asString(json['customer_name']) ?? '',
    deliveryDate: asString(json['delivery_date']),
    status: asString(json['status']) ?? '',
    totalAmount: asNum(json['total_amount']) ?? 0,
    notes: asString(json['notes']),
    warehouseId: asInt(json['warehouse_id']),
    warehouseCode: asString(json['warehouse_code']),
    warehouseName: asString(json['warehouse_name']),
    sourceType: asString(json['source_type']),
    sourceId: asInt(json['source_id']),
    quotationNo: asString(json['quotation_no']),
    createdBy: asInt(json['created_by']),
    createdByUsername: asString(json['created_by_username']),
    createdAt: asString(json['created_at']),
    updatedAt: asString(json['updated_at']),
  );

  final int id;
  final String soNo;
  final String soDate;
  final int customerId;
  final String customerName;
  final String? deliveryDate;
  final String status;
  final num totalAmount;
  final String? notes;
  final int? warehouseId;
  final String? warehouseCode;
  final String? warehouseName;
  final String? sourceType;
  final int? sourceId;
  final String? quotationNo;
  final int? createdBy;
  final String? createdByUsername;
  final String? createdAt;
  final String? updatedAt;
}

/// One line of the `items` array on `GET /sales-orders/:id`.
class SalesOrderItem {
  const SalesOrderItem({
    this.id,
    required this.itemId,
    this.itemCode = '',
    this.itemName = '',
    this.quantity = 0,
    this.deliveredQuantity,
    this.unitPrice = 0,
    this.amount,
  });

  factory SalesOrderItem.fromJson(Map<String, dynamic> json) => SalesOrderItem(
    id: asInt(json['id']),
    itemId: asInt(json['item_id']) ?? 0,
    itemCode: asString(json['item_code']) ?? '',
    itemName: asString(json['item_name']) ?? '',
    quantity: asNum(json['quantity']) ?? 0,
    deliveredQuantity: asNum(json['delivered_quantity']),
    unitPrice: asNum(json['unit_price']) ?? 0,
    amount: asNum(json['amount']),
  );

  final int? id;
  final int itemId;
  final String itemCode;
  final String itemName;
  final num quantity;
  final num? deliveredQuantity;
  final num unitPrice;
  final num? amount;
}

/// SO detail — the bare `GET /sales-orders/:id` response: the order plus
/// its line items (the list rows have neither). Tolerant like the rest of
/// the models: a missing/malformed `items` degrades to an empty list
/// instead of throwing.
class SalesOrderDetail extends SalesOrder {
  const SalesOrderDetail({
    required super.id,
    required super.soNo,
    required super.soDate,
    required super.customerId,
    required super.customerName,
    super.deliveryDate,
    required super.status,
    super.totalAmount,
    super.notes,
    super.warehouseId,
    super.warehouseCode,
    super.warehouseName,
    super.sourceType,
    super.sourceId,
    super.quotationNo,
    super.createdBy,
    super.createdByUsername,
    super.createdAt,
    super.updatedAt,
    required this.items,
  });

  factory SalesOrderDetail.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    return SalesOrderDetail(
      id: asInt(json['id']) ?? 0,
      soNo: asString(json['so_no']) ?? '',
      soDate: asString(json['so_date']) ?? '',
      customerId: asInt(json['customer_id']) ?? 0,
      customerName: asString(json['customer_name']) ?? '',
      deliveryDate: asString(json['delivery_date']),
      status: asString(json['status']) ?? '',
      totalAmount: asNum(json['total_amount']) ?? 0,
      notes: asString(json['notes']),
      warehouseId: asInt(json['warehouse_id']),
      warehouseCode: asString(json['warehouse_code']),
      warehouseName: asString(json['warehouse_name']),
      sourceType: asString(json['source_type']),
      sourceId: asInt(json['source_id']),
      quotationNo: asString(json['quotation_no']),
      createdBy: asInt(json['created_by']),
      createdByUsername: asString(json['created_by_username']),
      createdAt: asString(json['created_at']),
      updatedAt: asString(json['updated_at']),
      items: raw is List
          ? [
              for (final row in raw)
                if (row is Map<String, dynamic>) SalesOrderItem.fromJson(row),
            ]
          : const [],
    );
  }

  final List<SalesOrderItem> items;
}
