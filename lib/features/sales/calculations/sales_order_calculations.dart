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
    padded.add(SOFormItem(
      id: now + i + 1000,
      itemId: '',
      name: '',
      quantity: 1,
      unitPrice: 0,
      taxRate: 0,
      discount: flatZeroDiscount,
    ));
  }
  return padded;
}

num calculateItemDiscount(SOFormItem item) {    final subtotal = (item.quantity) * (item.unitPrice);
  if (item.discount.type == DiscountType.percentage) {
    return (subtotal * item.discount.value) / 100;
  }
  return item.discount.value;
}

num calculateItemTotal(SOFormItem item) {
  final subtotal = (item.quantity) * (item.unitPrice);
  final discount = calculateItemDiscount(item);
  final afterDiscount = subtotal - discount;
  final taxAmount = (afterDiscount * (item.taxRate)) / 100;
  return afterDiscount + taxAmount;
}

num calculateSubtotal(List<SOFormItem> items) {
  return items.fold<num>(
      0, (sum, item) => sum + (item.quantity) * (item.unitPrice));
}

num calculateDiscount(List<SOFormItem> items) {
  return items.fold<num>(0, (sum, item) => sum + calculateItemDiscount(item));
}

num calculateTax(List<SOFormItem> items) {
  return items.fold<num>(0, (sum, item) {
    final subtotal = (item.quantity) * (item.unitPrice);
    final discount = calculateItemDiscount(item);
    final afterDiscount = subtotal - discount;
    return sum + (afterDiscount * (item.taxRate)) / 100;
  });
}

num calculateTotal(List<SOFormItem> items) {
  return calculateSubtotal(items) - calculateDiscount(items) + calculateTax(items);
}
