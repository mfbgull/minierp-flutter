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
        InvoiceFormItem,
        InvoiceFormPayment,
        InvoiceFormState,
        defaultCompany,
        flatZeroDiscount,
        isoDate;

/* ── Item-level calculations ────────────────────────────────────── */

/// Round to cents — mirrors the server's `roundCurrency` so the
/// displayed totals agree with ACC-18 validation and storage exactly.
num _round2(num value) => (value * 100).round() / 100;

/// Base amount of a line. Amount-driven loose lines (flip model, spec
/// §5.2) bill the entered amount verbatim — qty × rate would differ by
/// the quantity rounding.
num calculateItemBase(CalculableLine item) {
  if (item.saleType == SaleType.loose && item.amountDriven) {
    return item.amount;
  }
  return item.quantity * item.rate;
}

/// Rounded gross of a line — the server's `decomposeLineAmount` rounds
/// the base before applying discount/tax.
num _lineGross(CalculableLine item) => _round2(calculateItemBase(item));

/// Discount amount for a single item (capped at the gross, like the
/// server's `Math.min(discountAmount, gross)`).
num _lineDiscount(CalculableLine item, num gross) {
  final raw = item.discount.type == DiscountType.percentage
      ? gross * item.discount.value / 100
      : item.discount.value;
  final rounded = _round2(raw);
  return rounded > gross ? gross : (rounded < 0 ? 0 : rounded);
}

/// Net (pre-tax) amount of a line after its item-scope discount.
num _lineNet(CalculableLine item, num gross, DiscountScope discountScope) {
  final discount = discountScope == DiscountScope.item
      ? _lineDiscount(item, gross)
      : 0;
  return _round2(gross - discount);
}

/// Discount amount for a single item.
num calculateItemDiscount(CalculableLine item) =>
    _lineDiscount(item, _lineGross(item));

/// Total for a single line (gross − item-scope discount + tax), each
/// boundary rounded like the server stores it.
num calculateItemTotal(
  CalculableLine item, {
  DiscountScope discountScope = DiscountScope.item,
}) {
  final net = _lineNet(item, _lineGross(item), discountScope);
  final taxAmount = _round2(net * item.tax / 100);
  return net + taxAmount;
}

/* ── Aggregate calculations ─────────────────────────────────────── */

/// Subtotal (Σ of rounded line grosses).
num calculateSubtotal(List<CalculableLine> items) {
  return items.fold<num>(0, (sum, item) => sum + _lineGross(item));
}

/// Total tax across all items (per-line rounded, on the post-discount
/// net — invoice-scope discounts don't reduce the tax base).
num calculateTax(
  List<CalculableLine> items, {
  DiscountScope discountScope = DiscountScope.item,
}) {
  return items.fold<num>(0, (sum, item) {
    final net = _lineNet(item, _lineGross(item), discountScope);
    return sum + _round2(net * item.tax / 100);
  });
}

/// Total discount across all items (or invoice-level discount applied
/// on the subtotal, capped at it).
num calculateDiscount(
  List<CalculableLine> items,
  DiscountScope discountScope,
  Discount invoiceDiscount,
) {
  if (discountScope == DiscountScope.item) {
    return items.fold<num>(
      0,
      (sum, item) => sum + _lineDiscount(item, _lineGross(item)),
    );
  }
  final subtotal = calculateSubtotal(items);
  final raw = invoiceDiscount.type == DiscountType.percentage
      ? subtotal * invoiceDiscount.value / 100
      : invoiceDiscount.value;
  final rounded = _round2(raw);
  return rounded > subtotal ? subtotal : (rounded < 0 ? 0 : rounded);
}

/// Grand total (subtotal + tax − discount). With every boundary rounded
/// here exactly like `computeInvoiceGrandTotal` on the server, this is
/// the number ACC-18 validation expects as `total_amount`.
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
