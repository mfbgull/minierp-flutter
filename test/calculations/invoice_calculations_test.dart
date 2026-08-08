// 1:1 Dart port of `calculations/tests/invoiceCalculations.test.ts`
// (PORTING.md §7 — guards the loose-item branch in the aggregates).

import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/data/models/invoice.dart'
    show Discount, DiscountType;
import 'package:minierp_app/data/models/item.dart' show SaleType;
import 'package:minierp_app/features/sales/calculations/invoice_calculations.dart';
import 'package:minierp_app/features/sales/models/sales_forms.dart'
    show DiscountScope, EditedField, InvoiceFormItem;

const packed = InvoiceFormItem(
  id: 1,
  itemId: '1',
  description: 'Soap',
  quantity: 2,
  rate: 50,
  tax: 10,
  discount: Discount(type: DiscountType.flat, value: 0),
  saleType: SaleType.packed,
);

// ₹100 of rice at ₹150/kg → 0.667 kg. qty × rate = 100.05, but the customer pays 100.
const looseAmountDriven = InvoiceFormItem(
  id: 2,
  itemId: '2',
  description: 'Rice',
  quantity: 0.667,
  rate: 150,
  amount: 100,
  tax: 0,
  discount: Discount(type: DiscountType.flat, value: 0),
  saleType: SaleType.loose,
  lastEditedField: EditedField.amount,
);

const looseQtyDriven = InvoiceFormItem(
  id: 3,
  itemId: '3',
  description: 'Rice',
  quantity: 0.667,
  rate: 150,
  amount: 100,
  tax: 0,
  discount: Discount(type: DiscountType.flat, value: 0),
  saleType: SaleType.loose,
  lastEditedField: EditedField.quantity,
);

void main() {
  test('loose amount-driven lines bill the entered amount, not qty × rate', () {
    expect(calculateItemBase(looseAmountDriven), 100);
    expect(calculateItemTotal(looseAmountDriven), 100);
    // qty-driven falls back to qty × rate (raw float, same as packed lines)
    expect(calculateItemBase(looseQtyDriven), closeTo(100.05, 1e-9));
  });

  test('packed lines are unchanged', () {
    expect(calculateItemBase(packed), 100);
    expect(calculateItemTotal(packed), 110); // + 10% tax
  });

  test('aggregates use the same base as the line total', () {
    const items = [packed, looseAmountDriven];
    expect(calculateSubtotal(items), 200);
    expect(calculateTax(items, discountScope: DiscountScope.item), 10);
    expect(
      calculateTotal(
        items,
        DiscountScope.invoice,
        const Discount(type: DiscountType.flat, value: 0),
      ),
      210,
    );
    // Sum of line totals matches subtotal + tax − discount
    final lineSum = items.fold<num>(0, (s, i) => s + calculateItemTotal(i));
    expect(lineSum, 210);
  });

  test('per-item discount applies to the loose amount', () {
    const discounted = InvoiceFormItem(
      id: 2,
      itemId: '2',
      description: 'Rice',
      quantity: 0.667,
      rate: 150,
      amount: 100,
      tax: 0,
      discount: Discount(type: DiscountType.percentage, value: 10),
      saleType: SaleType.loose,
      lastEditedField: EditedField.amount,
    );
    expect(calculateItemTotal(discounted), 90);
    expect(
      calculateDiscount(
        [discounted],
        DiscountScope.item,
        const Discount(type: DiscountType.flat, value: 0),
      ),
      10,
    );
  });
}
