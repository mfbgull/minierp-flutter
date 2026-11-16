// UX-3 (audit/GLM-UX-REVIEW.md) — the supplier-refund dialog reuses the
// purchase-return quantity strings for refund AMOUNT errors:
// supplier_refund_dialog.dart maps an invalid amount to
// `purchasesReturnqtyinvalid` ("Enter a valid return quantity") and an
// over-claim amount to `purchasesReturnqtyexceeds`. The user is on a refund
// form and reads about a "return quantity".
//
// Pin: an over-claim amount error must NOT talk about quantities.
// RED today by design — the fix gives refund amounts their own strings.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/data/models/purchase_return.dart';
import 'package:minierp_app/features/purchases/supplier_refund_dialog.dart';
import 'package:minierp_app/widgets/form_helpers.dart' show ErrorBanner;

import '../test_helpers.dart';

void main() {
  testWidgets(
    'an over-claim refund amount shows a refund-specific error, not a return-quantity message',
    (tester) async {
      final dio = createFakeDio({});
      await tester.pumpWidget(
        buildTestable(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showSupplierRefundDialog(
                  context,
                  purchaseReturn: PurchaseReturn.fromJson({
                    'id': 1,
                    'credit_note_id': 1,
                  }),
                  refundable: 200,
                ),
                child: const Text('Open refund'),
              ),
            ),
          ),
          dio: dio,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open refund'));
      await tester.pumpAndSettle();

      // Amount above the refundable 200: the server would refuse it too.
      await tester.enterText(find.byType(TextField).first, '300');
      final submit = find
          .byWidgetPredicate((widget) => widget is FilledButton)
          .last;
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();

      // Some error IS shown.
      expect(find.byType(ErrorBanner), findsOneWidget);
      // But it must not speak about a return quantity.
      expect(
        find.textContaining('quantity'),
        findsNothing,
        reason:
            'a refund-amount error must not reuse the return-quantity strings',
      );
    },
  );
}
