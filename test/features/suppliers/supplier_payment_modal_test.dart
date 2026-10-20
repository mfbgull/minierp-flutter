import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/data/models/purchase.dart' show Purchase;
import 'package:minierp_app/data/models/supplier.dart' show Supplier;
import 'package:minierp_app/features/suppliers/supplier_payment_modal.dart';

import '../../test_helpers.dart';

void main() {
  final supplier = Supplier.fromJson({
    'id': 1,
    'supplier_code': 'SUP001',
    'supplier_name': 'Alpha Traders',
  });

  final po = {
    'id': 1,
    'po_no': 'PO-900',
    'po_date': '2026-09-01',
    'supplier_id': 1,
    'supplier_name': 'Alpha Traders',
    'total_amount': 600.0,
    'paid_amount': 0.0,
    'balance_amount': 600.0,
    'status': 'Open',
  };

  final purchase = {
    'id': 5,
    'purchase_no': 'PUR-900',
    'purchase_date': '2026-09-02',
    'supplier_id': 1,
    'supplier_name': 'Alpha Traders',
    'total_cost': 400.0,
    'paid_amount': 0.0,
    'balance_amount': 400.0,
  };

  Map<String, dynamic>? postedBody;
  String? rejectionMessage;

  Dio buildDio({
    List<Map<String, dynamic>> pos = const [],
    List<Map<String, dynamic>> purchases = const [],
  }) {
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost:3011/api'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          Map<String, dynamic> paged(List<Map<String, dynamic>> rows) => {
                'success': true,
                'data': rows,
                'pagination': {
                  'totalItems': rows.length,
                  'currentPage': 1,
                  'totalPages': 1,
                  'hasNext': false,
                  'hasPrev': false,
                },
              };

          if (options.path == '/purchase-orders' &&
              options.method == 'GET') {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: paged(pos),
              ),
            );
            return;
          }
          if (options.path == '/purchases' && options.method == 'GET') {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: paged(purchases),
              ),
            );
            return;
          }
          if (options.path == '/payments' && options.method == 'POST') {
            final body = options.data as Map<String, dynamic>;
            postedBody = body;
            if (rejectionMessage != null) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 400,
                  data: {'success': false, 'error': rejectionMessage},
                ),
              );
              return;
            }
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 201,
                data: {
                  'success': true,
                  'data': {
                    'id': 77,
                    'payment_no': 'PAY-77',
                    'supplier_id': body['supplier_id'],
                    'payment_date': body['payment_date'],
                    'amount': body['amount'],
                    'payment_method': body['payment_method'],
                  },
                },
              ),
            );
            return;
          }
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 404,
              data: {'success': false, 'error': 'Not found'},
            ),
          );
        },
      ),
    );
    return dio;
  }

  setUp(() {
    postedBody = null;
    rejectionMessage = null;
  });

  Future<void> openModal(
    WidgetTester tester, {
    List<Map<String, dynamic>> pos = const [],
    List<Map<String, dynamic>> purchases = const [],
    Purchase? initialPurchase,
  }) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      buildTestable(
        Scaffold(
          body: SupplierPaymentModal(
            supplier: supplier,
            initialPurchase: initialPurchase,
          ),
        ),
        dio: buildDio(pos: pos, purchases: purchases),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder addButtonIn(String poNo) => find.descendant(
        of: find
            .ancestor(of: find.text(poNo), matching: find.byType(Row))
            .first,
        matching: find.text('+ Add'),
      );

  Future<void> enterTotal(WidgetTester tester, String value) async {
    await tester.enterText(find.byType(TextFormField).at(1), value);
    await tester.pump();
  }

  Finder allocationField(String text) => find.byWidgetPredicate(
        (w) => w is TextField && w.controller?.text == text,
      );

  Future<void> submit(WidgetTester tester) async {
    final submitBtn = find.widgetWithText(FilledButton, 'Record Payment').last;
    expect(submitBtn, findsOneWidget);
    final scrollable = find
        .descendant(of: find.byType(Form), matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(submitBtn, 200, scrollable: scrollable);
    await tester.ensureVisible(submitBtn);
    await tester.pumpAndSettle();
    await tester.tap(submitBtn);
    await tester.pumpAndSettle();
  }

  testWidgets('one PO and one direct purchase post exact allocation arrays', (
    tester,
  ) async {
    await openModal(tester, pos: [po], purchases: [purchase]);
    expect(find.text('PO-900'), findsOneWidget);
    expect(find.text('PUR-900'), findsOneWidget);

    await enterTotal(tester, '1000');
    await tester.tap(addButtonIn('PO-900'));
    await tester.pumpAndSettle();
    await tester.tap(addButtonIn('PUR-900'));
    await tester.pumpAndSettle();

    // Both allocations are seeded at min(balance, entered total).
    expect(find.text('600.00'), findsWidgets);
    expect(find.text('400.00'), findsWidgets);

    await submit(tester);

    final body = postedBody!;
    expect(body['supplier_id'], 1);
    expect(body['amount'], 1000.0);
    expect(body['po_allocations'], [
      {'po_id': 1, 'amount': 600.0},
    ]);
    expect(body['purchase_allocations'], [
      {'purchase_id': 5, 'amount': 400.0},
    ]);
  });

  testWidgets('an allocated line can be removed and added again', (
    tester,
  ) async {
    await openModal(tester, pos: [po]);
    await enterTotal(tester, '1000');

    await tester.tap(addButtonIn('PO-900'));
    await tester.pumpAndSettle();
    expect(allocationField('600.00'), findsOneWidget);

    // Remove the allocation row (the X action on the allocation line).
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();
    expect(allocationField('600.00'), findsNothing);

    // Re-add it.
    await tester.tap(addButtonIn('PO-900'));
    await tester.pumpAndSettle();
    expect(allocationField('600.00'), findsOneWidget);
  });

  testWidgets('auto allocate fills the remaining amount from the PO balance', (
    tester,
  ) async {
    await openModal(tester, pos: [po]);
    await enterTotal(tester, '1000');

    await tester.tap(find.text('Auto Allocate').first);
    await tester.pumpAndSettle();
    expect(allocationField('600.00'), findsOneWidget);
  });

  testWidgets('a seeded purchase survives an empty open-purchases response', (
    tester,
  ) async {
    await openModal(
      tester,
      purchases: const [],
      initialPurchase: Purchase.fromJson(purchase),
    );
    await tester.pumpAndSettle();

    // The seeded allocation keeps the section populated, so the
    // "no open purchases" empty state must not replace it.
    expect(find.text('No open purchases'), findsNothing);
    expect(find.text('PUR-900'), findsWidgets);
  });

  testWidgets('the allocation row exposes a localized accessible name', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await openModal(tester, pos: [po]);
    await enterTotal(tester, '600');
    await tester.tap(addButtonIn('PO-900'));
    await tester.pumpAndSettle();

    // The remove action is an icon button, so its tooltip is the
    // accessible name it exposes and must be localized.
    final remove = tester.getSemantics(
      find.widgetWithIcon(IconButton, Icons.close),
    );
    expect(remove.tooltip, 'Remove');
    semantics.dispose();
  });

  testWidgets('a rejected payment surfaces the server message', (
    tester,
  ) async {
    rejectionMessage = 'Payment rejected by the server';
    await openModal(tester, pos: [po]);
    // The modal only submits when the amount matches the allocated total.
    await enterTotal(tester, '600');
    await tester.tap(addButtonIn('PO-900'));
    await tester.pumpAndSettle();

    await submit(tester);

    expect(postedBody, isNotNull);
    expect(find.text('Payment rejected by the server'), findsOneWidget);
  });
}
