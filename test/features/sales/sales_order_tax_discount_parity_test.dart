// BUG-006 rounding parity — the Dart sales-order math must equal the
// server's `decomposeLineAmount` / `computeInvoiceTotal`.
//
// The case table below is duplicated in
// `server/src/__tests__/salesOrderTaxDiscount.test.ts` (the "rounding
// parity" describe). If the two disagree, a converted order can fail the
// server's total check — keep the numbers in step.
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/data/models/invoice.dart' show Discount, DiscountType;
import 'package:minierp_app/features/sales/calculations/sales_order_calculations.dart';
import 'package:minierp_app/features/sales/models/sales_forms.dart' show SOFormItem;

SOFormItem _line(
  num quantity,
  num unitPrice, {
  num taxRate = 0,
  DiscountType discountType = DiscountType.flat,
  num discountValue = 0,
}) => SOFormItem(
  id: 1,
  quantity: quantity,
  unitPrice: unitPrice,
  taxRate: taxRate,
  discount: Discount(type: discountType, value: discountValue),
);

void main() {
  group('sales order rounding parity (BUG-006)', () {
    // Each row mirrors one row of the server parity table.
    final cases = <String, (SOFormItem, num)>{
      'plain': (_line(3, 50), 150),
      'tax only': (_line(2, 100, taxRate: 17), 234),
      'percent discount only': (
        _line(1, 200, discountType: DiscountType.percentage, discountValue: 10),
        180,
      ),
      'flat discount only': (
        _line(1, 200, discountType: DiscountType.flat, discountValue: 25),
        175,
      ),
      'tax and percent discount': (
        _line(
          2,
          100,
          taxRate: 17,
          discountType: DiscountType.percentage,
          discountValue: 10,
        ),
        210.6,
      ),
      'rounding boundary three thirds': (
        _line(3, 33.333, taxRate: 17),
        // gross 99.999 -> 100.00; 17% -> 17.00; total 117.00
        117,
      ),
    };

    cases.forEach((name, entry) {
      test(name, () {
        expect(calculateItemTotal(entry.$1), closeTo(entry.$2, 0.0001));
      });
    });

    test('an order total is the sum of its rounded lines', () {
      final items = [
        _line(2, 100, taxRate: 17, discountType: DiscountType.percentage, discountValue: 10),
        _line(1, 200, discountType: DiscountType.flat, discountValue: 25),
      ];
      // 210.60 + 175.00
      expect(calculateTotal(items), closeTo(385.6, 0.0001));
    });
  });
}
