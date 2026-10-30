import 'json_helpers.dart';

/// One supplier row for a company: the union of manual links and valid
/// purchase history, with independent `linked` / `purchased` flags.
class CompanySupplier {
  const CompanySupplier({
    required this.supplierId,
    required this.supplierName,
    this.contactPerson,
    this.phone,
    this.email,
    this.isActive = true,
    this.linked = false,
    this.purchased = false,
    this.productCount = 0,
    this.lastPurchaseDate,
  });

  factory CompanySupplier.fromJson(Map<String, dynamic> json) => CompanySupplier(
    supplierId: asInt(json['supplier_id']) ?? 0,
    supplierName: asString(json['supplier_name']) ?? '',
    contactPerson: asString(json['contact_person']),
    phone: asString(json['phone']),
    email: asString(json['email']),
    isActive: asBool(json['is_active'], fallback: true),
    linked: asBool(json['linked']),
    purchased: asBool(json['purchased']),
    productCount: asInt(json['product_count']) ?? 0,
    lastPurchaseDate: asString(json['last_purchase_date']),
  );

  final int supplierId;
  final String supplierName;
  final String? contactPerson;
  final String? phone;
  final String? email;
  final bool isActive;
  final bool linked;
  final bool purchased;
  final int productCount;
  final String? lastPurchaseDate;
}
