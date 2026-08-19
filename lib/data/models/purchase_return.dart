// PurchaseReturn — a header of `GET /purchase-returns` (the redesigned,
// first-class return document served by `PurchaseReturnModel`). A return
// is a header (`purchase_returns`) plus lines (`purchase_return_items`),
// linked to its negative stock movement(s) and — when posted — to a
// supplier credit note (`credit_notes`). The list endpoint returns
// headers with a `line_count` (no embedded items); `GET /purchase-returns/:id`
// additionally embeds `items`. All money/quantity fields arrive as
// `number | string` (SQLite), so they are normalised with [asNum].

import 'json_helpers.dart';

/// One line of a purchase return (from the detail endpoint).
class PurchaseReturnItem {
  const PurchaseReturnItem({
    required this.id,
    this.purchaseReturnId = 0,
    this.sourceItemId,
    required this.itemId,
    required this.itemName,
    this.itemCode = '',
    this.unitOfMeasure = '',
    this.unitCost = 0,
    this.quantity = 0,
    this.amount = 0,
  });

  factory PurchaseReturnItem.fromJson(Map<String, dynamic> json) =>
      PurchaseReturnItem(
        id: asInt(json['id']) ?? 0,
        purchaseReturnId: asInt(json['purchase_return_id']) ?? 0,
        sourceItemId: asInt(json['source_item_id']),
        itemId: asInt(json['item_id']) ?? 0,
        itemName: asString(json['item_name']) ?? '',
        itemCode: asString(json['item_code']) ?? '',
        unitOfMeasure: asString(json['unit_of_measure']) ?? '',
        unitCost: asNum(json['unit_cost']) ?? 0,
        quantity: asNum(json['quantity']) ?? 0,
        amount: asNum(json['amount']) ?? 0,
      );

  final int id;
  final int purchaseReturnId;

  /// `purchases.id` | `purchase_order_items.id` — the source line.
  final int? sourceItemId;
  final int itemId;
  final String itemName;
  final String itemCode;
  final String unitOfMeasure;
  final num unitCost;
  final num quantity;
  final num amount;
}

/// A purchase-return header — one row of `GET /purchase-returns`.
class PurchaseReturn {
  const PurchaseReturn({
    required this.id,
    this.returnNo = '',
    this.returnDate = '',
    this.returnType = '',
    this.sourceType = '',
    this.sourceId,
    this.sourceNo = '',
    this.warehouseId = 0,
    this.warehouseCode = '',
    this.warehouseName = '',
    this.reason,
    this.status = '',
    this.totalQty = 0,
    this.totalAmount = 0,
    this.creditNoteId,
    this.creditNo,
    this.voidedAt,
    this.voidedReason,
    this.createdByUsername,
    this.createdAt,
    this.lineCount = 0,
    this.items = const [],
  });

  factory PurchaseReturn.fromJson(Map<String, dynamic> json) => PurchaseReturn(
    id: asInt(json['id']) ?? 0,
    returnNo: asString(json['return_no']) ?? '',
    returnDate: asString(json['return_date']) ?? '',
    returnType: asString(json['return_type']) ?? '',
    sourceType: asString(json['source_type']) ?? '',
    sourceId: asInt(json['source_id']),
    sourceNo: asString(json['source_no']) ?? '',
    warehouseId: asInt(json['warehouse_id']) ?? 0,
    warehouseCode: asString(json['warehouse_code']) ?? '',
    warehouseName: asString(json['warehouse_name']) ?? '',
    reason: asString(json['reason']),
    status: asString(json['status']) ?? '',
    totalQty: asNum(json['total_qty']) ?? 0,
    totalAmount: asNum(json['total_amount']) ?? 0,
    creditNoteId: asInt(json['credit_note_id']),
    creditNo: asString(json['credit_no']),
    voidedAt: asString(json['voided_at']),
    voidedReason: asString(json['voided_reason']),
    createdByUsername: asString(json['created_by_username']),
    createdAt: asString(json['created_at']),
    lineCount: asInt(json['line_count']) ?? 0,
    items: (json['items'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(PurchaseReturnItem.fromJson)
            .toList() ??
        const [],
  );

  final int id;
  final String returnNo;
  final String returnDate;

  /// `PURCHASE_RETURN` (direct purchase) | `PO_RETURN` (PO receipt).
  final String returnType;

  /// `PURCHASE` | `PURCHASE_ORDER` — the source document kind.
  final String sourceType;

  /// `purchases.id` | `purchase_orders.id` (nullable — legacy backfill
  /// rows can reference deleted source documents).
  final int? sourceId;

  /// The source document number (`PURCH-…` / `PO-…`).
  final String sourceNo;
  final int warehouseId;
  final String warehouseCode;
  final String warehouseName;

  /// Optional return reason (free text).
  final String? reason;

  /// `POSTED` | `VOIDED`.
  final String status;
  final num totalQty;
  final num totalAmount;

  /// The supplier credit-note document, when this return was posted.
  final int? creditNoteId;
  final String? creditNo;
  final String? voidedAt;
  final String? voidedReason;
  final String? createdByUsername;
  final String? createdAt;
  final int lineCount;

  /// Lines — only populated on the detail endpoint.
  final List<PurchaseReturnItem> items;

  /// Whether the return has been voided (full reversal applied).
  bool get isVoided => status == 'VOIDED';

  /// Whether this return is still posted (not voided).
  bool get isPosted => status == 'POSTED';
}
