import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart' show isoDate;
import '../../data/models/dashboard_summary.dart'
    show
        ArSummaryResult,
        CashOpeningBalances,
        CashPositionSummary,
        DashboardSummary,
        ExpenseSummaryResult,
        KpiResult,
        ProductionStatusResult,
        SalesSummaryResult,
        StockMovementSummaryResult,
        TopCustomer;
import '../../data/repositories/api_result.dart'
    show ApiFailure, ApiResult, ApiSuccess;
import '../../data/repositories/dashboard_repository.dart'
    show dashboardRepositoryProvider;
import '../reports/report_providers.dart'
    show globalReportFromDateProvider, globalReportToDateProvider;

/// Loads the aggregated dashboard KPIs (GET /dashboard/summary), filtered
/// by the dashboard's global date range (the money figures + chart react
/// to the range picker). Failures surface as [ApiFailure.error]; the
/// screen offers a retry via `ref.invalidate`.
final dashboardSummaryProvider = FutureProvider<DashboardSummary>((ref) async {
  final from = ref.watch(globalReportFromDateProvider);
  final to = ref.watch(globalReportToDateProvider);
  final result = await ref.watch(dashboardRepositoryProvider).summary(
    fromDate: from == null ? null : isoDate(from),
    toDate: to == null ? null : isoDate(to),
  );
  return _data(result);
});

/// Resolves an [ApiResult] to its data or throws the failure (the block
/// screens show the error via their own error panels + retry).
T _data<T>(ApiResult<T> result) => switch (result) {
  ApiSuccess(:final data) => data,
  ApiFailure(:final error) => throw error,
};

/// `GET /dashboard/top-customers` (default limit 5).
final dashboardTopCustomersProvider =
    FutureProvider.family<List<TopCustomer>, int>((ref, limit) async {
      final result = await ref
          .watch(dashboardRepositoryProvider)
          .topCustomers(limit: limit);
      return _data(result);
    });

/// `GET /dashboard/sales-summary?period=`.
final dashboardSalesSummaryProvider =
    FutureProvider.family<SalesSummaryResult, String>((ref, period) async {
      final result = await ref
          .watch(dashboardRepositoryProvider)
          .salesSummary(period: period);
      return _data(result);
    });

/// `GET /dashboard/expense-summary?period=`.
final dashboardExpenseSummaryProvider =
    FutureProvider.family<ExpenseSummaryResult, String>((ref, period) async {
      final result = await ref
          .watch(dashboardRepositoryProvider)
          .expenseSummary(period: period);
      return _data(result);
    });

/// `GET /dashboard/production-status`.
final dashboardProductionStatusProvider =
    FutureProvider<ProductionStatusResult>((ref) async {
      final result = await ref
          .watch(dashboardRepositoryProvider)
          .productionStatus();
      return _data(result);
    });

/// `GET /dashboard/stock-movement-summary?days=`.
final dashboardStockMovementSummaryProvider =
    FutureProvider.family<StockMovementSummaryResult, int>((ref, days) async {
      final result = await ref
          .watch(dashboardRepositoryProvider)
          .stockMovementSummary(days: days);
      return _data(result);
    });

/// `GET /dashboard/kpi?metric=`.
final dashboardKpiProvider = FutureProvider.family<KpiResult, String>((
  ref,
  metric,
) async {
  final result = await ref
      .watch(dashboardRepositoryProvider)
      .kpi(metric: metric);
  return _data(result);
});

/// `GET /dashboard/ar-summary`.
final dashboardArSummaryProvider = FutureProvider<ArSummaryResult>((ref) async {
  final result = await ref.watch(dashboardRepositoryProvider).arSummary();
  return _data(result);
});

/// `GET /dashboard/cash-position` — closing balance per cash account
/// (Cash, Bank, Easypaisa, JazzCash, UPaisa) as of today.
final dashboardCashPositionProvider = FutureProvider<CashPositionSummary>((
  ref,
) async {
  final result = await ref.watch(dashboardRepositoryProvider).cashPosition();
  return _data(result);
});

/// `GET /dashboard/cash-opening-balances` — the starting (seed) balances
/// each cash account was founded with. Edited from the dashboard cash
/// strip; saving invalidates this + the cash-position provider.
final dashboardCashOpeningBalancesProvider =
    FutureProvider<CashOpeningBalances>((ref) async {
      final result = await ref
          .watch(dashboardRepositoryProvider)
          .cashOpeningBalances();
      return _data(result);
    });
