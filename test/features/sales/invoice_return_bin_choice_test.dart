// Invoice return — restock-bin choice for a line whose sale recorded no
// per-bin draw (Decision: "partial return of a line sold from two bins").
//
// A line the server marks `requires_return_bin` has no recorded draw, so
// the user must choose the bin; the dialog sends that choice as
// `location_id` on the line. A line whose draws WERE recorded replays them
// and must not carry a choice, and a legacy line sold from no batch needs
// none at all.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/features/sales/invoice_return_dialog.dart';
import 'package:minierp_app/widgets/searchable_select.dart';

import '../../test_helpers.dart';

/// The invoice under return: line 11 needs a bin choice, line 12 does not
/// (its sale recorded the draws).
Map<String, dynamic> _invoice({
  bool firstLineNeedsBin = true,
  List<Object?> firstLineDraws = const [],
  bool secondLineNeedsBin = false,
  List<Object?> secondLineDraws = const [
    {'batch_id': 7, 'location_id': 10, 'quantity': 4},
  ],
}) => {
  'id': 1,
  'invoice_no': 'INV-1',
  'customer_id': 1,
  'invoice_date': '2026-09-01',
  'total_amount': 200,
  'balance_amount': 200,
  'items': [
    {
      'id': 11,
      'invoice_id': 1,
      'item_id': 1,
      'item_name': 'Two-bin item',
      'quantity': 5,
      'unit_price': 10,
      'amount': 50,
      'returned_qty': 0,
      'bin_consumption': firstLineDraws,
      'requires_return_bin': firstLineNeedsBin,
    },
    {
      'id': 12,
      'invoice_id': 1,
      'item_id': 2,
      'item_name': 'Recorded-bin item',
      'quantity': 4,
      'unit_price': 10,
      'amount': 40,
      'returned_qty': 0,
      'bin_consumption': secondLineDraws,
      'requires_return_bin': secondLineNeedsBin,
    },
  ],
};

void main() {
  final locations = successEnvelope([
    {'location_id': 10, 'location_code': 'DEFAULT', 'location_name': 'Default'},
    {'location_id': 11, 'location_code': 'RACK-A', 'location_name': 'Rack A'},
  ]);

  Map<String, dynamic> responses() => {
    '/invoices/1': _invoice(),
    '/invoices': successEnvelope(<Object?>[]),
    '/inventory/warehouses': successEnvelope([
      {'id': 1, 'warehouse_code': 'WH-1', 'warehouse_name': 'Main'},
    ]),
    '/inventory/locations': locations,
  };

  /// Captures every POST the dialog sends and fails it, so the assertions
  /// read the exact request body without a result shape to satisfy.
  Future<(List<RequestOptions>, List<RequestOptions>)> pumpDialog(
    WidgetTester tester, {
    Map<String, dynamic>? invoice,
  }) async {
    final posts = <RequestOptions>[];
    final gets = <RequestOptions>[];
    final dio = createFakeDio({
      ...responses(),
      '/invoices/1': ?invoice,
    });
    dio.interceptors.insert(
      0,
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.method == 'POST') {
            posts.add(options);
            handler.reject(DioException(
              requestOptions: options,
              type: DioExceptionType.receiveTimeout,
            ));
          } else {
            gets.add(options);
            handler.next(options);
          }
        },
      ),
    );
    await tester.pumpWidget(
      buildTestable(
        const Scaffold(body: InvoiceReturnDialog(invoiceId: 1)),
        dio: dio,
      ),
    );
    await tester.pumpAndSettle();
    return (posts, gets);
  }

  /// Pick the restock warehouse through its searchable select.
  Future<void> chooseWarehouse(WidgetTester tester) async {
    await tester.tap(find.byType(SearchableSelect<int>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Main').last);
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    final submitButton = find
        .byWidgetPredicate((widget) => widget is FilledButton)
        .last;
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pumpAndSettle();
  }

  testWidgets('the chosen bin reaches the request for the line that needs it',
      (tester) async {
    final (posts, gets) = await pumpDialog(tester);
    await chooseWarehouse(tester);

    // The bins were asked for by the chosen warehouse.
    final binRequest = gets.lastWhere(
      (r) => r.path == '/inventory/locations',
    );
    expect(binRequest.queryParameters['warehouse_id'], '1');

    // Only the line with no recorded draw offers a bin, so there are
    // exactly two selects: the warehouse and that line's bin.
    expect(find.byType(SearchableSelect<int>), findsNWidgets(2));
    await tester.tap(find.byType(SearchableSelect<int>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('RACK-A — Rack A').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '2');
    await tester.enterText(find.byType(TextField).at(1), '3');
    await tester.pumpAndSettle();
    await submit(tester);

    expect(posts, hasLength(1));
    final items = posts.single.data['items'] as List<dynamic>;
    expect(items, hasLength(2));
    expect(items[0], {
      'invoice_item_id': 11,
      'return_quantity': 2.0,
      'location_id': 11,
    });
    // The recorded-draw line replays its own bins: no choice is sent.
    expect(items[1], {
      'invoice_item_id': 12,
      'return_quantity': 3.0,
    });
  });

  testWidgets('a required line without a chosen bin blocks the submit',
      (tester) async {
    final (posts, _) = await pumpDialog(tester);
    await chooseWarehouse(tester);

    await tester.enterText(find.byType(TextField).at(0), '2');
    await tester.pumpAndSettle();
    await submit(tester);

    expect(posts, isEmpty);
    // The bin picker is on screen and still shows its hint.
    expect(find.byType(SearchableSelect<int>), findsNWidgets(2));
    expect(find.text('Select the bin to restock into'), findsOneWidget);
    expect(
      find.text(
        'Choose the restock bin for every returned line that has no '
        'recorded bin',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a legacy line sold from no batch needs no bin choice',
      (tester) async {
    final (posts, _) = await pumpDialog(
      tester,
      invoice: _invoice(
        firstLineNeedsBin: false,
        secondLineDraws: const [],
      ),
    );
    await chooseWarehouse(tester);

    // Two returnable lines and neither needs a bin, so only the
    // warehouse select exists.
    expect(find.byType(SearchableSelect<int>), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), '2');
    await tester.pumpAndSettle();
    await submit(tester);

    expect(posts, hasLength(1));
    final items = posts.single.data['items'] as List<dynamic>;
    expect(items, hasLength(1));
    expect(items.single, {'invoice_item_id': 11, 'return_quantity': 2.0});
  });
}
