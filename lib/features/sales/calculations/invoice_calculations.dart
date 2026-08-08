// Invoice calculations — all pure functions, no UI imports (PORTING.md §7).
// 1:1 port of `calculations/invoiceCalculations.ts`.
//
// The functions are typed against the `CalculableLine` interface so both
// invoice grids (form-shape `InvoiceFormItem` and V2 `InvoiceV2FormItem`)
// share one implementation.
//
// Omitted from the TS source on purpose: `getStatusColor` (a CSS/AG-Grid
// color lookup — the Flutter equivalent is the `StatusBadge` widget, see
// `widgets/status_badge.dart`; calculation code stays UI-free).

import '../../../data/models/invoice.dart'
    show Discount, DiscountType, PaymentMethod;
import '../../../data/models/item.dart' show SaleType;
import '../models/sales_forms.dart'
    show
        CalculableLine,
        DiscountScope,
        EditedField,
        InvoiceFormItem,
        InvoiceFormPayment,
        InvoiceFormState,
        defaultCompany,
        flatZeroDiscount,
        isoDate;

/* ── Item-level calculations ────────────────────────────────────── */

/// Base amount of a line. Loose lines where the user typed the Amount use
/// it verbatim — qty × rate would differ by the quantity rounding.
num calculateItemBase(CalculableLine item) {
  if (item.saleType == SaleType.loose &&
      item.lastEditedField == EditedField.amount) {
    return item.amount;
  }
  return item.quantity * item.rate;
}

/// Discount amount for a single item.
num calculateItemDiscount(CalculableLine item) {
  final subtotal = calculateItemBase(item);
  if (item.discount.type == DiscountType.percentage) {
    return (subtotal * item.discount.value) / 100;
  }
  return item.discount.value;
}

/// Total for a single item (subtotal − discount + tax).
num calculateItemTotal(
  CalculableLine item, {
  DiscountScope discountScope = DiscountScope.item,
}) {
  final subtotal = calculateItemBase(item);
  final discount = discountScope == DiscountScope.item
      ? calculateItemDiscount(item)
      : 0;
  final afterDiscount = subtotal - discount;
  final taxAmount = (afterDiscount * item.tax) / 100;
  return afterDiscount + taxAmount;
}

/* ── Aggregate calculations ─────────────────────────────────────── */

/// Subtotal (sum of qty × rate for all items).
num calculateSubtotal(List<CalculableLine> items) {
  return items.fold<num>(0, (sum, item) => sum + calculateItemBase(item));
}

/// Total tax across all items.
num calculateTax(
  List<CalculableLine> items, {
  DiscountScope discountScope = DiscountScope.item,
}) {
  return items.fold<num>(0, (sum, item) {
    final subtotal = calculateItemBase(item);
    final discount = discountScope == DiscountScope.item
        ? calculateItemDiscount(item)
        : 0;
    final afterDiscount = subtotal - discount;
    return sum + (afterDiscount * item.tax) / 100;
  });
}

/// Total discount across all items (or invoice-level discount).
num calculateDiscount(
  List<CalculableLine> items,
  DiscountScope discountScope,
  Discount invoiceDiscount,
) {
  if (discountScope == DiscountScope.item) {
    return items.fold<num>(0, (sum, item) => sum + calculateItemDiscount(item));
  }
  final subtotal = calculateSubtotal(items);
  if (invoiceDiscount.type == DiscountType.percentage) {
    return (subtotal * invoiceDiscount.value) / 100;
  }
  return invoiceDiscount.value;
}

/// Grand total (subtotal + tax − discount).
num calculateTotal(
  List<CalculableLine> items,
  DiscountScope discountScope,
  Discount invoiceDiscount,
) {
  return calculateSubtotal(items) +
      calculateTax(items, discountScope: discountScope) -
      calculateDiscount(items, discountScope, invoiceDiscount);
}

/* ── Field navigation ───────────────────────────────────────────── */

const List<String> _fieldOrderItem = [
  'description',
  'quantity',
  'rate',
  'discountValue',
  'tax',
  'amount',
];

