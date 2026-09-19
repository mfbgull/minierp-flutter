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
    this.returnId,
    this.returnNo,
    this.status,
    this.returnedItems = const [],
    this.totalItems = 0,
    this.disposition,
    this.returnAmount = 0,
    this.feeAmount = 0,
    this.netAmount = 0,
    this.settledAmount = 0,
    this.netReturn = 0,
    this.deduction = 0,
    this.refundAmount = 0,
    this.retainedCredit = 0,
    this.settlements = const [],
    this.position,
  });

  factory SalesReturnResult.fromJson(Map<String, dynamic> json) =>
      SalesReturnResult(
        returnId: asInt(json['returnId']),
        returnNo: asString(json['returnNo']),
        status: asString(json['status']),
        returnedItems: json['returnedItems'] is List
            ? [
                for (final row in json['returnedItems'] as List)
                  if (row is Map<String, dynamic>) row,
              ]
            : const [],
        totalItems: asInt(json['totalItems']) ?? 0,
        disposition: asString(json['disposition']),
        returnAmount: asNum(json['returnAmount']) ?? 0,
        feeAmount: asNum(json['feeAmount']) ?? 0,
        netAmount: asNum(json['netAmount']) ?? 0,
        settledAmount: asNum(json['settledAmount']) ?? 0,
        netReturn: asNum(json['netReturn']) ?? 0,
        deduction: asNum(json['deduction']) ?? 0,
        refundAmount: asNum(json['refundAmount']) ?? 0,
        retainedCredit: asNum(json['retainedCredit']) ?? 0,
        settlements: _parseList(json['settlements'], ReturnSettlement.fromJson) ??
            const [],
        position: json['position'] is Map<String, dynamic>
            ? InvoicePosition.fromJson(json['position'] as Map<String, dynamic>)
            : null,
      );

  final int? returnId;
  final String? returnNo;

  /// 'Unsettled' | 'Settled' | 'Not Required'.
  final String? status;
  final List<Map<String, dynamic>> returnedItems;
  final int totalItems;
  final String? disposition;

  /// Gross value of the returned lines (before any restocking fee).
  final num returnAmount;

  /// Restocking fee charged by this return.
  final num feeAmount;

  /// returnAmount − feeAmount.
  final num netAmount;
  final num settledAmount;

  /// Legacy alias of [netAmount] (pre-rework response shape).
  final num netReturn;
  final num deduction;

  /// Cash actually refunded — capped at what the customer collected on
  /// the invoice (server-side rule; may be less than [netAmount]).
  final num refundAmount;

  /// [netAmount] minus [refundAmount] — stays as a customer credit on
  /// account, not cash out.
  final num retainedCredit;
  final List<ReturnSettlement> settlements;
  final InvoicePosition? position;
}

/// One settlement allocation of a return (`return_settlements`).
class ReturnSettlement {
  const ReturnSettlement({
    required this.settlementNo,
    required this.type,
    required this.amount,
    this.method,
    this.reference,
    this.settledDate,
  });

  factory ReturnSettlement.fromJson(Map<String, dynamic> json) =>
      ReturnSettlement(
        settlementNo: asString(json['settlement_no']) ?? '',
        type: asString(json['type']) ?? 'credit',
        amount: asNum(json['amount']) ?? 0,
        method: asString(json['method']),
        reference: asString(json['reference']),
        settledDate: asString(json['settled_date']),
      );

  final String settlementNo;

  /// 'refund' | 'credit' | 'adjust'.
  final String type;
  final num amount;

  /// Refund only: Cash | Bank | Card …
  final String? method;

  /// Payment no (refund) or target invoice no (adjust).
  final String? reference;
  final String? settledDate;
}

/// One line of a return document (`invoice_return_items`).
class ReturnDocumentItem {
  const ReturnDocumentItem({
    required this.itemId,
    required this.quantity,
    required this.unitPrice,
    this.taxAmount = 0,
    this.lineAmount = 0,
  });

  factory ReturnDocumentItem.fromJson(Map<String, dynamic> json) =>
      ReturnDocumentItem(
        itemId: asInt(json['item_id']) ?? 0,
        quantity: asNum(json['quantity']) ?? 0,
        unitPrice: asNum(json['unit_price']) ?? 0,
        taxAmount: asNum(json['tax_amount']) ?? 0,
        lineAmount: asNum(json['line_amount']) ?? 0,
      );

  final int itemId;
  final num quantity;
  final num unitPrice;
  final num taxAmount;

  /// Net of item discount, tax-inclusive — mirrors the server's
  /// proportional tax split (spec §3.5).
  final num lineAmount;
}

/// A persisted return document (`invoice_returns`) with its items and
/// settlements — the `returns` array of `GET /invoices/:id`.
class ReturnDocument {
  const ReturnDocument({
    required this.id,
    required this.returnNo,
    required this.returnDate,
    this.reason,
    required this.status,
    this.feeType,
    this.feeValue = 0,
    this.returnedAmount = 0,
    this.feeAmount = 0,
    this.netAmount = 0,
    this.settledAmount = 0,
    this.warehouseId,
    this.items = const [],
    this.settlements = const [],
  });

