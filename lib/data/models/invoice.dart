import 'json_helpers.dart';

/// Invoice status values — the full union from the server Invoice model
/// (`INVOICE_STATUSES` in types/client-types.ts, plus `Returned`).
/// `Invoice.status` stays a plain `String` (verbatim port of
/// `status: string`); this enum is the UI/status-color reference.
enum InvoiceStatus {
  draft('Draft'),
  sent('Sent'),
  unpaid('Unpaid'),
  partiallyPaid('Partially Paid'),
  paid('Paid'),
  overdue('Overdue'),
  cancelled('Cancelled'),
  returned('Returned'),
  partiallyReturned('Partially Returned');

  const InvoiceStatus(this.value);

  final String value;

  /// null-safe lookup used by UI maps — returns null for unknown strings.
  static InvoiceStatus? tryParse(String? value) {
    for (final s in values) {
      if (s.value == value) return s;
    }
    return null;
  }
}

/// `'flat'` or `'percentage'` (DISCOUNT_TYPES in types/client-types.ts).
enum DiscountType {
  flat('flat'),
  percentage('percentage');

  const DiscountType(this.value);

  final String value;

  static DiscountType fromString(Object? value) => values.firstWhere(
    (e) => e.value == value,
    orElse: () => DiscountType.percentage,
  );
}

/// Nested discount object used by the client invoice types
/// (`Discount` in types/client-types.ts).
class Discount {
  const Discount({required this.type, required this.value});

  factory Discount.fromJson(Map<String, dynamic> json) => Discount(
    type: DiscountType.fromString(json['type']),
    value: asNum(json['value']) ?? 0,
  );

  final DiscountType type;
  final num value;

  Map<String, dynamic> toJson() => {'type': type.value, 'value': value};
}

/// Invoice line as returned by the server (`InvoiceItem` in
/// server/src/models/Invoice.ts) — NOT the client form-shape type.
///
/// The form-shape `InvoiceItem` (id, description, rate, tax,
/// discount: Discount) belongs to the invoice form state and is ported
/// with the sales feature.
class InvoiceItem {
  const InvoiceItem({
    required this.id,
    required this.invoiceId,
    required this.itemId,
    this.itemCode,
    this.itemName,
    required this.quantity,
    required this.unitPrice,
    required this.amount,
    required this.taxRate,
    required this.discountType,
    required this.discountValue,
    required this.returnedQty,
    this.expiryDate,
    this.isExpiredAtSale = false,
  });

  factory InvoiceItem.fromJson(Map<String, dynamic> json) => InvoiceItem(
    id: asInt(json['id']) ?? 0,
    invoiceId: asInt(json['invoice_id']) ?? 0,
    itemId: asInt(json['item_id']) ?? 0,
    itemCode: asString(json['item_code']),
    itemName: asString(json['item_name']),
    quantity: asNum(json['quantity']) ?? 0,
    unitPrice: asNum(json['unit_price']) ?? 0,
    amount: asNum(json['amount']) ?? 0,
    taxRate: asNum(json['tax_rate']) ?? 0,
    discountType: asString(json['discount_type']) ?? 'none',
    discountValue: asNum(json['discount_value']) ?? 0,
    returnedQty: asNum(json['returned_qty']) ?? 0,
    expiryDate: asString(json['expiry_date']),
    isExpiredAtSale: asBool(json['is_expired_at_sale']),
  );

  final int id;
  final int invoiceId;
  final int itemId;
  final String? itemCode;
  final String? itemName;
  final num quantity;
  final num unitPrice;
  final num amount;
  final num taxRate;
  final String discountType; // 'none' | 'percentage' | 'flat'
  final num discountValue;
  final num returnedQty;
  final String? expiryDate;
  final bool isExpiredAtSale;

  Map<String, dynamic> toJson() => {
    'id': id,
    'invoice_id': invoiceId,
    'item_id': itemId,
    if (itemCode != null) 'item_code': itemCode,
    if (itemName != null) 'item_name': itemName,
    'quantity': quantity,
    'unit_price': unitPrice,
    'amount': amount,
    'tax_rate': taxRate,
    'discount_type': discountType,
    'discount_value': discountValue,
    'returned_qty': returnedQty,
    if (expiryDate != null) 'expiry_date': expiryDate,
    'is_expired_at_sale': isExpiredAtSale ? 1 : 0,
  };
}

