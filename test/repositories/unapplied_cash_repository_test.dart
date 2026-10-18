import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/data/models/payment.dart';
import 'package:minierp_app/data/models/unapplied_cash.dart';
import 'package:minierp_app/data/repositories/unapplied_cash_repository.dart';
import 'package:minierp_app/core/cache/cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:minierp_app/data/repositories/api_result.dart';
import 'package:minierp_app/data/repositories/repository_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('payment metadata survives parsing and serialization', () {
    final payment = Payment.fromJson({
      'id': 12,
      'payment_kind': 'UNAPPLIED_RECEIPT',
      'voided_at': '2026-10-03',
    });
    expect(payment.toJson()['payment_kind'], 'UNAPPLIED_RECEIPT');
    expect(payment.toJson()['voided_at'], '2026-10-03');
    expect(Payment.fromJson({}).toJson()['payment_kind'], 'RECEIPT');
  });

  test(
    'structured domain failures remain usable without exposing raw bodies',
    () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            handler.resolve(
              Response<dynamic>(
                requestOptions: request,
                statusCode: 200,
                data: jsonDecode('''
        {"success":false,"error":{"code":"UNAPPLIED_ALREADY_APPLIED","message":"Receipt used",
        "blockedBy":[{"sourceId":1,"consumed":40,"invoices":[9]}]}}
      '''),
              ),
            );
          },
        ),
      );
      final result = await RepositoryClient(
        dio,
      ).get<Object>('/test', parse: (value) => value!);
      expect(result, isA<ApiFailure<Object>>());
      final failure = result as ApiFailure<Object>;
      expect(failure.error.message, 'Receipt used');
      expect(failure.error.toString(), contains('UNAPPLIED_ALREADY_APPLIED'));
      expect(failure.error.code, 'UNAPPLIED_ALREADY_APPLIED');
      expect(failure.error.blockedBy.single.sourceId, 1);
      expect(failure.error.blockedBy.single.invoices, [9]);
    },
  );

  test(
    'all cash writes send exact bodies and keys and expire dependent caches after success',
    () async {
      final requests = <RequestOptions>[];
      final cache = CacheManager();
      final dio = Dio(BaseOptions(baseUrl: 'http://test/api'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'success': true,
                  'data': {
                    'paymentId': 12,
                    'applicationId': null,
                    'amount': 0.30,
                  },
                },
              ),
            );
          },
        ),
      );
      final repository = UnappliedCashRepository(
        RepositoryClient(dio, cache: cache),
      );
      final commands = [
        CashRequest.receive(customerId: 3, amountMinor: 30, date: '2026-10-01'),
        CashRequest.apply(
          customerId: 3,
          date: '2026-10-02',
          allocations: [CashAllocation(invoiceId: 9, amountMinor: 30)],
        ),
        CashRequest.refund(
          customerId: 3,
          amountMinor: 10,
          date: '2026-10-03',
          method: 'Bank',
        ),
        CashRequest.reverse(
          customerId: 3,
          paymentId: 12,
          reason: ' Duplicate ',
        ),
      ];
      for (final command in commands) {
        for (final path in [
          '/customers/3',
          '/payments?type=customer',
          '/invoices?customerId=3',
          '/dashboard/summary',
        ]) {
          await cache.put(path, '{}');
        }
        expect(
          (await repository.execute(
            command,
            'exact-key-123',
          )).requireData.paymentId,
          12,
        );
        expect(requests.last.path, command.path);
        expect(requests.last.method, 'POST');
        expect(requests.last.headers['Idempotency-Key'], 'exact-key-123');
        expect(requests.last.data, command.body);
        expect(await cache.get('/customers/3'), isNull);
        expect(await cache.get('/payments?type=customer'), isNull);
        expect(await cache.get('/invoices?customerId=3'), isNull);
        expect(await cache.get('/dashboard/summary'), isNull);
      }
      expect(commands[0].body, {
        'amount': 0.30,
        'operation_date': '2026-10-01',
        'payment_method': 'Cash',
      });
      expect(commands[1].body, {
        'customer_id': 3,
        'operation_date': '2026-10-02',
        'allocations': [
          {'invoice_id': 9, 'amount': 0.30},
        ],
      });
      expect(commands[2].body, {
        'customer_id': 3,
        'amount': 0.10,
        'operation_date': '2026-10-03',
        'payment_method': 'Bank',
      });
      expect(commands[3].body, {'reason': 'Duplicate'});
    },
  );

  test(
    'cash capabilities and capacity never fall back to offline cached data',
    () async {
      final cache = CacheManager();
      const capabilityPath = '/unapplied-cash/capabilities';
      await cache.put(
        capabilityPath,
        jsonEncode({
          'success': true,
          'data': {'receive': 'durable-v1'},
        }),
      );
      await cache.put('/customers/3/unapplied-cash?limit=20&page=1', '{}');
      final dio = Dio(BaseOptions(baseUrl: 'http://test/api'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
              ),
            );
          },
        ),
      );
      final client = RepositoryClient(dio, cache: cache);
      final repository = UnappliedCashRepository(client);
      expect(
        await repository.capabilities(),
        isA<ApiFailure<CashCapabilities>>(),
      );
      expect(await repository.summary(3), isA<ApiFailure<CashSummary>>());
      expect(client.servingCached.value, isFalse);
    },
  );

  test('currency and immutable allocations reject invalid input', () {
    expect(parseCashMinor('0.10') + parseCashMinor('0.20'), 30);
    for (final value in [
      '0',
      '-1',
      'NaN',
      '1.001',
      '1e2',
      '90071992547410.00',
    ]) {
      expect(() => parseCashMinor(value), throwsFormatException);
    }
    expect(
      () => CashRequest.receive(
        customerId: 1,
        amountMinor: 1,
        date: '2026-02-30',
      ),
      throwsFormatException,
    );
    expect(
      () => CashRequest.receive(
        customerId: 1,
        amountMinor: 1,
        date: '2026-10-01',
        method: 'Credit',
      ),
      throwsFormatException,
    );
    final line = CashAllocation(invoiceId: 9, amountMinor: 10);
    expect(
      () => CashRequest.apply(
        customerId: 1,
        date: '2026-10-01',
        allocations: [line, line],
      ),
      throwsFormatException,
    );
    final request = CashRequest.apply(
      customerId: 1,
      date: '2026-10-01',
      allocations: [line],
    );
    expect(() => request.body['allocations'] = [], throwsUnsupportedError);
    expect(
      CashRequest.fromJson(
        jsonDecode(jsonEncode(request.toJson())),
      ).fingerprint,
      request.fingerprint,
    );
  });

  test(
    'HTTP failures preserve typed domain details and tolerate legacy string errors',
    () async {
      final dio = Dio();
      Object error = {
        'code': 'UNAPPLIED_ALREADY_APPLIED',
        'message': 'Used',
        'blockedBy': [
          {
            'sourceId': 2,
            'consumed': 40,
            'invoices': [5],
          },
        ],
      };
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.badResponse,
                response: Response<dynamic>(
                  requestOptions: options,
                  statusCode: 409,
                  data: {'success': false, 'error': error},
                ),
              ),
            );
          },
        ),
      );
      final repository = UnappliedCashRepository(RepositoryClient(dio));
      final result =
          await repository.capabilities() as ApiFailure<CashCapabilities>;
      expect(result.error.code, 'UNAPPLIED_ALREADY_APPLIED');
      expect(result.error.blockedBy.single.consumed, 40);
      error = 'Legacy failure';
      expect(
        (await repository.capabilities() as ApiFailure<CashCapabilities>)
            .error
            .message,
        'Legacy failure',
      );
    },
  );

  test(
    'online reads use exact supported queries without adding CORS-blocked headers',
    () async {
      final dio = Dio();
      final seen = <RequestOptions>[];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            seen.add(options);
            expect(options.headers.containsKey('Cache-Control'), isFalse);
            final summary = options.path.endsWith('/unapplied-cash');
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'success': true,
                  'data': summary
                      ? {
                          'customer_id': 3,
                          'operation_date': '2026-10-02',
                          'remaining_amount': 0.30,
                          'available_amount': 0.20,
                          'refundable_amount': 0.20,
                          'receipts': [],
                        }
                      : [
                          {
                            'application_id': 2,
                            'operation': 'APPLY',
                            'operation_date': '2026-10-02',
                            'total_amount': 0.10,
                            'payment_id': null,
                            'lines': [
                              {
                                'source_id': 1,
                                'invoice_id': 9,
                                'invoice_no': 'INV9',
                                'payment_id': 12,
                                'amount': 0.10,
                                'kind': 'APPLY',
                                'voided_at': null,
                              },
                            ],
                          },
                        ],
                  'pagination': {
                    'currentPage': 2,
                    'totalPages': 3,
                    'totalItems': 5,
                  },
                },
              ),
            );
          },
        ),
      );
      final repository = UnappliedCashRepository(RepositoryClient(dio));
      final summary = (await repository.summary(
        3,
        date: '2026-10-02',
        page: 2,
        limit: 1,
      )).requireData;
      expect(summary.remainingMinor, 30);
      expect(summary.availableMinor, 20);
      expect(seen.last.queryParameters, {
        'page': 2,
        'limit': 1,
        'operation_date': '2026-10-02',
      });
      final activity = (await repository.activity(
        3,
        page: 2,
        limit: 1,
        fromDate: '2026-10-01',
        toDate: '2026-10-02',
      )).requireData;
      expect(activity.items.single.paymentId, isNull);
      expect(activity.items.single.lines.single.invoiceId, 9);
      expect(activity.items.single.amountMinor, 10);
      expect(seen.last.queryParameters, {
        'page': 2,
        'limit': 1,
        'fromDate': '2026-10-01',
        'toDate': '2026-10-02',
      });
      expect(
        CashResult({
          'applicationId': 2,
          'paymentId': null,
          'amount': 0.10,
        }).amountMinor,
        10,
      );
    },
  );
}
