import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/features/suppliers/supplier_bill_dialog.dart';

import '../test_helpers.dart';

void main() {
  testWidgets('supplier bill preserves amounts and its key across retries', (
    tester,
  ) async {
    final requests = <RequestOptions>[];
    final dio = createFakeDio({});
    dio.interceptors.insert(
      0,
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.receiveTimeout,
            ),
          );
        },
      ),
    );
    await tester.pumpWidget(
      buildTestable(
        const Scaffold(body: SupplierBillDialog.create(supplierId: 1)),
        dio: dio,
      ),
    );
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'VENDOR-1');
    await tester.enterText(fields.at(1), 'Services');
    await tester.enterText(fields.at(2), '100');
    await tester.enterText(fields.at(3), '15');
    final submit = find.byType(FilledButton);
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt == 2) await tester.enterText(fields.at(2), '150');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
    }
    expect(requests, hasLength(3));
    for (final request in requests) {
      expect(request.path, '/supplier-bills');
      expect(request.data['supplier_id'], 1);
      expect(request.data['bill_no'], 'VENDOR-1');
      expect(request.data['input_tax_amount'], 15);
    }
    expect(requests.first.data['net_amount'], 100);
    expect(requests.last.data['net_amount'], 150);
    final keys = requests.map((r) => r.headers['Idempotency-Key']).toList();
    expect(keys.first, isA<String>());
    expect(keys[0], keys[1]);
    expect(keys[2], isNot(keys[1]));
  });
}
