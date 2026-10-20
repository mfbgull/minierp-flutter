import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/data/models/item.dart';
import 'package:minierp_app/data/models/supplier.dart';
import 'package:minierp_app/data/models/purchase_order.dart';
import 'package:minierp_app/features/purchase_orders/purchase_order_form_dialog.dart';
import 'package:minierp_app/features/purchase_orders/purchase_order_providers.dart';

import '../../test_helpers.dart';

void main() {
  testWidgets('editing draft PO tax changes its saved line and gross total', (
    tester,
  ) async {
    final requests = <RequestOptions>[];
    final lineJson = {
      'id': 2,
      'item_id': 1,
      'quantity': 10,
      'unit_price': 10,
      'input_tax_amount': 10,
    };
    final detailJson = <String, dynamic>{
      'id': 1,
      'supplier_id': 1,
      'po_no': 'PO-1',
      'po_date': '2026-09-01',
      'status': 'Draft',
      'total_amount': 110,
      'items': [lineJson],
    };
    final detail = PurchaseOrderDetail.fromJson(detailJson);
    final dio = createFakeDio({});
    dio.interceptors.insert(
      0,
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: options.path.endsWith('/items/2') ? lineJson : detailJson,
            ),
          );
        },
      ),
    );
    await tester.pumpWidget(
      buildTestable(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showPurchaseOrderFormDialog(context, detail: detail),
              child: const Text('Open PO'),
            ),
          ),
        ),
        dio: dio,
        overrides: [
          poItemsProvider.overrideWith(
            (ref) async => [
              Item.fromJson({
                'id': 1,
                'item_code': 'ITEM',
                'item_name': 'Stock',
              }),
            ],
          ),
          poSupplierOptionsProvider.overrideWith(
            (ref) async => [
              Supplier.fromJson({
                'id': 1,
                'supplier_code': 'SUP',
                'supplier_name': 'Vendor',
              }),
            ],
          ),
        ],
      ),
    );
    await tester.tap(find.text('Open PO'));
    await tester.pumpAndSettle();
    final tax = find.byKey(const ValueKey('po-input-tax-0'));
    expect(tax, findsOneWidget);
    expect(tester.widget<TextFormField>(tax).controller!.text, '10');
    await tester.ensureVisible(tax);
    await tester.enterText(tax, '15');
    final submit = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    final saved = requests.singleWhere(
      (r) => r.method == 'PUT' && r.path.endsWith('/items/2'),
    );
    expect(saved.data['input_tax_amount'], 15);
    expect(saved.data['quantity'], 10);
    expect(saved.data['unit_price'], 10);
    expect(tester.takeException(), isNull);
  });
}
