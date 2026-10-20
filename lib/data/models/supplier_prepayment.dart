import 'json_helpers.dart';

class SupplierPrepayment {
  const SupplierPrepayment({
    required this.id,
    required this.supplierId,
    required this.amount,
    required this.appliedAmount,
    required this.availableAmount,
    required this.prepayDate,
    required this.paymentMethod,
    this.voidedAt,
  });
  factory SupplierPrepayment.fromJson(Map<String, dynamic> json) =>
      SupplierPrepayment(
        id: asInt(json['id']) ?? 0,
        supplierId: asInt(json['supplier_id']) ?? 0,
        amount: asNum(json['amount']) ?? 0,
        appliedAmount: asNum(json['applied_amount']) ?? 0,
        availableAmount: asNum(json['available_amount']) ?? 0,
        prepayDate: asString(json['prepay_date']) ?? '',
        paymentMethod: asString(json['payment_method']) ?? '',
        voidedAt: asString(json['voided_at']),
      );
  final int id;
  final int supplierId;
  final num amount;
  final num appliedAmount;
  final num availableAmount;
  final String prepayDate;
  final String paymentMethod;
  final String? voidedAt;
}

enum SupplierPaymentTargetKind {
  purchase('purchase'),
  purchaseOrder('purchase_order'),
  supplierBill('supplier_bill');

  const SupplierPaymentTargetKind(this.value);
  final String value;
}

class SupplierPaymentTarget {
  const SupplierPaymentTarget({
    required this.kind,
    required this.id,
    required this.reference,
    required this.balanceAmount,
  });
  factory SupplierPaymentTarget.fromJson(Map<String, dynamic> json) =>
      SupplierPaymentTarget(
        kind: SupplierPaymentTargetKind.values.firstWhere(
          (kind) => kind.value == json['kind'],
        ),
        id: asInt(json['id']) ?? 0,
        reference: asString(json['reference']) ?? '',
        balanceAmount: asNum(json['balance_amount']) ?? 0,
      );
  final SupplierPaymentTargetKind kind;
  final int id;
  final String reference;
  final num balanceAmount;
}
