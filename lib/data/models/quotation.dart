// Quotation models — port of `Quotation` / `QuotationItem` /
// `QuotationDetail` (types/client-types.ts) plus the fields the server's
// `QuotationModel.getAll`/`getById` join in (warehouse_code,
// warehouse_name, created_by_username).
//
// Envelope variants observed on the server (PORTING.md §2):
// - `GET /quotations` → **bare array** `[Quotation]` (filters: status,
//   customer_id, customer_name, start_date, end_date, warehouse_id,
//   limit — no search/page)
// - `GET /quotations/:id` → **bare object** `{...quotation, items}`

import 'json_helpers.dart';

/// A quotation row (list or detail — the detail adds `items` via
/// [QuotationDetail]). `total_amount` arrives as `number | string`
/// (SQLite), so it is normalised with [asNum].
class Quotation {
  const Quotation({
    required this.id,
    required this.quotationNo,
    required this.quotationDate,
    required this.customerId,
    required this.customerName,
    this.expiryDate,
    required this.status,
    this.totalAmount = 0,
    this.notes,
    this.terms,
    this.warehouseId,
    this.warehouseCode,
    this.warehouseName,
    this.createdBy,
    this.createdByUsername,
    this.createdAt,
    this.updatedAt,
  });

  factory Quotation.fromJson(Map<String, dynamic> json) => Quotation(
    id: asInt(json['id']) ?? 0,
    quotationNo: asString(json['quotation_no']) ?? '',
    quotationDate: asString(json['quotation_date']) ?? '',
    customerId: asInt(json['customer_id']) ?? 0,
    customerName: asString(json['customer_name']) ?? '',
    expiryDate: asString(json['expiry_date']),
    status: asString(json['status']) ?? '',
    totalAmount: asNum(json['total_amount']) ?? 0,
    notes: asString(json['notes']),
    terms: asString(json['terms']),
    warehouseId: asInt(json['warehouse_id']),
    warehouseCode: asString(json['warehouse_code']),
    warehouseName: asString(json['warehouse_name']),
    createdBy: asInt(json['created_by']),
    createdByUsername: asString(json['created_by_username']),
    createdAt: asString(json['created_at']),
    updatedAt: asString(json['updated_at']),
  );

  final int id;
  final String quotationNo;
  final String quotationDate;
  final int customerId;
  final String customerName;
  final String? expiryDate;
  final String status;
  final num totalAmount;
  final String? notes;
  final String? terms;
  final int? warehouseId;
  final String? warehouseCode;
  final String? warehouseName;
  final int? createdBy;
  final String? createdByUsername;
  final String? createdAt;
  final String? updatedAt;
}

/// One line of the `items` array on `GET /quotations/:id`.
class QuotationItem {
  const QuotationItem({
    this.id,
    required this.itemId,
    this.itemCode = '',
    this.itemName = '',
    this.quantity = 0,
    this.unitPrice = 0,
    this.discountType,
    this.discountValue,
    this.taxRate,
    this.amount,
  });

  factory QuotationItem.fromJson(Map<String, dynamic> json) => QuotationItem(
    id: asInt(json['id']),
    itemId: asInt(json['item_id']) ?? 0,
    itemCode: asString(json['item_code']) ?? '',
    itemName: asString(json['item_name']) ?? '',
    quantity: asNum(json['quantity']) ?? 0,
    unitPrice: asNum(json['unit_price']) ?? 0,
    discountType: asString(json['discount_type']),
    discountValue: asNum(json['discount_value']),
    taxRate: asNum(json['tax_rate']),
    amount: asNum(json['amount']),
  );

  final int? id;
  final int itemId;
  final String itemCode;
  final String itemName;
  final num quantity;
  final num unitPrice;
  final String? discountType;
  final num? discountValue;
  final num? taxRate;
  final num? amount;
}

/// Quotation detail — the bare `GET /quotations/:id` response: the
/// quotation plus its line items (the list rows have neither). Tolerant
/// like the rest of the models: a missing/malformed `items` degrades to
/// an empty list instead of throwing.
class QuotationDetail extends Quotation {
  const QuotationDetail({
    required super.id,
    required super.quotationNo,
    required super.quotationDate,
    required super.customerId,
    required super.customerName,
    super.expiryDate,
    required super.status,
    super.totalAmount,
    super.notes,
    super.terms,
    super.warehouseId,
    super.warehouseCode,
    super.warehouseName,
    super.createdBy,
    super.createdByUsername,
    super.createdAt,
    super.updatedAt,
    required this.items,
  });

  factory QuotationDetail.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    return QuotationDetail(
      id: asInt(json['id']) ?? 0,
      quotationNo: asString(json['quotation_no']) ?? '',
      quotationDate: asString(json['quotation_date']) ?? '',
      customerId: asInt(json['customer_id']) ?? 0,
      customerName: asString(json['customer_name']) ?? '',
      expiryDate: asString(json['expiry_date']),
      status: asString(json['status']) ?? '',
      totalAmount: asNum(json['total_amount']) ?? 0,
      notes: asString(json['notes']),
      terms: asString(json['terms']),
      warehouseId: asInt(json['warehouse_id']),
      warehouseCode: asString(json['warehouse_code']),
      warehouseName: asString(json['warehouse_name']),
      createdBy: asInt(json['created_by']),
      createdByUsername: asString(json['created_by_username']),
      createdAt: asString(json['created_at']),
      updatedAt: asString(json['updated_at']),
      items: raw is List
          ? [
              for (final row in raw)
                if (row is Map<String, dynamic>) QuotationItem.fromJson(row),
            ]
          : const [],
    );
  }

  final List<QuotationItem> items;
}

/// Result of `POST /quotations/:id/convert` — the server responds
/// `{success: true, message, salesOrderId, salesOrderNo}` (a **flat**
/// body with no `data` field, unlike the enveloped action endpoints), so
/// the repository parses the raw body into this.
class QuotationConvertResult {
  const QuotationConvertResult({required this.salesOrderId, this.salesOrderNo});

  factory QuotationConvertResult.fromJson(Map<String, dynamic> json) =>
      QuotationConvertResult(
        salesOrderId: asInt(json['salesOrderId']) ?? 0,
        salesOrderNo: asString(json['salesOrderNo']),
      );

  final int salesOrderId;
  final String? salesOrderNo;
}
