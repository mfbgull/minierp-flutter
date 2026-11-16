// UX-13 (audit/GLM-UX-REVIEW.md) — the sales-order line's discount value
// only validates the percentage kind (amount >= 100). A FLAT discount larger
// than the line total passes local validation and reaches the server, which
// then refuses (or, worse, computes a negative line).
//
// Pin: a flat discount above the line total must fail form validation with
// an error on the discount field. RED today by design.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/data/models/invoice.dart' show DiscountType;
import 'package:minierp_app/features/sales_orders/sales_order_form_dialog.dart';

import '../test_helpers.dart';

void main() {
  testWidgets(
    'a flat discount above the line total is rejected by the form validator',
    (tester) async {
      final dio = createFakeDio({
        '/customers': pagedEnvelope([
          {'id': 1, 'customer_code': 'C-1', 'customer_name': 'Test customer'},
        ]),
        '/inventory/items': pagedEnvelope([
          {'id': 1, 'item_code': 'ITM-1', 'item_name': 'Test item'},
        ]),
        '/inventory/warehouses': {
          'success': true,
          'data': [
            {'id': 1, 'warehouse_code': 'WH-1', 'warehouse_name': 'Main'},
          ],
        },
      });

      await tester.pumpWidget(
        buildTestable(
          const Scaffold(body: SalesOrderFormDialog()),
          dio: dio,
        ),
      );
      await tester.pumpAndSettle();

      // Valid quantity and price: line total = 100.
      await tester.enterText(
        find.byKey(const ValueKey('so-line-quantity')),
        '10',
      );
      await tester.enterText(
        find.byKey(const ValueKey('so-line-price')),
        '10',
      );
      // Flat discount of 150 against a 100 line.
      await tester.tap(
        find.byType(DropdownButtonFormField<DiscountType?>).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Amount').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('so-line-discount-value')),
        '150',
      );

      final submit = find
          .byWidgetPredicate((widget) => widget is FilledButton)
          .last;
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();

      // Every OTHER field validator passes here, so the only possible
      // field error is the discount's.
      final discountField = find.descendant(
        of: find.byKey(const ValueKey('so-line-discount-value')),
        matching: find.byType(TextField),
      );
      expect(
        tester.widget<TextField>(discountField.first).decoration?.errorText,
        isNotNull,
        reason:
            'a flat discount above the line total must be flagged locally, '
            'not sent to the server',
      );
    },
    // RED-BY-DESIGN — UX-13 (audit/GLM-UX-REVIEW.md): a flat discount above
    // the line total still passes local validation. Un-skip when UX-13 is
    // fixed. FAILURE_WHEN_FIXED.
    skip: true,
  );
}