const List<String> _fieldOrderInvoice = [
  'description',
  'quantity',
  'rate',
  'tax',
  'amount',
];

List<String> getFieldOrder(DiscountScope discountScope) {
  return discountScope == DiscountScope.item
      ? _fieldOrderItem
      : _fieldOrderInvoice;
}

String? getNextField(String field, DiscountScope discountScope) {
  final order = getFieldOrder(discountScope);
  final currentIndex = order.indexOf(field);
  return currentIndex >= 0 && currentIndex + 1 < order.length
      ? order[currentIndex + 1]
      : null;
}

/* ── Item helpers ───────────────────────────────────────────────── */

int _now() => DateTime.now().millisecondsSinceEpoch;

InvoiceFormItem createEmptyItemRow(int index) {
  return InvoiceFormItem(
    id: _now() + index,
    itemId: '',
    description: '',
    quantity: 1,
    rate: 0,
    tax: 0,
    discount: flatZeroDiscount,
    saleType: SaleType.packed,
    amount: 0,
    lastEditedField: null,
    qtyDecimalPrecision: 0,
    roundingStep: null,
  );
}

List<CalculableLine> padItemsToMinimum(
  List<CalculableLine> items, {
  int min = 1,
}) {
  if (items.length >= min) return items;
  final padded = [...items];
  final now = _now();
  for (var i = items.length; i < min; i++) {
    padded.add(
      InvoiceFormItem(
        id: now + i + 1000,
        itemId: '',
        description: '',
        quantity: 0,
        rate: 0,
        tax: 0,
        discount: flatZeroDiscount,
        saleType: SaleType.packed,
        amount: 0,
        lastEditedField: null,
        qtyDecimalPrecision: 0,
        roundingStep: null,
      ),
    );
  }
  return padded;
}

/* ── Status helpers ─────────────────────────────────────────────── */

String getExpectedStatus(
  String? invoiceId,
  bool recordPayment,
  List<PaymentMethod> paymentMethods,
  List<CalculableLine> items,
  DiscountScope discountScope,
  Discount invoiceDiscount, {
  String? currentStatus,
}) {
  if (invoiceId == null || invoiceId.isEmpty) {
    if (recordPayment) {
      final total = calculateTotal(items, discountScope, invoiceDiscount);
      final paymentAmount = paymentMethods.fold<num>(
        0,
        (sum, m) => sum + m.amount,
      );
      if (paymentAmount >= total) return 'Paid';
      if (paymentAmount > 0) return 'Partially Paid';
    }
    return 'Unpaid';
  }
  return currentStatus ?? 'Unpaid';
}

/* ── Invoice number generation ──────────────────────────────────── */

String generateInvoiceNo() {
  final now = DateTime.now();
  return 'INV-${now.year}-${(now.millisecondsSinceEpoch % 1000000).toString().padLeft(6, '0')}';
}

/* ── Default invoice state ──────────────────────────────────────── */

InvoiceFormState createDefaultInvoice() {
  return InvoiceFormState(
    invoiceNo: generateInvoiceNo(),
    status: 'Unpaid',
    invoiceDate: isoDate(),
    dueDate: isoDate(const Duration(days: 14)),
    customerId: '',
    customerName: '',
    customerEmail: '',
    customerPhone: '',
    customerAddress: '',
    discountScope: DiscountScope.invoice,
    discount: flatZeroDiscount,
    items: [createEmptyItemRow(0)],
    notes: 'Thank you for your business. Payment is due within 14 days.',
    terms: 'Net 14 days. Late payments subject to 1.5% monthly interest.',
    createdBy: null,
    company: defaultCompany,
    payment: InvoiceFormPayment(
      recordPayment: true,
      paymentDate: isoDate(),
      paymentAmount: 0,
      paymentMethod: 'Cash',
      referenceNo: '',
      paymentNotes: '',
    ),
    paymentMethods: [
      PaymentMethod(id: _now(), method: 'Cash', amount: 0, referenceNo: ''),
    ],
  );
}
