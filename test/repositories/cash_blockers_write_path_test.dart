// ACCT-013 / PRET-002 — the guard list must survive the WRITE path.
//
// The server answers a refused void with HTTP 409 and a normal
// `{success: false, error: {code, message}, details: [...]}` body. Dio does
// not throw on a 409, so the response travels through `_envelopeData`, which
// builds an `ApiResponseException`. That class carried `code` and `blockedBy`
// but silently dropped `details`, so the dialog always got an empty
// `cashBlockers` list and could only show the message.
//
// These tests pin the fix: the envelope path keeps the same `cashBlockers`
// the direct `ApiError.fromResponse` path already parsed, and `blockedBy`
// keeps its own separate shape.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:minierp_app/data/repositories/api_result.dart';
import 'package:minierp_app/data/repositories/repository_client.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.status, this.body);

  final int status;
  final Object body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

void main() {
  Future<ApiResult<void>> postVoid(Object body, {int status = 409}) async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.httpClientAdapter = _Adapter(status, body);
    return RepositoryClient(dio).post(
      '/supplier-refunds/5/void',
      body: {},
      parse: (data) {},
    );
  }

  test('a refused void keeps the cash blockers through the write path',
      () async {
    final result = await postVoid({
      'success': false,
      'error': {
        'code': 'CASH_TIMELINE_BLOCKED',
        'message':
            'Insufficient funds in Cash on 2026-08-05: balance would be -50.00.',
      },
      'details': [
        {'id': 7, 'date': '2026-08-05', 'amount': 120.5, 'type': 'EXPENSE'},
        {'id': 9, 'date': '2026-08-05', 'amount': 30.0, 'type': 'SUPPLIER_REFUND'},
      ],
    });

    expect(result, isA<ApiFailure<void>>());
    final error = (result as ApiFailure<void>).error;
    expect(error.statusCode, 409);
    // A readable message, not "Request failed".
    expect(error.message, contains('Insufficient funds in Cash'));
    // The whole point: the dialog can now list what to reverse first.
    expect(error.cashBlockers, hasLength(2));
    expect(error.cashBlockers.first.id, 7);
    expect(error.cashBlockers.first.type, 'EXPENSE');
    expect(error.cashBlockers.last.type, 'SUPPLIER_REFUND');
  });

  test('a 403 write-off keeps a readable server message', () async {
    final result = await postVoid(
      {
        'success': false,
        'error': {
          'code': 'FORBIDDEN',
          'message':
              'Write-offs above Rs 1000 require owner (admin) approval',
        },
      },
      status: 403,
    );

    final error = (result as ApiFailure<void>).error;
    expect(error.statusCode, 403);
    expect(error.message, 'Write-offs above Rs 1000 require owner (admin) approval');
    expect(error.cashBlockers, isEmpty);
  });

  test('a refused void with no details yields an empty list, not a throw',
      () async {
    final result = await postVoid({
      'success': false,
      'error': {
        'code': 'CASH_TIMELINE_BLOCKED',
        'message': 'Insufficient funds in Cash on 2026-08-05.',
      },
    });

    final error = (result as ApiFailure<void>).error;
    expect(error.cashBlockers, isEmpty);
    expect(error.message, contains('Insufficient funds'));
  });

  test('blockedBy keeps its own shape on the write path', () async {
    final result = await postVoid({
      'success': false,
      'error': {
        'code': 'UNAPPLIED_ALREADY_APPLIED',
        'message': 'Receipt used',
        'blockedBy': [
          {'sourceId': 1, 'consumed': 40, 'invoices': [9]},
        ],
      },
    });

    final error = (result as ApiFailure<void>).error;
    expect(error.blockedBy.single.sourceId, 1);
    expect(error.blockedBy.single.invoices, [9]);
    expect(error.cashBlockers, isEmpty);
  });
}
