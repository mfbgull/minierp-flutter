// Form-state models used by the sales calculations (PORTING.md §7).
//
// These are NOT wire models: they mirror the client form types in
// `types/client-types.ts` (`InvoiceFormItem`, `InvoiceFormState`,
// `QuotationFormItem`, `SOFormItem`) and `types/invoiceV2.ts`
// (`InvoiceV2FormItem`, `InvoiceV2State`). The data layer keeps the
// server shapes (`data/models/`); these live in the sales feature.
//
// Port decisions:
// - `itemId`/`customerId` are normalized to `String`. TS types them
//   `number | string`; the calculations never branch on that difference
//   and fresh-row placeholders (TS `''` for invoice/SO, `0` for
//   quotation) collapse to `''`, which preserves the falsy semantics of
//   `filterFilledItems`.
// - Immutable with const constructors; `copyWith` is deferred to the
//   invoice-form port where the mutation surface is known.
// - Reuses `Discount`/`DiscountType`, `PaymentMethod`, `CompanyInfo`
//   and `SaleType` from the data models instead of re-declaring them.

import '../../../data/models/invoice.dart'
    show CompanyInfo, Discount, DiscountType, PaymentMethod;
import '../../../data/models/item.dart' show SaleType;

/// `'item' | 'invoice'` discount scope (client invoice types).
enum DiscountScope {
  item('item'),
  invoice('invoice');

  const DiscountScope(this.value);

  final String value;
}

/// Which field the user last edited on a line — drives loose
/// recalculation (`lastEditedField` in the form types).
enum EditedField {
  quantity('quantity'),
  amount('amount');

  const EditedField(this.value);

  final String value;
}

/// Minimal surface the shared invoice math reads from a form line.
/// Implemented by `InvoiceFormItem` and `InvoiceV2FormItem` so both
/// grids share one implementation (the TS code casts between the two
/// shapes; Dart achieves the same via the interface, type-safely).
abstract interface class CalculableLine {
  num get quantity;
  num get rate;
  num get tax;
  Discount get discount;
  SaleType get saleType;
  num get amount;

  /// Sticky loose-line flag (spec §5.2): `true` once the amount has been
  /// edited — the line then bills the entered amount and derives qty.
  bool get amountDriven;

  EditedField? get lastEditedField;
}

/// A form line with the fields `filterFilledItems` tests for
/// (`item_id || description` in TS). `SOFormItem` intentionally does
/// not implement this — it has `name`, not `description`.
abstract interface class FillableLine {
  String get itemId;
  String get description;
}

/* ── Shared invoice-form defaults (used by the sales calculations) ── */

/// Zero flat discount — the default for every fresh row/state
/// (TS `{ type: 'flat', value: 0 }`).
const Discount flatZeroDiscount = Discount(type: DiscountType.flat, value: 0);

/// Today (or `offset` from today) as `YYYY-MM-DD` — TS
/// `new Date().toISOString().split('T')[0]`.
String isoDate([Duration? offset]) {
  final now = DateTime.now();
  return (offset == null ? now : now.add(offset))
      .toIso8601String()
      .split('T')
      .first;
}

/// Default company block printed on documents (web-client defaults).
const CompanyInfo defaultCompany = CompanyInfo(
  name: 'Mini ERP',
  email: 'support@minierp.com',
  phone: '+1 123 456 7890',
  address: '456 Enterprise Ave, BC 12345',
  taxId: 'TAX-123456789',
);

/// Port of `filterFilledItems` (invoiceRules.ts / quotationCalculations.ts).
/// In TS a row is "filled" when `item.item_id || item.description` is
/// truthy; with ids normalized to strings that is `itemId.isNotEmpty
/// || description.isNotEmpty`.
List<T> filterFilledItems<T extends FillableLine>(List<T> items) {
  return items
      .where((item) => item.itemId.isNotEmpty || item.description.isNotEmpty)
      .toList();
}

/// Invoice form line (`InvoiceFormItem` in types/client-types.ts).
/// `unit_of_measure` is UI-only and deferred with the form port.
class InvoiceFormItem implements CalculableLine, FillableLine {
  const InvoiceFormItem({
    required this.id,
    this.itemId = '',
    this.description = '',
    this.quantity = 0,
    this.rate = 0,
    this.tax = 0,
    required this.discount,
    this.saleType = SaleType.packed,
    this.amount = 0,
    this.amountDriven = false,
    this.lastEditedField,
    this.qtyDecimalPrecision = 0,
    this.roundingStep,
  });

  final int id;

  @override
  final String itemId;

  @override
  final String description;

  @override
  final num quantity;

  @override
  final num rate;

  @override
  final num tax;

  @override
  final Discount discount;

  @override
  final SaleType saleType;

  @override
  final num amount;

  @override
  final bool amountDriven;

  @override
  final EditedField? lastEditedField;

  final num qtyDecimalPrecision;
  final num? roundingStep;
}

/// Nested payment block of the invoice form (`InvoiceFormPayment`).
class InvoiceFormPayment {
  const InvoiceFormPayment({
    this.recordPayment = false,
    this.paymentDate = '',
    this.paymentAmount = 0,
    this.paymentMethod = '',
    this.referenceNo = '',
    this.paymentNotes = '',
  });

  final bool recordPayment;
  final String paymentDate;
  final num paymentAmount;
  final String paymentMethod;
  final String referenceNo;
  final String paymentNotes;
}