/// Nested payment to record with invoice creation
/// (`InvoicePayment` in types/client-types.ts).
class InvoicePayment {
  const InvoicePayment({
    required this.recordPayment,
    required this.paymentDate,
    required this.paymentAmount,
    required this.paymentMethod,
    this.referenceNo,
    this.paymentNotes,
  });

  factory InvoicePayment.fromJson(Map<String, dynamic> json) => InvoicePayment(
    recordPayment: asBool(json['record_payment']),
    paymentDate: asString(json['payment_date']) ?? '',
    paymentAmount: asNum(json['payment_amount']) ?? 0,
    paymentMethod: asString(json['payment_method']) ?? '',
    referenceNo: asString(json['reference_no']),
    paymentNotes: asString(json['payment_notes']),
  );

  final bool recordPayment;
  final String paymentDate;
  final num paymentAmount;
  final String paymentMethod;
  final String? referenceNo;
  final String? paymentNotes;

  Map<String, dynamic> toJson() => {
    'record_payment': recordPayment,
    'payment_date': paymentDate,
    'payment_amount': paymentAmount,
    'payment_method': paymentMethod,
    if (referenceNo != null) 'reference_no': referenceNo,
    if (paymentNotes != null) 'payment_notes': paymentNotes,
  };
}

/// Split payment method entry (`PaymentMethod` in types/client-types.ts).
class PaymentMethod {
  const PaymentMethod({
    required this.id,
    required this.method,
    required this.amount,
    this.referenceNo,
  });

  factory PaymentMethod.fromJson(Map<String, dynamic> json) => PaymentMethod(
    id: asInt(json['id']) ?? 0,
    method: asString(json['method']) ?? '',
    amount: asNum(json['amount']) ?? 0,
    referenceNo: asString(json['reference_no']),
  );

  final int id;
  final String method;
  final num amount;
  final String? referenceNo;

  Map<String, dynamic> toJson() => {
    'id': id,
    'method': method,
    'amount': amount,
    if (referenceNo != null) 'reference_no': referenceNo,
  };
}

/// An existing payment row returned by `GET /invoices/:id/payments` (the
/// server's payment record for invoice allocation view). Distinct from
/// `InvoicePayment` (a form-nested record) and `PaymentMethod` (a form
/// split line).
class InvoicePaymentRecord {
  const InvoicePaymentRecord({
    required this.id,
    this.invoiceId,
    this.paymentNo,
    this.paymentDate,
    required this.amount,
    required this.method,
    this.referenceNo,
    this.notes,
  });

  factory InvoicePaymentRecord.fromJson(Map<String, dynamic> json) =>
      InvoicePaymentRecord(
        id: asInt(json['id']) ?? 0,
        invoiceId: asInt(json['invoice_id']),
        paymentNo: asString(json['payment_no']),
        paymentDate: asString(json['payment_date']),
        amount: asNum(json['amount']) ?? 0,
        method: asString(json['payment_method']) ?? '',
        referenceNo: asString(json['reference_no']),
        notes: asString(json['notes']),
      );

  final int id;
  final int? invoiceId;
  final String? paymentNo;
  final String? paymentDate;
  final num amount;
  final String method;
  final String? referenceNo;
  final String? notes;

  Map<String, dynamic> toJson() => {
    'id': id,
    if (invoiceId != null) 'invoice_id': invoiceId,
    if (paymentNo != null) 'payment_no': paymentNo,
    if (paymentDate != null) 'payment_date': paymentDate,
    'amount': amount,
    'payment_method': method,
    if (referenceNo != null) 'reference_no': referenceNo,
    if (notes != null) 'notes': notes,
  };
}

/// Company block printed on documents (`CompanyInfo` in types/client-types.ts).
class CompanyInfo {
  const CompanyInfo({
    required this.name,
    required this.email,
    required this.phone,
    required this.address,
    this.taxId,
  });

