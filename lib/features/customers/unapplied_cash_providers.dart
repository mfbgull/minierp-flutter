import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_notifier.dart';
import '../../data/models/unapplied_cash.dart';
import '../../data/repositories/api_result.dart';
import '../../data/repositories/unapplied_cash_repository.dart';
import 'customer_providers.dart';
import 'unapplied_cash_operation.dart';
import '../payments/payments_providers.dart';
import '../sales/invoice_providers.dart';
import '../dashboard/dashboard_providers.dart';
import '../reports/report_providers.dart';

typedef CashSummaryArgs = ({int customerId, String? date, int page, int limit});
typedef CashActivityArgs = ({
  int customerId,
  String? fromDate,
  String? toDate,
  int page,
  int limit,
});

final customerCashSummaryProvider = FutureProvider.autoDispose
    .family<CashSummary, CashSummaryArgs>((ref, args) async {
      ref.watch(customerTabsVersionProvider);
      final result = await ref
          .watch(unappliedCashRepositoryProvider)
          .summary(
            args.customerId,
            date: args.date,
            page: args.page,
            limit: args.limit,
          );
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });

final customerCashActivityProvider = FutureProvider.autoDispose
    .family<CashPage<CashActivity>, CashActivityArgs>((ref, args) async {
      ref.watch(customerTabsVersionProvider);
      final result = await ref
          .watch(unappliedCashRepositoryProvider)
          .activity(
            args.customerId,
            page: args.page,
            limit: args.limit,
            fromDate: args.fromDate,
            toDate: args.toDate,
          );
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });

final currentCashScopeProvider = Provider<CashScope?>((ref) {
  final auth = ref.watch(authProvider);
  final user = auth.user;
  if (!auth.isAuthenticated || user == null) return null;
  return (
    server: ref.watch(unappliedCashRepositoryProvider).server,
    userId: user.id,
  );
});

final cashPendingStoreProvider = Provider<CashPendingStore>(
  (ref) => CashPendingStore(),
);

final cashOperationProvider =
    StateNotifierProvider.family<
      CashOperationController,
      CashOperationState,
      CashScope
    >((ref, scope) {
      return CashOperationController(
        repository: ref.watch(unappliedCashRepositoryProvider),
        store: ref.watch(cashPendingStoreProvider),
        scope: scope,
        isCurrentScope: () => ref.read(currentCashScopeProvider) == scope,
        onSuccess: (customerId) => invalidateUnappliedCash(ref, customerId),
      );
    });

void invalidateUnappliedCash(Ref ref, int customerId) {
  ref.invalidate(customerDetailProvider(customerId));
  ref.invalidate(customerLedgerProvider(customerId));
  ref.invalidate(customerInvoicesProvider(customerId));
  ref.invalidate(customerPaymentsProvider(customerId));
  ref.read(customerTabsVersionProvider.notifier).state++;
  ref.read(customerLedgerVersionProvider.notifier).state++;
  ref.read(customerStatementVersionProvider.notifier).state++;
  ref.invalidate(customersProvider);
  ref.invalidate(invoicesProvider);
  ref.invalidate(customerOpenInvoicesProvider(customerId));
  ref.invalidate(paymentsProvider);
  ref.invalidate(paymentDetailProvider);
  ref.invalidate(unifiedPaymentsProvider);
  ref.invalidate(dashboardBootProvider);
  ref.invalidate(arAgingProvider);
  ref.invalidate(cashFlowReportProvider);
}
