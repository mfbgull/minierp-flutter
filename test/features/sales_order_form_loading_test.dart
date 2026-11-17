// UX-11 (audit/GLM-UX-REVIEW.md) — the sales-order form watches its option
// providers. Three async states must be distinguishable to the user:
//
//   pending  -> loading feedback (not a blank form)
//   error    -> the failure surfaces (l10n.errorsFailed) with a retry
//   empty    -> normal empty pickers, and NO loading feedback
//
// The original code read every provider as `valueOrNull ?? []`, so error
// rendered like empty and pending rendered like empty. These tests pin all
// three states.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/data/models/customer.dart';
import 'package:minierp_app/features/sales_orders/sales_order_form_dialog.dart';
import 'package:minierp_app/features/sales_orders/sales_order_providers.dart';
import 'package:minierp_app/widgets/searchable_select.dart';

import '../test_helpers.dart';

Map<String, dynamic> get _itemsStub => pagedEnvelope([
      {'id': 1, 'item_code': 'ITM-1', 'item_name': 'Test item'},
    ]);
Map<String, dynamic> get _warehousesStub => {
      'success': true,
      'data': [
        {'id': 1, 'warehouse_code': 'WH-1', 'warehouse_name': 'Main'},
      ],
    };

Future<void> _pumpForm(WidgetTester tester, Dio dio,
    {List<Override> overrides = const []}) async {
  await tester.pumpWidget(
    buildTestable(
      const Scaffold(body: SalesOrderFormDialog()),
      dio: dio,
      overrides: overrides,
    ),
  );
}

void main() {
  testWidgets(
    'a failed customer load is surfaced to the user, not rendered as an empty picker',
    (tester) async {
      // /customers is deliberately NOT stubbed: its GET 404s and the
      // provider errors. Items and warehouses load normally, so the only
      // broken provider is the one under test.
      final dio = createFakeDio({
        '/inventory/items': _itemsStub,
        '/inventory/warehouses': _warehousesStub,
      });

      await _pumpForm(tester, dio);
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

  testWidgets(
    'pending option providers show loading feedback, unlike a loaded empty list',
    (tester) async {
      // The customer provider never completes: the form must show that the
      // options are still LOADING, not silently render blank pickers that
      // are indistinguishable from "no customers yet".
      final pendingCustomers = salesOrderCustomerOptionsProvider.overrideWith(
        (ref) => Completer<List<Customer>>().future,
      );
      final dio = createFakeDio({
        '/inventory/items': _itemsStub,
        '/inventory/warehouses': _warehousesStub,
      });

      await _pumpForm(tester, dio, overrides: [pendingCustomers]);
      // Plain pumps, NOT pumpAndSettle: an animated loading indicator never
      // settles, and that is exactly the state under test.
      await tester.pump(const Duration(milliseconds: 150));

      expect(
        find.byType(LinearProgressIndicator),
        findsOneWidget,
        reason:
            'pending option providers must show loading feedback — a blank '
            'form is indistinguishable from "no customers yet"',
      );
    },
  );

  testWidgets(
    'a loaded (empty) customer list shows NO loading feedback',
    (tester) async {
      // The control for the test above: once the providers HAVE resolved
      // (even to an empty list), the loading indicator must be gone. This
      // is what makes "loading" and "empty" distinguishable states.
      final dio = createFakeDio({
        '/customers': pagedEnvelope(<Map<String, dynamic>>[]),
        '/inventory/items': pagedEnvelope(<Map<String, dynamic>>[]),
        '/inventory/warehouses': {
          'success': true,
          'data': <Map<String, dynamic>>[],
        },
      });

      await _pumpForm(tester, dio);
      await tester.pumpAndSettle();

      expect(
        find.byType(LinearProgressIndicator),
        findsNothing,
        reason:
            'loading feedback is for PENDING providers only; an empty '
            'success must not keep the form in a loading state',
      );
    },
  );

  testWidgets(
    'retrying after a failed customer load recovers the picker',
    (tester) async {
      // /customers 404s on the first call and succeeds after the retry.
      // The stub map is mutated between the failure and the tap, so the
      // invalidated provider refetches into success.
      final stubs = <String, dynamic>{
        '/inventory/items': _itemsStub,
        '/inventory/warehouses': _warehousesStub,
      };
      final dio = createFakeDio(stubs);

      await _pumpForm(tester, dio);
      await tester.pumpAndSettle();
      expect(find.textContaining('Failed'), findsWidgets);

      stubs['/customers'] = pagedEnvelope([
        {'id': 1, 'customer_code': 'C-1', 'customer_name': 'Test customer'},
      ]);
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Failed'),
        findsNothing,
        reason: 'a successful retry must clear the error state',
      );
      // The recovered options are actually usable: open the customer
      // picker and find the customer.
      await tester.tap(find.byType(SearchableSelect<int>).first);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('C-1').last,
        findsOneWidget,
        reason: 'after a successful retry the customer options must load',
      );
    },
  );
}
