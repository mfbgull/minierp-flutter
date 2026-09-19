// Regression test for the invoice-return submission payload.
//
// `InvoiceRepository.processReturn` once built its POST body from every
// field EXCEPT `items` — the one the server requires (`POST /invoices/:id/
// return` answers 400 "Invalid request: items must be a non-empty array"
// when `body.items` is missing). The dialog therefore always failed at
// submit time. This test pins the serialized body so that omission cannot
// return.
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:minierp_app/data/repositories/api_result.dart';
import 'package:minierp_app/data/repositories/invoice_repository.dart';
import 'package:minierp_app/data/repositories/repository_client.dart';

Map<String, dynamic> capturedBody = {};
String capturedPath = '';

Dio _capturingDio() {
  final dio = Dio(BaseOptions(baseUrl: 'http://localhost:3011/api'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        capturedPath = options.path;
        capturedBody = options.data is Map
            ? Map<String, dynamic>.from(options.data as Map)
            : (options.data is String
                ? jsonDecode(options.data as String) as Map<String, dynamic>
                : <String, dynamic>{});
        handler.resolve(
          Response<dynamic>(
            requestOptions: options,
            statusCode: 200,
            data: {
              'success': true,
              'data': {
                'returnId': 7,
                'returnNo': 'RET-0001',
                'status': 'Settled',
                'returnAmount': 1200,
                'feeAmount': 120,
                'netAmount': 1080,
                'settledAmount': 1080,
              },
            },
          ),
        );
      },
    ),
  );
  return dio;
}

void main() {
  late InvoiceRepository repo;

  setUp(() {
    repo = InvoiceRepository(RepositoryClient(_capturingDio()));
  });

  test('processReturn serializes the return lines into the request body',
      () async {
    final result = await repo.processReturn(
      42,
      items: [
        {'invoice_item_id': 101, 'return_quantity': 2},
        {'invoice_item_id': 102, 'return_quantity': 1},
      ],
      feeType: 'percentage',
      feeValue: 10,
      returnDate: '2026-09-18',
      reason: 'Damaged',
      warehouseId: 3,
      settlements: [
        {'type': 'refund', 'amount': 1080, 'method': 'Cash'},
      ],
    );

    expect(result, isA<ApiSuccess>());
    expect(capturedPath, '/invoices/42/return');
    // The regression: `items` must reach the server (it was the one field
    // the repository forgot to serialize).
    expect(capturedBody['items'], [
      {'invoice_item_id': 101, 'return_quantity': 2},
      {'invoice_item_id': 102, 'return_quantity': 1},
    ]);
    expect(capturedBody['fee_type'], 'percentage');
    expect(capturedBody['fee_value'], 10);
    expect(capturedBody['return_date'], '2026-09-18');
    expect(capturedBody['reason'], 'Damaged');
    expect(capturedBody['warehouse_id'], 3);
    expect(capturedBody['settlements'], [
      {'type': 'refund', 'amount': 1080, 'method': 'Cash'},
    ]);
  });

  test('processReturn omits the optional fields it was not given',
      () async {
    await repo.processReturn(
      42,
      items: [
        {'invoice_item_id': 101, 'return_quantity': 1},
      ],
    );
    expect(capturedBody['items'], [
      {'invoice_item_id': 101, 'return_quantity': 1},
    ]);
    expect(capturedBody.containsKey('reason'), false);
    expect(capturedBody.containsKey('settlements'), false);
  });

  test('settleReturn posts its allocations to the return endpoint',
      () async {
    await repo.settleReturn(
      7,
      settlements: [
        {'type': 'credit', 'amount': 540},
      ],
    );
    expect(capturedPath, '/invoice-returns/7/settle');
    expect(capturedBody['settlements'], [
      {'type': 'credit', 'amount': 540},
    ]);
  });
}
