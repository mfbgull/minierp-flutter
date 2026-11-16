// UX-11 (audit/GLM-UX-REVIEW.md) — the sales-order form watches its option
// providers with `valueOrNull ?? []` (sales_order_form_dialog.dart:340,
// :532-536), so a failed fetch renders exactly like an empty list: no
// spinner, no message, no retry. The user sees blank pickers and cannot
// tell "no customers yet" from "the load broke".
//
// Pin: when the customer list fails, the failure must surface — like every
// other screen does (l10n.errorsFailed). RED today by design.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/features/sales_orders/sales_order_form_dialog.dart';

import '../test_helpers.dart';

void main() {
  testWidgets(
    'a failed customer load is surfaced to the user, not rendered as an empty picker',
    (tester) async {
      // /customers is deliberately NOT stubbed: its GET 404s and the
      // provider errors. Items and warehouses load normally, so the only
      // broken provider is the one under test.
      final dio = createFakeDio({
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

      expect(
        find.textContaining('Failed'),
        findsWidgets,
        reason:
            'a provider error must be visible, not silently swallowed by '
            'valueOrNull ?? []',
      );
    },
  );
}
