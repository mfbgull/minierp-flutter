import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/data/models/item.dart';
import 'package:minierp_app/data/models/supplier.dart';
import 'package:minierp_app/data/models/warehouse.dart';
import 'package:minierp_app/features/inventory/inventory_providers.dart';
import 'package:minierp_app/features/purchase_orders/purchase_order_providers.dart';
import 'package:minierp_app/features/purchases/purchase_form_dialog.dart';
import 'package:minierp_app/widgets/searchable_select.dart';

import '../test_helpers.dart';

void main() {
  testWidgets(
    'stock purchase submits recoverable tax and includes it in payment',
    (tester) async {
      final requests = <RequestOptions>[];
      final dio = createFakeDio({});
      dio.interceptors.insert(
        0,
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 201,
                data: options.path == '/purchases'
                    ? [
                        {
                          'id': 1,
                          'total_cost': 100,
                          'input_tax_amount': 15,
                          'total_payable': 115,
                        },
                      ]
                    : {
                        'success': true,
                        'data': {'id': 1},
                      },
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
                onPressed: () => showPurchaseFormDialog(context),
                child: const Text('Open purchase'),
              ),
            ),
          ),
          dio: dio,
          overrides: [
            allItemsProvider.overrideWith(
              (ref) async => [
                Item.fromJson({
                  'id': 1,
                  'item_code': 'ITEM',
                  'item_name': 'Stock',
                }),
              ],
            ),
            warehousesProvider.overrideWith(
              (ref) async => [
                Warehouse.fromJson({
                  'id': 1,
                  'warehouse_code': 'WH',
                  'warehouse_name': 'Warehouse',
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
      await tester.tap(find.text('Open purchase'));
      await tester.pumpAndSettle();
      final tax = find.byKey(const ValueKey('purchase-input-tax-0'));
      await tester.ensureVisible(tax);
      expect(tax, findsOneWidget);
      for (final selection in [
        (0, 'SUP — Vendor'),
        (1, 'Warehouse'),
        (2, 'ITEM — Stock'),
      ]) {
        final picker = find.byType(SearchableSelect<int>).at(selection.$1);
        await tester.ensureVisible(picker);
        await tester.tap(picker);
        await tester.pumpAndSettle();
        await tester.tap(find.text(selection.$2).last);
        await tester.pumpAndSettle();
      }
      final fields = find.byType(TextFormField);
      await tester.ensureVisible(fields.at(2));
      await tester.enterText(fields.at(2), '10');
      await tester.enterText(fields.at(3), '10');
      await tester.enterText(tax, '15');
      final submit = find.widgetWithText(FilledButton, 'Save');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      final purchase = requests.singleWhere((r) => r.path == '/purchases');
      expect(purchase.data['items'].single['input_tax_amount'], 15);
      final payment = requests.singleWhere((r) => r.path == '/payments');
      expect(payment.data['amount'], 115);
      expect(payment.data['purchase_allocations'], [
        {'purchase_id': 1, 'amount': 115},
      ]);
      expect(payment.headers['Idempotency-Key'], isA<String>());
      expect(tester.takeException(), isNull);
    },
  );
}
