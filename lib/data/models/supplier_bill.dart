import 'json_helpers.dart';

class SupplierBill {
  const SupplierBill({
    required this.id,
    required this.supplierId,
    required this.billNo,
    required this.billDate,
    required this.netAmount,
    required this.inputTaxAmount,
    required this.totalAmount,
    required this.balanceAmount,
    required this.description,
    this.dueDate,
    this.voidedAt,
  });

  factory SupplierBill.fromJson(Map<String, dynamic> json) => SupplierBill(
    id: asInt(json['id']) ?? 0,
    supplierId: asInt(json['supplier_id']) ?? 0,
    billNo: asString(json['bill_no']) ?? '',
    billDate: asString(json['bill_date']) ?? '',
    dueDate: asString(json['due_date']),
    description: asString(json['description']) ?? '',
    netAmount: asNum(json['net_amount']) ?? 0,
    inputTaxAmount: asNum(json['input_tax_amount']) ?? 0,
    totalAmount: asNum(json['total_amount']) ?? 0,
    balanceAmount: asNum(json['balance_amount']) ?? 0,
    voidedAt: asString(json['voided_at']),
  );

  final int id;
  final int supplierId;
  final String billNo;
  final String billDate;
  final String? dueDate;
  final String description;
  final num netAmount;
  final num inputTaxAmount;
  final num totalAmount;
  final num balanceAmount;
  final String? voidedAt;
}
