import 'json_helpers.dart';

/// Port of `Supplier` (types/client-types.ts) + the server Supplier model.
class Supplier {
  const Supplier({
    required this.id,
    required this.supplierCode,
    required this.supplierName,
    this.contactPerson,
    this.email,
    this.phone,
    this.address,
    this.paymentTerms,
    this.currentBalance,
    this.creditUtilizationPercent,
    this.isActive = true,
    this.notes,
    this.createdAt,
    this.updatedAt,
  });

  factory Supplier.fromJson(Map<String, dynamic> json) => Supplier(
    id: asInt(json['id']) ?? 0,
    supplierCode: asString(json['supplier_code']) ?? '',
    supplierName: asString(json['supplier_name']) ?? '',
    contactPerson: asString(json['contact_person']),
    email: asString(json['email']),
    phone: asString(json['phone']),
    address: asString(json['address']),
    paymentTerms: asString(json['payment_terms']),
    currentBalance: asNum(json['current_balance']),
    creditUtilizationPercent: asNum(json['credit_utilization_percent']),
    isActive: asBool(json['is_active'], fallback: true),
    notes: asString(json['notes']),
    createdAt: asString(json['created_at']),
    updatedAt: asString(json['updated_at']),
  );

  final int id;
  final String supplierCode;
  final String supplierName;
  final String? contactPerson;
  final String? email;
  final String? phone;
  final String? address;
  final String? paymentTerms;
  final num? currentBalance;
  final num? creditUtilizationPercent;
  final bool isActive;
  final String? notes;
  final String? createdAt;
  final String? updatedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'supplier_code': supplierCode,
    'supplier_name': supplierName,
    if (contactPerson != null) 'contact_person': contactPerson,
    if (email != null) 'email': email,
    if (phone != null) 'phone': phone,
    if (address != null) 'address': address,
    if (paymentTerms != null) 'payment_terms': paymentTerms,
    if (currentBalance != null) 'current_balance': currentBalance,
    if (creditUtilizationPercent != null)
      'credit_utilization_percent': creditUtilizationPercent,
    'is_active': isActive ? 1 : 0,
    if (notes != null) 'notes': notes,
    if (createdAt != null) 'created_at': createdAt,
    if (updatedAt != null) 'updated_at': updatedAt,
  };
}
