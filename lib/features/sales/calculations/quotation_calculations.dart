// Quotation calculations (PORTING.md §7).
// 1:1 port of `calculations/quotationCalculations.ts`.
//
// Omitted: `getStatusColor` (CSS/AG-Grid color lookup — Flutter uses the
// `StatusBadge` widget). `filterFilledItems` lives in
// `../models/sales_forms.dart` (shared with invoiceRules).

import '../../../data/models/invoice.dart' show DiscountType;
import '../../../data/models/item.dart' show Item;
import '../models/sales_forms.dart' show QuotationFormItem, flatZeroDiscount;

/* ── Item row utilities ─────────────────────────────────────────── */

int _now() => DateTime.now().millisecondsSinceEpoch;

QuotationFormItem createEmptyItemRow(int index) {
  return QuotationFormItem(
    id: _now() + index,
    itemId: '',
    description: '',
    quantity: 1,
    rate: 0,
    tax: 0,
    discount: flatZeroDiscount,
  );
}

List<QuotationFormItem> padItemsToMinimum(List<QuotationFormItem> items,
    {int min = 1}) {
  if (items.length >= min) return items;
  final padded = [...items];
  final now = _now();
  for (var i = items.length; i < min; i++) {
    padded.add(QuotationFormItem(
      id: now + i + 1000,
      itemId: '',
      description: '',
      quantity: 1,
      rate: 0,
      tax: 0,
      discount: flatZeroDiscount,
    ));
  }
  return padded;
}

/* ── Calculations ───────────────────────────────────────────────── */

num calculateItemDiscount(QuotationFormItem item) {
  final subtotal = item.quantity * item.rate;
  if (item.discount.type == DiscountType.percentage) {
    return (subtotal * item.discount.value) / 100;
  }
  return item.discount.value;
}

num calculateItemTotal(QuotationFormItem item) {
  final subtotal = item.quantity * item.rate;
  final discount = calculateItemDiscount(item);
  final afterDiscount = subtotal - discount;
  final taxAmount = (afterDiscount * item.tax) / 100;
  return afterDiscount + taxAmount;
}

num calculateSubtotal(List<QuotationFormItem> items) {
  return items.fold<num>(
      0, (sum, item) => sum + (item.quantity * item.rate));
}

num calculateDiscount(List<QuotationFormItem> items) {
  return items.fold<num>(0, (sum, item) => sum + calculateItemDiscount(item));
}

num calculateTax(List<QuotationFormItem> items) {
  return items.fold<num>(0, (sum, item) {
    final subtotal = item.quantity * item.rate;
    final discount = calculateItemDiscount(item);
    final afterDiscount = subtotal - discount;
    return sum + (afterDiscount * item.tax / 100);
  });
}

num calculateTotal(List<QuotationFormItem> items) {
  return calculateSubtotal(items) - calculateDiscount(items) + calculateTax(items);
}

/* ── Field navigation ───────────────────────────────────────────── */

const List<String> _fieldOrder = [
  'description',
  'quantity',
  'rate',
  'discountValue',
  'tax',
];

List<String> getFieldOrder() => _fieldOrder;

String? getNextField(String currentField) {
  final currentIndex = _fieldOrder.indexOf(currentField);
  return currentIndex >= 0 && currentIndex + 1 < _fieldOrder.length
      ? _fieldOrder[currentIndex + 1]
      : null;
}

/* ── Validation / submission ────────────────────────────────────── */

/// Sellable items for the quotation line picker: not raw material, and
/// marked finished-good or purchased. TS returns a projected subset and
/// slices to 10; Dart returns the (superset) `Item` models.
List<Item> getSellableItems(List<Item> items) {
  return items
      .where((item) =>
          !item.isRawMaterial &&
          (item.isFinishedGood || item.isPurchased))
      .take(10)
      .toList();
}
