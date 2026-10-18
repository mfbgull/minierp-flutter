import 'json_helpers.dart';

/// Port of `Payment` (types/client-types.ts) superset of the server
/// Payment model (`server/src/models/Payment.ts`), which also returns
/// `supplier_id` / `invoice_id` / `invoice_no` and grouped allocation
/// strings for supplier payments. Allocation arrays (`allocations`)
/// are deferred to the payments feature port.
class Payment {
  const Payment({
    required this.id,
    required this.paymentNo,
    required this.customerId,
    required this.paymentDate,
    required this.amount,
    required this.paymentMethod,
    this.customerName,
    this.supplierId,
    this.supplierName,
    this.invoiceId,
    this.invoiceNo,
    this.referenceNo,
    this.notes,
    this.createdAt,
    this.paymentKind = 'RECEIPT',
    this.voidedAt,
  });

  factory Payment.fromJson(Map<String, dynamic> json) => Payment(
    id: asInt(json['id']) ?? 0,
    paymentNo: asString(json['payment_no']) ?? '',
    customerId: asInt(json['customer_id']) ?? 0,
    customerName: asString(json['customer_name']),
    supplierId: asInt(json['supplier_id']),
    supplierName: asString(json['supplier_name']),
    invoiceId: asInt(json['invoice_id']),
    invoiceNo: asString(json['invoice_no']),
    paymentDate: asString(json['payment_date']) ?? '',
    amount: asNum(json['amount']) ?? 0,
    paymentMethod: asString(json['payment_method']) ?? '',
    referenceNo: asString(json['reference_no']),
    notes: asString(json['notes']),
    createdAt: asString(json['created_at']),
    paymentKind: asString(json['payment_kind']) ?? 'RECEIPT',
    voidedAt: asString(json['voided_at']),
  );

  final int id;
  final String paymentNo;
  final int customerId;
  final String? customerName;
  final int? supplierId; // supplier payments only
  final String? supplierName;
  final int? invoiceId;
  final String? invoiceNo;
  final String paymentDate;
  final num amount;
  final String paymentMethod;
  final String? referenceNo;
  final String? notes;
  final String? createdAt;
  final String paymentKind;
  final String? voidedAt;

  bool get canModify => paymentKind == 'RECEIPT' && voidedAt == null;
  bool get isCashOutflow =>
      supplierId != null || paymentKind == 'REFUND' || amount < 0;

  Map<String, dynamic> toJson() => {
    'id': id,
    'payment_no': paymentNo,
    'customer_id': customerId,
    if (customerName != null) 'customer_name': customerName,
    if (supplierId != null) 'supplier_id': supplierId,
    if (supplierName != null) 'supplier_name': supplierName,
    if (invoiceId != null) 'invoice_id': invoiceId,
    if (invoiceNo != null) 'invoice_no': invoiceNo,
    'payment_date': paymentDate,
    'amount': amount,
    'payment_method': paymentMethod,
    'payment_kind': paymentKind,
    'voided_at': voidedAt,
    if (referenceNo != null) 'reference_no': referenceNo,
    if (notes != null) 'notes': notes,
    if (createdAt != null) 'created_at': createdAt,
  };
}
