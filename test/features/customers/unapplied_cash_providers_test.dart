import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:minierp_app/core/cache/cached_repository.dart';
import 'package:minierp_app/data/repositories/api_result.dart';
import 'package:minierp_app/data/repositories/repository_client.dart';
import 'package:minierp_app/data/models/unapplied_cash.dart';
import 'package:minierp_app/core/cache/cache_manager.dart';
import 'package:minierp_app/features/customers/customer_providers.dart';
import 'package:minierp_app/features/customers/unapplied_cash_providers.dart';
import 'package:minierp_app/features/payments/payments_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'successful operations refresh cash date views, activity and all customer consumers',
    () async {
      SharedPreferences.setMockInitialValues({});
      final calls = <String, int>{};
      final dio = Dio(BaseOptions(baseUrl: 'http://test/api'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.method == 'GET') {
              calls.update(
                options.path,
                (count) => count + 1,
                ifAbsent: () => 1,
              );
            }
            Object? data;
            if (options.method == 'POST') {
              data = {'paymentId': 12, 'applicationId': null, 'amount': 500};
            } else if (options.path.endsWith('/capabilities')) {
              data = {'receive': 'durable-v1'};
            } else if (options.path.endsWith('/unapplied-cash')) {
              data = {
                'customer_id': 3,
                'operation_date': options.queryParameters['operation_date'],
                'remaining_amount': 500,
                'available_amount': 500,
                'refundable_amount': 500,
                'receipts': [],
              };
            } else if (options.path == '/customers/3') {
              data = {'id': 3, 'customer_name': 'Fresh customer'};
            } else if (options.path == '/payments/12') {
              data = {
                'id': 12,
                'customer_id': 3,
                'payment_kind': 'UNAPPLIED_RECEIPT',
                'amount': 500,
              };
            } else {
              data = [];
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
                    'totalItems': 0,
                    'limit': 20,
                  },
                },
              ),
            );
          },
        ),
      );
      const scope = (server: 'http://test/api', userId: 7);
      final container = ProviderContainer(
        overrides: [
          repositoryClientProvider.overrideWithValue(RepositoryClient(dio)),
          cachedRepositoryClientProvider.overrideWithValue(
            CachedRepositoryClient(dio, cache: CacheManager()),
          ),
          currentCashScopeProvider.overrideWithValue(scope),
        ],
      );
      addTearDown(container.dispose);
      const summary = (customerId: 3, date: '2026-10-01', page: 1, limit: 20);
      const secondDate = (
        customerId: 3,
        date: '2026-10-02',
        page: 1,
        limit: 20,
      );
      const activity = (
        customerId: 3,
        fromDate: '2026-10-01',
        toDate: '2026-10-03',
        page: 1,
        limit: 20,
      );
      final providers = <ProviderListenable<AsyncValue<Object>>>[
        customerCashSummaryProvider(summary),
        customerCashSummaryProvider(secondDate),
        customerCashActivityProvider(activity),
        customerDetailProvider(3),
        customerLedgerProvider(3),
        customerInvoicesProvider(3),
        customerPaymentsProvider(3),
        paymentDetailProvider(12),
        unifiedPaymentsProvider,
      ];
      for (final provider in providers) {
        container.listen(provider, (previous, next) {});
      }
      await Future.wait([
        container.read(customerCashSummaryProvider(summary).future),
        container.read(customerCashSummaryProvider(secondDate).future),
        container.read(customerCashActivityProvider(activity).future),
        container.read(customerDetailProvider(3).future),
        container.read(customerLedgerProvider(3).future),
        container.read(customerInvoicesProvider(3).future),
        container.read(customerPaymentsProvider(3).future),
        container.read(paymentDetailProvider(12).future),
        container.read(unifiedPaymentsProvider.future),
      ]);
      final before = Map.of(calls);
      expect(
        await container
            .read(cashOperationProvider(scope).notifier)
            .start(
              CashRequest.receive(
                customerId: 3,
                amountMinor: 50000,
                date: '2026-10-01',
              ),
            ),
        isA<ApiSuccess<CashResult>>(),
      );
      await Future.wait([
        container.read(customerCashSummaryProvider(summary).future),
        container.read(customerCashSummaryProvider(secondDate).future),
        container.read(customerCashActivityProvider(activity).future),
        container.read(customerDetailProvider(3).future),
        container.read(customerLedgerProvider(3).future),
        container.read(customerInvoicesProvider(3).future),
        container.read(customerPaymentsProvider(3).future),
        container.read(paymentDetailProvider(12).future),
        container.read(unifiedPaymentsProvider.future),
      ]);
      for (final path in [
        '/customers/3',
        '/customers/3/ledger',
        '/invoices',
        '/payments',
        '/payments/12',
        '/payments/unified',
        '/customers/3/unapplied-cash/activity',
      ]) {
        expect(calls[path], greaterThan(before[path]!));
      }
      expect(
        calls['/customers/3/unapplied-cash'],
        before['/customers/3/unapplied-cash']! + 2,
      );
      final previous = calls['/customers/3/unapplied-cash']!;
      container.read(customerTabsVersionProvider.notifier).state++;
      await container.read(customerCashSummaryProvider(summary).future);
      expect(calls['/customers/3/unapplied-cash'], greaterThan(previous));
    },
  );
}