  factory CompanyInfo.fromJson(Map<String, dynamic> json) => CompanyInfo(
    name: asString(json['name']) ?? '',
    email: asString(json['email']) ?? '',
    phone: asString(json['phone']) ?? '',
    address: asString(json['address']) ?? '',
    taxId: asString(json['taxId']),
  );

  final String name;
  final String email;
  final String phone;
  final String address;
  final String? taxId;

  Map<String, dynamic> toJson() => {
    'name': name,
    'email': email,
    'phone': phone,
    'address': address,
    if (taxId != null) 'taxId': taxId,
  };
}

/// Port of `Invoice` (types/client-types.ts) superset of the server
/// Invoice model — the union of both, so one model parses list rows and
/// detail responses (which add customer_*, items, source links, etc.).
///
/// `status` is kept as a plain `String` (verbatim `status: string`);
/// use `InvoiceStatus.tryParse` for enum semantics.
class Invoice {
  const Invoice({
    required this.id,
    required this.invoiceNo,
    required this.customerId,
    required this.invoiceDate,
    required this.totalAmount,
    required this.paidAmount,
    required this.balanceAmount,
    required this.status,
    this.customerName,
    this.customerEmail,
    this.customerPhone,
    this.customerAddress,
    this.customerCurrentBalance,
    this.customerCreditLimit,
    this.customerCreditUtilization,
    this.dueDate,
    this.returnedAmount = 0,
    this.returnFee,
    this.discountScope,
    this.discountType,
    this.discountValue,
    this.discount,
    this.items,
    this.notes,
    this.terms,
    this.createdBy,
    this.createdByUsername,
    this.createdAt,
    this.updatedAt,
    this.soId,
    this.soNo,
    this.sourceType,
    this.quotationId,
    this.quotationNo,
    this.warehouseId,
    this.warehouseCode,
    this.warehouseName,
    this.company,
    this.payment,
    this.paymentMethods,
    this.expiryNotes,
  });

  factory Invoice.fromJson(Map<String, dynamic> json) => Invoice(
    id: asInt(json['id']) ?? 0,
    invoiceNo: asString(json['invoice_no']) ?? '',
    customerId: asInt(json['customer_id']) ?? 0,
    customerName: asString(json['customer_name']),
    customerEmail: asString(json['customer_email']),
    customerPhone: asString(json['customer_phone']),
    customerAddress: asString(json['customer_address']),
    customerCurrentBalance: asNum(json['customer_current_balance']),
    customerCreditLimit: asNum(json['customer_credit_limit']),
    customerCreditUtilization: asNum(json['customer_credit_utilization']),
    invoiceDate: asString(json['invoice_date']) ?? '',
    dueDate: asString(json['due_date']),
    totalAmount: asNum(json['total_amount']) ?? 0,
    paidAmount: asNum(json['paid_amount']) ?? 0,
    balanceAmount: asNum(json['balance_amount']) ?? 0,
    status: asString(json['status']) ?? '',
    returnedAmount: asNum(json['returned_amount']) ?? 0,
    returnFee: asNum(json['return_fee']),
    discountScope: asString(json['discount_scope'] ?? json['discountScope']),
    discountType: asString(json['discount_type']),
    discountValue: asNum(json['discount_value']),
    discount: json['discount'] is Map<String, dynamic>
        ? Discount.fromJson(json['discount'] as Map<String, dynamic>)
        : null,
    items: _parseList(json['items'], InvoiceItem.fromJson),
    notes: asString(json['notes']),
    terms: asString(json['terms']),
    createdBy: asInt(json['created_by']),
    createdByUsername: asString(json['created_by_username']),
    createdAt: asString(json['created_at']),
    updatedAt: asString(json['updated_at']),
    soId: asInt(json['so_id']),
    soNo: asString(json['so_no']),
    sourceType: asString(json['source_type']),
    quotationId: asInt(json['quotation_id']),
    quotationNo: asString(json['quotation_no']),
    warehouseId: asInt(json['warehouse_id']),
    warehouseCode: asString(json['warehouse_code']),
    warehouseName: asString(json['warehouse_name']),
    expiryNotes: asString(json['expiry_notes']),
    company: json['company'] is Map<String, dynamic>
        ? CompanyInfo.fromJson(json['company'] as Map<String, dynamic>)
        : null,
    payment: json['payment'] is Map<String, dynamic>
        ? InvoicePayment.fromJson(json['payment'] as Map<String, dynamic>)
        : null,
    paymentMethods: _parseList(json['paymentMethods'], PaymentMethod.fromJson),
  );

