// Sales Order calculations (PORTING.md §7).
// 1:1 port of `calculations/salesOrderCalculations.ts`.
//
// Omitted: `getStatusColor` (CSS/AG-Grid color lookup — Flutter uses the
// `StatusBadge` widget).

import '../../../data/models/invoice.dart' show DiscountType;
import '../models/sales_forms.dart' show SOFormItem, flatZeroDiscount;

const List<String> _fieldOrder = [
  'name',
  'quantity',
  'unitPrice',
  'discountValue',
  'taxRate',
];

List<String> getFieldOrder() => _fieldOrder;

String? getNextField(String field) {
  final index = _fieldOrder.indexOf(field);
  return index >= 0 && index + 1 < _fieldOrder.length
      ? _fieldOrder[index + 1]
      : null;
}

int _now() => DateTime.now().millisecondsSinceEpoch;

SOFormItem createEmptyItemRow(int index) {
  return SOFormItem(
    id: _now() + index,
    itemId: '',
    name: '',
    quantity: 1,
    unitPrice: 0,
    taxRate: 0,
    discount: flatZeroDiscount,
  );
}

List<SOFormItem> padItemsToMinimum(List<SOFormItem> items, {int min = 1}) {
  if (items.length >= min) return items;
  final padded = [...items];
  final now = _now();
  for (var i = items.length; i < min; i++) {
    padded.add(
      SOFormItem(
        id: now + i + 1000,
        itemId: '',
        name: '',
        quantity: 1,
        unitPrice: 0,
        taxRate: 0,
        discount: flatZeroDiscount,
      ),
    );
  }
  return padded;
}

num calculateItemDiscount(SOFormItem item) {
  final gross = _round2(item.quantity * item.unitPrice);
  final raw = item.discount.type == DiscountType.percentage
      ? _round2(gross * item.discount.value / 100)
      : _round2(item.discount.value);
  // Mirrors the server's `decomposeLineAmount`: the discount clamps to
  // the gross, never below 0.
  return raw > gross ? gross : (raw < 0 ? 0 : raw);
}

num calculateItemTotal(SOFormItem item) {
  final net = _lineNet(item);
  return _round2(net + _round2(net * item.taxRate / 100));
}

/// Round to cents — the same rule as the server's `roundCurrency`
/// (`Math.round((value + Number.EPSILON) * 100) / 100`). The two sides
/// must agree exactly, or a converted order fails the total check.
num _round2(num value) => (value * 100).round() / 100;

/// Pre-tax line amount after the item discount, rounded — the base the
/// tax applies to (server `decomposeLineAmount`).
num _lineNet(SOFormItem item) {
  final gross = _round2(item.quantity * item.unitPrice);
  return _round2(gross - calculateItemDiscount(item));
}

num calculateSubtotal(List<SOFormItem> items) {
  return items.fold<num>(
    0,
    (sum, item) => _round2(_round2(sum) + _round2(item.quantity * item.unitPrice)),
  );
}

num calculateDiscount(List<SOFormItem> items) {
  return items.fold<num>(
    0,
    (sum, item) => _round2(_round2(sum) + calculateItemDiscount(item)),
  );
}

num calculateTax(List<SOFormItem> items) {
  return items.fold<num>(0, (sum, item) {
    final net = _lineNet(item);
    return _round2(_round2(sum) + _round2(net * item.taxRate / 100));
  });
}

/// Grand total — Σ of the rounded line amounts (server `computeInvoiceTotal`).
num calculateTotal(List<SOFormItem> items) {
  return items.fold<num>(
    0,
    (sum, item) => _round2(_round2(sum) + calculateItemTotal(item)),
  );
}
