import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:minierp_app/data/models/unapplied_cash.dart';
import 'package:minierp_app/data/repositories/api_result.dart';
import 'package:minierp_app/data/repositories/repository_client.dart';
import 'package:minierp_app/data/repositories/unapplied_cash_repository.dart';
import 'package:minierp_app/features/customers/unapplied_cash_operation.dart';

class UnavailableCashStore extends CashPendingStore {
  @override
  Future<void> save(CashScope scope, PendingCashOperation pending) async {
    throw StateError('Storage unavailable');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const scope = (server: 'http://test/api', userId: 7);
  late CashPendingStore store;
  late UnappliedCashRepository repository;
  late Dio dio;
  late bool timeout;
  late bool capable;
  late bool current;
  late bool alreadyVoided;
  late bool reversible;
  late int writes;
  late int effects;
  late List<int> refreshed;
  late List<String> keys;
  late List<Object?> bodies;
  final seen = <String>{};

  CashOperationController controller() => CashOperationController(
    repository: repository,
    store: store,
    scope: scope,
    isCurrentScope: () => current,
    onSuccess: refreshed.add,
  );
  CashRequest receive() => CashRequest.receive(
    customerId: 3,
    amountMinor: 50000,
    date: '2026-10-01',
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = CashPendingStore();
    timeout = false;
    capable = true;
    current = true;
    alreadyVoided = false;
    reversible = true;
    writes = 0;
    effects = 0;
    refreshed = [];
    keys = [];
    bodies = [];
    seen.clear();
    dio = Dio(BaseOptions(baseUrl: scope.server));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          Object? data;
          if (options.method == 'POST') {
            writes++;
            final key = options.headers['Idempotency-Key'] as String;
            keys.add(key);
            bodies.add(jsonDecode(jsonEncode(options.data)));
            expect((await store.load(scope))?.key, key);
            if (seen.add(key)) effects++;
            if (timeout) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.receiveTimeout,
                ),
              );
              return;
            }
            data = {'paymentId': 12, 'applicationId': null, 'amount': 500};
          } else if (options.path.endsWith('/capabilities')) {
            data = capable
                ? {
                    'receive': 'durable-v1',
                    'apply': 'permanent-application-v1',
                    'refund': 'permanent-application-v1',
                    'reverse': 'guarded-status-v1',
                  }
                : {};
          } else if (options.path == '/payments/12') {
            data = {
              'id': 12,
              'customer_id': 3,
              'payment_kind': 'UNAPPLIED_RECEIPT',
              'voided_at': alreadyVoided ? '2026-10-02' : null,
            };
          } else {
            data = {
              'customer_id': 3,
              'operation_date': '2026-10-01',
              'remaining_amount': 500,
              'available_amount': 500,
              'refundable_amount': 500,
              'receipts': [
                {
                  'source_id': 1,
                  'payment_id': 12,
                  'payment_no': 'P12',
                  'payment_date': '2026-10-01',
                  'payment_method': 'Cash',
                  'original_amount': 500,
                  'applied_amount': 0,
                  'refunded_amount': 0,
                  'remaining_amount': 500,
                  'voided_at': null,
                  'can_reverse': reversible,
                },
              ],
            };
          }
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'success': true,
                'data': data,
                'pagination': {
                  'currentPage': 1,
                  'totalPages': 1,
                  'totalItems': 1,
                },
              },
            ),
          );
        },
      ),
    );
    repository = UnappliedCashRepository(RepositoryClient(dio));
  });

  test(
    'lost committed response survives restart and retries old immutable key once',
    () async {
      final first = controller();
      timeout = true;
      expect(await first.start(receive()), isA<ApiFailure<CashResult>>());
      expect(writes, 1);
      expect(effects, 1);
      final pending = await store.load(scope);
      expect(pending?.replayPolicy, 'durable-v1');
      first.dispose();
      final restarted = controller();
      await restarted.restore();
      expect(writes, 1);
      timeout = false;
      expect(await restarted.resume(), isA<ApiSuccess<CashResult>>());
      expect(keys.toSet().length, 1);
      expect(bodies.first, bodies.last);
      expect(effects, 1);
      expect(await store.load(scope), isNull);
      expect(refreshed, [3]);
      restarted.dispose();
    },
  );

  test(
    'old requests require their original policy, never only a fresh capability',
    () async {
      for (final policy in [null, 'central-30-days', 'durable-v1']) {
        await store.save(
          scope,
          PendingCashOperation(
            request: receive(),
            key: 'old-receive-key',
            firstDispatchedAt: DateTime.utc(2020),
            replayPolicy: policy,
          ),
        );
        capable = policy != 'durable-v1';
        final operation = controller();
        expect(await operation.resume(), isA<ApiFailure<CashResult>>());
        expect(operation.state.phase, CashOperationPhase.recoveryRequired);
        expect((await store.load(scope))?.key, 'old-receive-key');
        operation.dispose();
      }
      expect(writes, 0);
    },
  );

  test(
    'permanent replay is safe beyond thirty days without key rotation',
    () async {
      await store.save(
        scope,
        PendingCashOperation(
          request: receive(),
          key: 'durable-old-key',
          firstDispatchedAt: DateTime.utc(2020),
          replayPolicy: 'durable-v1',
        ),
      );
      final operation = controller();
      expect(await operation.resume(), isA<ApiSuccess<CashResult>>());
      expect(keys, ['durable-old-key']);
      operation.dispose();
    },
  );

  test(
    'pending data is isolated by server and user, and cannot be replaced by a new body',
    () async {
      await store.save(
        scope,
        PendingCashOperation(
          request: receive(),
          key: 'scope-isolated',
          firstDispatchedAt: DateTime.utc(2026),
          replayPolicy: 'durable-v1',
        ),
      );
      expect(await store.load((server: scope.server, userId: 8)), isNull);
      expect(await store.load((server: 'http://other/api', userId: 7)), isNull);
      final operation = controller();
      expect(
        await operation.start(
          CashRequest.receive(
            customerId: 3,
            amountMinor: 1,
            date: '2026-10-01',
          ),
        ),
        isA<ApiFailure<CashResult>>(),
      );
      expect((await store.load(scope))?.request.body['amount'], 500);
      expect(writes, 0);
      current = false;
      expect(await operation.resume(), isA<ApiFailure<CashResult>>());
      expect(writes, 0);
      operation.dispose();
    },
  );

  test('duplicate taps cannot race persistence and dispatch', () async {
    final operation = controller();
    final gate = Completer<void>();
    dio.interceptors.insert(
      0,
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (options.path.endsWith('/capabilities')) await gate.future;
          handler.next(options);
        },
      ),
    );
    final first = operation.start(receive());
    final second = await operation.start(receive());
    expect(second, isA<ApiFailure<CashResult>>());
    gate.complete();
    expect(await first, isA<ApiSuccess<CashResult>>());
    expect(writes, 1);
    operation.dispose();
  });

  test(
    'reversal recovery checks current state and does not claim it caused an existing void',
    () async {
      final request = CashRequest.reverse(
        customerId: 3,
        paymentId: 12,
        reason: 'Duplicate',
      );
      await store.save(
        scope,
        PendingCashOperation(
          request: request,
          key: 'reverse-old-key',
          firstDispatchedAt: DateTime.utc(2020),
          replayPolicy: 'guarded-status-v1',
        ),
      );
      alreadyVoided = true;
      final operation = controller();
      expect(await operation.resume(), isA<ApiSuccess<CashResult>>());
      expect(operation.state.phase, CashOperationPhase.alreadyVoided);
      expect(writes, 0);
      expect(await store.load(scope), isNull);
      operation.dispose();
    },
  );

  test(
    'a used live receipt stays in recovery without a reversal POST',
    () async {
      await store.save(
        scope,
        PendingCashOperation(
          request: CashRequest.reverse(
            customerId: 3,
            paymentId: 12,
            reason: 'Duplicate',
          ),
          key: 'used-reverse-key',
          firstDispatchedAt: DateTime.utc(2020),
          replayPolicy: 'guarded-status-v1',
        ),
      );
      reversible = false;
      final operation = controller();
      expect(await operation.resume(), isA<ApiFailure<CashResult>>());
      expect(operation.state.phase, CashOperationPhase.recoveryRequired);
      expect(writes, 0);
      operation.dispose();
    },
  );

  test(
    'storage failure or session change before dispatch cannot issue a POST',
    () async {
      store = UnavailableCashStore();
      final unavailable = controller();
      expect(await unavailable.start(receive()), isA<ApiFailure<CashResult>>());
      expect(writes, 0);
      expect(unavailable.state.phase, CashOperationPhase.recoveryRequired);
      unavailable.dispose();
      store = CashPendingStore();
      dio.interceptors.insert(
        0,
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.endsWith('/capabilities')) current = false;
            handler.next(options);
          },
        ),
      );
      final switched = controller();
      expect(await switched.start(receive()), isA<ApiFailure<CashResult>>());
      expect(writes, 0);
      expect(await store.load(scope), isNull);
      switched.dispose();
    },
  );

  test('corrupt pending storage is retained and blocks new writes', () async {
    await store.save(
      scope,
      PendingCashOperation(
        request: receive(),
        key: 'corrupt-fixture',
        firstDispatchedAt: DateTime.utc(2020),
        replayPolicy: 'durable-v1',
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getKeys().single;
    await prefs.setString(key, '{invalid');
    final operation = controller();
    await operation.restore();
    expect(operation.state.phase, CashOperationPhase.recoveryRequired);
    expect(await operation.start(receive()), isA<ApiFailure<CashResult>>());
    expect(prefs.getString(key), '{invalid');
    expect(writes, 0);
    operation.dispose();
  });

  test(
    'an uncertain retry denied by current permissions keeps its original key',
    () async {
      timeout = true;
      final operation = controller();
      await operation.start(receive());
      final original = await store.load(scope);
      timeout = false;
      dio.interceptors.insert(
        0,
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.method == 'POST') {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.badResponse,
                  response: Response<dynamic>(
                    requestOptions: options,
                    statusCode: 403,
                    data: {'error': 'Forbidden'},
                  ),
                ),
              );
            } else {
              handler.next(options);
            }
          },
        ),
      );
      expect(await operation.resume(), isA<ApiFailure<CashResult>>());
      expect((await store.load(scope))?.key, original?.key);
      expect(operation.state.phase, CashOperationPhase.recoveryRequired);
      expect(effects, 1);
      operation.dispose();
    },
  );

  test(
    'intentional repeated receipts after success use distinct keys',
    () async {
      final operation = controller();
      expect(await operation.start(receive()), isA<ApiSuccess<CashResult>>());
      expect(await operation.start(receive()), isA<ApiSuccess<CashResult>>());
      expect(keys.toSet().length, 2);
      expect(effects, 2);
      operation.dispose();
    },
  );

  test(
    'apply and refund resume with their permanent application policies',
    () async {
      for (final request in [
        CashRequest.apply(
          customerId: 3,
          date: '2026-10-01',
          allocations: [CashAllocation(invoiceId: 9, amountMinor: 50000)],
        ),
        CashRequest.refund(
          customerId: 3,
          amountMinor: 50000,
          date: '2026-10-01',
        ),
      ]) {
        await store.save(
          scope,
          PendingCashOperation(
            request: request,
            key: 'permanent-${request.operation.name}',
            firstDispatchedAt: DateTime.utc(2020),
            replayPolicy: 'permanent-application-v1',
          ),
        );
        final operation = controller();
        expect(await operation.resume(), isA<ApiSuccess<CashResult>>());
        expect(bodies.last, request.body);
        expect(await store.load(scope), isNull);
        operation.dispose();
      }
    },
  );
}