  final int id;
  final String invoiceNo;
  final int customerId;
  final String? customerName;
  final String? customerEmail;
  final String? customerPhone;
  final String? customerAddress;
  final num? customerCurrentBalance;
  final num? customerCreditLimit;
  final num? customerCreditUtilization;
  final String invoiceDate;
  final String? dueDate;
  final num totalAmount;
  final num paidAmount;
  final num balanceAmount;
  final String status;
  final num returnedAmount;
  final num? returnFee;
  final String? discountScope; // 'item' | 'invoice'
  final String? discountType; // 'percentage' | 'flat' | 'none'
  final num? discountValue;
  final Discount? discount; // nested form shape, when the API returns it
  final List<InvoiceItem>? items;
  final String? notes;
  final String? terms;
  final int? createdBy;
  final String? createdByUsername;
  final String? createdAt;
  final String? updatedAt;
  final int? soId;
  final String? soNo;
  final String? sourceType; // 'SALES_ORDER' | 'DIRECT' | 'POS' | null
  final int? quotationId;
  final String? quotationNo;
  final int? warehouseId;
  final String? warehouseCode;
  final String? warehouseName;
  final String? expiryNotes;
  final CompanyInfo? company;
  final InvoicePayment? payment;
  final List<PaymentMethod>? paymentMethods;

  Map<String, dynamic> toJson() => {
    'id': id,
    'invoice_no': invoiceNo,
    'customer_id': customerId,
    if (customerName != null) 'customer_name': customerName,
    if (customerEmail != null) 'customer_email': customerEmail,
    if (customerPhone != null) 'customer_phone': customerPhone,
    if (customerAddress != null) 'customer_address': customerAddress,
    if (customerCurrentBalance != null)
      'customer_current_balance': customerCurrentBalance,
    if (customerCreditLimit != null)
      'customer_credit_limit': customerCreditLimit,
    if (customerCreditUtilization != null)
      'customer_credit_utilization': customerCreditUtilization,
    'invoice_date': invoiceDate,
    if (dueDate != null) 'due_date': dueDate,
    'total_amount': totalAmount,
    'paid_amount': paidAmount,
    'balance_amount': balanceAmount,
    'status': status,
    'returned_amount': returnedAmount,
    if (returnFee != null) 'return_fee': returnFee,
    if (discountScope != null) 'discount_scope': discountScope,
    if (discountType != null) 'discount_type': discountType,
    if (discountValue != null) 'discount_value': discountValue,
    if (discount != null) 'discount': discount!.toJson(),
    if (items != null) 'items': items!.map((e) => e.toJson()).toList(),
    if (notes != null) 'notes': notes,
    if (terms != null) 'terms': terms,
    if (createdBy != null) 'created_by': createdBy,
    if (createdByUsername != null) 'created_by_username': createdByUsername,
    if (createdAt != null) 'created_at': createdAt,
    if (updatedAt != null) 'updated_at': updatedAt,
    if (soId != null) 'so_id': soId,
    if (soNo != null) 'so_no': soNo,
    if (sourceType != null) 'source_type': sourceType,
    if (quotationId != null) 'quotation_id': quotationId,
    if (quotationNo != null) 'quotation_no': quotationNo,
    if (warehouseId != null) 'warehouse_id': warehouseId,
    if (warehouseCode != null) 'warehouse_code': warehouseCode,
    if (warehouseName != null) 'warehouse_name': warehouseName,
    if (expiryNotes != null) 'expiry_notes': expiryNotes,
    if (company != null) 'company': company!.toJson(),
    if (payment != null) 'payment': payment!.toJson(),
    if (paymentMethods != null)
      'paymentMethods': paymentMethods!.map((e) => e.toJson()).toList(),
  };

  /// Parses a JSON array of objects into typed items, skipping junk.
  static List<T>? _parseList<T>(
    Object? value,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (value is! List) return null;
    return [
      for (final item in value)
        if (item is Map<String, dynamic>) fromJson(item),
    ];
  }
}
