import 'json_helpers.dart';

/// Port of `Customer` (types/client-types.ts) + the server Customer model.
///
/// Field names match the API JSON keys (snake_case) in `toJson`, and
/// `fromJson` tolerates the server's 0/1 integers for `is_active`.
class Customer {
  const Customer({
    required this.id,
    required this.customerCode,
    required this.customerName,
    this.contactPerson,
    this.email,
    this.phone,
    this.billingAddress,
    this.shippingAddress,
    this.paymentTerms,
    this.paymentTermsDays,
    this.creditLimit,
    this.creditUtilizationPercent,
    required this.currentBalance,
    this.openingBalance,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
        id: asInt(json['id']) ?? 0,
        customerCode: asString(json['customer_code']) ?? '',
        customerName: asString(json['customer_name']) ?? '',
        contactPerson: asString(json['contact_person']),
        email: asString(json['email']),
        phone: asString(json['phone']),
        billingAddress: asString(json['billing_address']),
        shippingAddress: asString(json['shipping_address']),
        paymentTerms: asString(json['payment_terms']),
        paymentTermsDays: asNum(json['payment_terms_days']),
        creditLimit: asNum(json['credit_limit']),
        creditUtilizationPercent: asNum(json['credit_utilization_percent']),
        currentBalance: asNum(json['current_balance']) ?? 0,
        openingBalance: asNum(json['opening_balance']),
        isActive: asBool(json['is_active'], fallback: true),
        createdAt: asString(json['created_at']),
        updatedAt: asString(json['updated_at']),
      );

  final int id;
  final String customerCode;
  final String customerName;
  final String? contactPerson;
  final String? email;
  final String? phone;
  final String? billingAddress;
  final String? shippingAddress;
  final String? paymentTerms;
  final num? paymentTermsDays;
  final num? creditLimit;
  final num? creditUtilizationPercent;
  final num currentBalance;
  final num? openingBalance;
  final bool isActive;
  final String? createdAt;
  final String? updatedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'customer_code': customerCode,
        'customer_name': customerName,
        if (contactPerson != null) 'contact_person': contactPerson,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
        if (billingAddress != null) 'billing_address': billingAddress,
        if (shippingAddress != null) 'shipping_address': shippingAddress,
        if (paymentTerms != null) 'payment_terms': paymentTerms,
        if (paymentTermsDays != null) 'payment_terms_days': paymentTermsDays,
        if (creditLimit != null) 'credit_limit': creditLimit,
        if (creditUtilizationPercent != null)
          'credit_utilization_percent': creditUtilizationPercent,
        'current_balance': currentBalance,
        if (openingBalance != null) 'opening_balance': openingBalance,
        'is_active': isActive ? 1 : 0,
        if (createdAt != null) 'created_at': createdAt,
        if (updatedAt != null) 'updated_at': updatedAt,
      };
}