/// Full invoice form state (`InvoiceFormState` in types/client-types.ts).
/// `customer_id` normalized to `String` (see file header).
class InvoiceFormState {
  const InvoiceFormState({
    required this.invoiceNo,
    required this.status,
    required this.invoiceDate,
    required this.dueDate,
    required this.customerId,
    required this.customerName,
    required this.customerEmail,
    required this.customerPhone,
    required this.customerAddress,
    required this.discountScope,
    required this.discount,
    required this.items,
    required this.notes,
    required this.terms,
    required this.company,
    required this.payment,
    required this.paymentMethods,
    this.customerCurrentBalance,
    this.customerCreditLimit,
    this.customerCreditUtilization,
    this.createdBy,
    this.id,
    this.totalAmount,
    this.paidAmount,
    this.balanceAmount,
  });

  final String invoiceNo;
  final String status;
  final String invoiceDate;
  final String dueDate;
  final String customerId;
  final String customerName;
  final String customerEmail;
  final String customerPhone;
  final String customerAddress;
  final num? customerCurrentBalance;
  final num? customerCreditLimit;
  final num? customerCreditUtilization;
  final DiscountScope discountScope;
  final Discount discount;
  final List<InvoiceFormItem> items;
  final String notes;
  final String terms;
  final int? createdBy;
  final CompanyInfo company;
  final InvoiceFormPayment payment;
  final List<PaymentMethod> paymentMethods;
  final int? id;
  final num? totalAmount;
  final num? paidAmount;
  final num? balanceAmount;
}

/// Quotation form line (`QuotationFormItem` in types/client-types.ts).
class QuotationFormItem implements FillableLine {
  const QuotationFormItem({
    required this.id,
    this.itemId = '',
    this.description = '',
    this.quantity = 1,
    this.rate = 0,
    this.tax = 0,
    required this.discount,
  });

  final int id;

  @override
  final String itemId;

  @override
  final String description;

  final num quantity;
  final num rate;
  final num tax;
  final Discount discount;
}

/// Sales-order form line (`SOFormItem` in types/client-types.ts).
class SOFormItem {
  const SOFormItem({
    required this.id,
    this.itemId = '',
    this.name = '',
    this.quantity = 1,
    this.unitPrice = 0,
    this.taxRate = 0,
    required this.discount,
  });

  final int id;
  final String itemId;
  final String name;
  final num quantity;
  final num unitPrice;
  final num taxRate;
  final Discount discount;
}

/// Selected customer in the V2 invoice header (`InvoiceV2Customer`).
class InvoiceV2Customer {
  const InvoiceV2Customer({
    required this.id,
    required this.name,
    this.code,
    this.email = '',
    this.phone = '',
    this.address = '',
    this.balance = 0,
    this.creditLimit = 0,
    this.creditUtilization = 0,
  });

  final int id;
  final String name;
  final String? code;
  final String email;
  final String phone;
  final String address;
  final num balance;
  final num creditLimit;
  final num creditUtilization;
}

/// Document the V2 invoice was created from (`InvoiceV2Source`).
enum InvoiceV2SourceType {
  quotation('quotation'),
  so('so');

  const InvoiceV2SourceType(this.value);

  final String value;
}

class InvoiceV2Source {
  const InvoiceV2Source({
    required this.type,
    required this.id,
    required this.reference,
  });

  final InvoiceV2SourceType type;
  final int id;
  final String reference;
}

/// V2 invoice form line (`InvoiceV2FormItem` in types/invoiceV2.ts).
class InvoiceV2FormItem implements CalculableLine {
  const InvoiceV2FormItem({
    required this.id,
    this.itemId = '',
    this.description = '',
    this.quantity = 0,
    this.rate = 0,
    this.tax = 0,
    required this.discount,
    this.saleType = SaleType.packed,
    this.amount = 0,
    this.amountDriven = false,
    this.lastEditedField,
    this.qtyDecimalPrecision = 0,
    this.roundingStep,
  });

  final int id;
  final String itemId;
  final String description;

  @override
  final num quantity;

  @override
  final num rate;

  @override
  final num tax;

  @override
  final Discount discount;

  @override
  final SaleType saleType;

  @override
  final num amount;

  @override
  final bool amountDriven;

  @override
  final EditedField? lastEditedField;

  final num qtyDecimalPrecision;
  final num? roundingStep;
}

/// Payment block of the V2 state (`InvoiceV2Payment`).
class InvoiceV2Payment {
  const InvoiceV2Payment({
    this.recordPayment = false,
    this.paymentDate = '',
    this.paymentMethods = const [],
    this.paymentNotes = '',
  });

  final bool recordPayment;
  final String paymentDate;
  final List<PaymentMethod> paymentMethods;
  final String paymentNotes;
}

/// Full V2 invoice state (`InvoiceV2State` in types/invoiceV2.ts).
class InvoiceV2State {
  const InvoiceV2State({
    required this.invoiceNo,
    required this.customer,
    required this.invoiceDate,
    required this.dueDate,
    required this.discountScope,
    required this.discount,
    required this.items,
    required this.notes,
    required this.terms,
    required this.source,
    required this.payment,
    required this.company,
  });

  final String invoiceNo;
  final InvoiceV2Customer? customer;
  final String invoiceDate;
  final String dueDate;
  final DiscountScope discountScope;
  final Discount discount;
  final List<InvoiceV2FormItem> items;
  final String notes;
  final String terms;
  final InvoiceV2Source? source;
  final InvoiceV2Payment payment;
  final CompanyInfo company;
}