  factory ReturnDocument.fromJson(Map<String, dynamic> json) =>
      ReturnDocument(
        id: asInt(json['id']) ?? 0,
        returnNo: asString(json['return_no']) ?? '',
        returnDate: asString(json['return_date']) ?? '',
        reason: asString(json['reason']),
        status: asString(json['status']) ?? 'Unsettled',
        feeType: asString(json['fee_type']),
        feeValue: asNum(json['fee_value']) ?? 0,
        returnedAmount: asNum(json['returned_amount']) ?? 0,
        feeAmount: asNum(json['fee_amount']) ?? 0,
        netAmount: asNum(json['net_amount']) ?? 0,
        settledAmount: asNum(json['settled_amount']) ?? 0,
        warehouseId: asInt(json['warehouse_id']),
        items: _parseList(json['items'], ReturnDocumentItem.fromJson) ??
            const [],
        settlements: _parseList(json['settlements'], ReturnSettlement.fromJson) ??
            const [],
      );

  final int id;
  final String returnNo;
  final String returnDate;
  final String? reason;

  /// 'Unsettled' | 'Settled' | 'Not Required' | 'Voided'.
  final String status;

  /// 'none' | 'fixed' | 'percentage'.
  final String? feeType;
  final num feeValue;
  final num returnedAmount;
  final num feeAmount;
  final num netAmount;
  final num settledAmount;
  final int? warehouseId;
  final List<ReturnDocumentItem> items;
  final List<ReturnSettlement> settlements;

  bool get isSettled => status == 'Settled';
}

/// The authoritative money position of an invoice (spec §3.2 / §4.2) —
/// `data.position` on the invoice detail and the `:id/position` endpoint.
class InvoicePosition {
  const InvoicePosition({
    this.originalTotal = 0,
    this.totalReturned = 0,
    this.currentInvoiceValue = 0,
    this.totalPaid = 0,
    this.totalFees = 0,
    this.netPosition = 0,
    this.refundCreditDue = 0,
    this.totalSettled = 0,
    this.remainingRefundDue = 0,
    this.balanceDue = 0,
    this.remainingSettlementCapacity = 0,
    this.settledAmount = 0,
  });

  factory InvoicePosition.fromJson(Map<String, dynamic> json) =>
      InvoicePosition(
        originalTotal: asNum(json['originalTotal']) ?? 0,
        totalReturned: asNum(json['totalReturned']) ?? 0,
        currentInvoiceValue: asNum(json['currentInvoiceValue']) ?? 0,
        totalPaid: asNum(json['totalPaid']) ?? 0,
        totalFees: asNum(json['totalFees']) ?? 0,
        netPosition: asNum(json['netPosition']) ?? 0,
        refundCreditDue: asNum(json['refundCreditDue']) ?? 0,
        totalSettled: asNum(json['totalSettled']) ?? 0,
        remainingRefundDue: asNum(json['remainingRefundDue']) ?? 0,
        balanceDue: asNum(json['balanceDue']) ?? 0,
        remainingSettlementCapacity:
            asNum(json['remainingSettlementCapacity']) ?? 0,
        settledAmount: asNum(json['settledAmount']) ?? 0,
      );

  /// The invoice total as originally written.
  final num originalTotal;

  /// Σ returned line value (gross, tax-inclusive).
  final num totalReturned;

  /// What the kept goods are worth: original − returned.
  final num currentInvoiceValue;

  /// Gross collected base: positive allocations + credit offset. Refunds
  /// never shrink it (spec §3.2 / scenario 10).
  final num totalPaid;
  final num totalFees;

  /// The customer's net position: value kept + fees − paid.
  final num netPosition;

  /// What the invoice owes the customer back: max(0, paid − netPosition).
  final num refundCreditDue;
  final num totalSettled;
  final num remainingRefundDue;

  /// Always shown (D12): never negative.
  final num balanceDue;
  final num remainingSettlementCapacity;

  /// Spec §4.2 alias of [totalSettled].
  final num settledAmount;
}

/// One row of the chronological transaction history (spec §6.3 7).
class TimelineEvent {
  const TimelineEvent({
    required this.type,
    required this.reference,
    required this.amount,
    required this.date,
  });

  factory TimelineEvent.fromJson(Map<String, dynamic> json) => TimelineEvent(
        type: asString(json['type']) ?? '',
        reference: asString(json['reference']) ?? '',
        amount: asNum(json['amount']) ?? 0,
        date: asString(json['date']) ?? '',
      );

  /// 'INVOICE' | 'PAYMENT' | 'RETURN' | 'RESTOCKING_FEE' | 'SETTLEMENT'.
  final String type;
  final String reference;
  final num amount;
  final String date;
}

List<T>? _parseList<T>(
  Object? value,
  T Function(Map<String, dynamic>) fromJson,
) {
  if (value is! List) return null;
  return [
    for (final item in value)
      if (item is Map<String, dynamic>) fromJson(item),
  ];
}


