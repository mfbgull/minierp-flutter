// 1:1 Dart port of `calculations/tests/invoiceLineCalc.test.ts`
// (PORTING.md §7 — test parity for the line calculation math).

import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/data/models/item.dart' show SaleType;
import 'package:minierp_app/features/sales/calculations/invoice_line_calc.dart';
import 'package:minierp_app/features/sales/models/sales_forms.dart'
    show EditedField;

void main() {
  group('roundToStep', () {
    test('rounds to the nearest step multiple', () {
      expect(roundToStep(0.6666, 0.001), 0.667);
      expect(roundToStep(1.234, 0.01), 1.23);
      expect(roundToStep(2.6, 1), 3);
      expect(roundToStep(1.2, 0.5), 1);
      expect(roundToStep(5, 0), 5); // no step → passthrough
    });
  });

  group('calcItemLine', () {
    test('packed items: quantity drives amount', () {
      expect(
        calcItemLine(const CalcItemLineInput(
            saleType: SaleType.packed, quantity: 5, rate: 150)),
        (quantity: 5, amount: 750, error: null),
      );
      expect(
        calcItemLine(const CalcItemLineInput(
            saleType: SaleType.packed, quantity: 3, rate: 10.33)),
        (quantity: 3, amount: 30.99, error: null),
      );
      // sale_type omitted defaults to packed
      expect(
        calcItemLine(const CalcItemLineInput(quantity: 2, rate: 4)),
        (quantity: 2, amount: 8, error: null),
      );
    });

    test('loose: amount drives quantity', () {
      expect(
        calcItemLine(const CalcItemLineInput(
          saleType: SaleType.loose,
          amount: 100,
          rate: 150,
          lastEditedField: EditedField.amount,
          qtyDecimalPrecision: 3,
        )),
        (quantity: 0.667, amount: 100, error: null),
      );
    });

    test('loose: amount with zero rate errors', () {
      final res = calcItemLine(const CalcItemLineInput(
        saleType: SaleType.loose,
        amount: 100,
        rate: 0,
        lastEditedField: EditedField.amount,
        qtyDecimalPrecision: 3,
      ));
      expect(res.error?.code, LineErrorCode.zeroRate);
      expect(res.error?.severity, LineErrorSeverity.error);
    });

    test('loose: amount too small warns about zero quantity', () {
      final res = calcItemLine(const CalcItemLineInput(
        saleType: SaleType.loose,
        amount: 1,
        rate: 150,
        lastEditedField: EditedField.amount,
        qtyDecimalPrecision: 1,
      ));
      expect(res.quantity, 0);
      expect(res.error?.code, LineErrorCode.zeroQuantity);
      expect(res.error?.severity, LineErrorSeverity.warning);
    });

    test('loose: quantity drives amount', () {
      expect(
        calcItemLine(const CalcItemLineInput(
            saleType: SaleType.loose,
            quantity: 5,
            rate: 150,
            lastEditedField: EditedField.quantity)),
        (quantity: 5, amount: 750, error: null),
      );
    });

    test('loose: rate change keeps the driver fixed', () {
      // amount-driven → quantity recomputed
      expect(
        calcItemLine(const CalcItemLineInput(
          saleType: SaleType.loose,
          amount: 100,
          rate: 200,
          lastEditedField: EditedField.amount,
          qtyDecimalPrecision: 3,
        )),
        (quantity: 0.5, amount: 100, error: null),
      );
      // quantity-driven → amount recomputed
      expect(
        calcItemLine(const CalcItemLineInput(
            saleType: SaleType.loose,
            quantity: 2,
            rate: 200,
            lastEditedField: EditedField.quantity)),
        (quantity: 2, amount: 400, error: null),
      );
    });

    test('loose: fresh row is a no-op', () {
      expect(
        calcItemLine(const CalcItemLineInput(
            saleType: SaleType.loose,
            quantity: 0,
            amount: 0,
            rate: 150,
            lastEditedField: null)),
        (quantity: 0, amount: 0, error: null),
      );
    });

    test('loose: explicit rounding_step overrides precision', () {
      expect(
        calcItemLine(const CalcItemLineInput(
          saleType: SaleType.loose,
          amount: 100,
          rate: 150,
          lastEditedField: EditedField.amount,
          qtyDecimalPrecision: 3,
          roundingStep: 0.5,
        )),
        (quantity: 0.5, amount: 100, error: null),
      );
    });
  });

  group('applyLineFieldUpdate', () {
    test('editing a field makes it the driver', () {
      const loose = CalcItemLineInput(
          saleType: SaleType.loose, qtyDecimalPrecision: 3, rate: 150);

      expect(
        applyLineFieldUpdate(loose, LineField.amount, 100),
        (
          quantity: 0.667,
          amount: 100,
          rate: 150,
          lastEditedField: EditedField.amount,
        ),
      );
      expect(
        applyLineFieldUpdate(loose, LineField.quantity, 2),
        (
          quantity: 2,
          amount: 300,
          rate: 150,
          lastEditedField: EditedField.quantity,
        ),
      );
    });

    test('rate edit keeps the existing driver', () {
      const amountDriven = CalcItemLineInput(
        saleType: SaleType.loose,
        qtyDecimalPrecision: 3,
        rate: 150,
        amount: 100,
        quantity: 0.667,
        lastEditedField: EditedField.amount,
      );
      expect(
        applyLineFieldUpdate(amountDriven, LineField.rate, 200),
        (
          quantity: 0.5,
          amount: 100,
          rate: 200,
          lastEditedField: EditedField.amount,
        ),
      );
    });

    test('packed lines never set a driver', () {
      const packed =
          CalcItemLineInput(saleType: SaleType.packed, rate: 10, quantity: 3);
      expect(
        applyLineFieldUpdate(packed, LineField.quantity, 4),
        (quantity: 4, amount: 40, rate: 10, lastEditedField: null),
      );
    });
  });

  group('lineIssue', () {
    test('only flags loose lines with a positive amount', () {
      expect(lineIssue(const CalcItemLineInput(
          saleType: SaleType.packed, amount: 100, rate: 0)), null);
      expect(lineIssue(const CalcItemLineInput(
          saleType: SaleType.loose, amount: 0, rate: 0)), null);
      expect(
        lineIssue(const CalcItemLineInput(
            saleType: SaleType.loose, amount: 100, rate: 0))?.code,
        LineErrorCode.zeroRate,
      );
      expect(
        lineIssue(const CalcItemLineInput(
          saleType: SaleType.loose,
          amount: 1,
          rate: 150,
          qtyDecimalPrecision: 1,
        ))?.code,
        LineErrorCode.zeroQuantity,
      );
    });
  });
}
