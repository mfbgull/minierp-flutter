// Dashboard repository — PORTING.md §10. Typed against the dashboard
// controller (`GET /dashboard/summary` + the seven block data endpoints:
// top-customers, sales-summary, expense-summary, production-status,
// stock-movement-summary, kpi, ar-summary).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/endpoints.dart' show ApiEndpoints;
import '../../core/cache/cached_repository.dart'
    show cachedRepositoryClientProvider;
import '../models/dashboard_boot.dart' show DashboardBoot;
import '../models/dashboard_summary.dart'
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
import 'api_result.dart';
import 'repository_client.dart';

class DashboardRepository {
  DashboardRepository(this._api);

  final RepositoryClient _api;

  /// `GET /dashboard/boot` (spec 7.1) — the composite boot payload:
  /// summary + active layout + KPI batch + cash position + AR summary
  /// + expiry alerts + top customers in one round trip. The dashboard
  /// providers derive from this instead of firing 8 parallel GETs at
  /// login. Honours the dashboard's global date range for the money
  /// figures; [metrics] selects the KPI batch entries.
  Future<ApiResult<DashboardBoot>> boot({
    required List<String> metrics,
    String? fromDate,
    String? toDate,
  }) => _api.get(
    ApiEndpoints.dashboardBoot,
    queryParameters: {
      'metrics': metrics.join(','),
      'fromDate': ?fromDate,
      'toDate': ?toDate,
    },
    parse: (Object? json) =>
        DashboardBoot.fromJson(json as Map<String, dynamic>),
  );

  /// `GET /dashboard/summary` — KPIs + the sales/purchases chart.
  /// [fromDate]/[toDate] filter the money figures and the chart (the
  /// dashboard's global range picker); omitted → server defaults
  /// (7-day chart, all-time totals).
  Future<ApiResult<DashboardSummary>> summary({
    String? fromDate,
    String? toDate,
  }) => _api.get(
    ApiEndpoints.dashboardSummary,
    queryParameters: fromDate == null && toDate == null
        ? null
        : <String, dynamic>{'fromDate': fromDate, 'toDate': toDate},
    parse: (Object? json) =>
        DashboardSummary.fromJson(json as Map<String, dynamic>),
  );

  /// `GET /dashboard/top-customers?limit=N` → array.
  Future<ApiResult<List<TopCustomer>>> topCustomers({int limit = 5}) =>
      _api.getList(
        ApiEndpoints.dashboardTopCustomers,
        queryParameters: {'limit': limit},
        parseItem: (Object? json) =>
            TopCustomer.fromJson(json as Map<String, dynamic>),
      );

  /// `GET /dashboard/sales-summary?period=today|week|month`.
  Future<ApiResult<SalesSummaryResult>> salesSummary({
    String period = 'today',
  }) => _api.get(
    ApiEndpoints.dashboardSalesSummary,
    queryParameters: {'period': period},
    parse: (Object? json) =>
        SalesSummaryResult.fromJson(json as Map<String, dynamic>),
  );

  /// `GET /dashboard/expense-summary?period=week|month`.
  Future<ApiResult<ExpenseSummaryResult>> expenseSummary({
    String period = 'month',
  }) => _api.get(
    ApiEndpoints.dashboardExpenseSummary,
    queryParameters: {'period': period},
    parse: (Object? json) =>
        ExpenseSummaryResult.fromJson(json as Map<String, dynamic>),
  );

  /// `GET /dashboard/production-status`.
  Future<ApiResult<ProductionStatusResult>> productionStatus() => _api.get(
    ApiEndpoints.dashboardProductionStatus,
    parse: (Object? json) =>
        ProductionStatusResult.fromJson(json as Map<String, dynamic>),
  );

  /// `GET /dashboard/stock-movement-summary?days=N`.
  Future<ApiResult<StockMovementSummaryResult>> stockMovementSummary({
    int days = 7,
  }) => _api.get(
    ApiEndpoints.dashboardStockMovementSummary,
    queryParameters: {'days': days},
    parse: (Object? json) =>
        StockMovementSummaryResult.fromJson(json as Map<String, dynamic>),
  );

  /// `GET /dashboard/kpi?metric=stock_health`. Optional [fromDate]/
  /// [toDate] apply the dashboard's global range to the money metrics
  /// (stock snapshots stay unfiltered server-side, matching summary).
  Future<ApiResult<KpiResult>> kpi({
    String metric = 'stock_health',
    String? fromDate,
    String? toDate,
  }) => _api.get(
    ApiEndpoints.dashboardKpi,
    queryParameters: {
      'metric': metric,
      'fromDate': ?fromDate,
      'toDate': ?toDate,
    },
    parse: (Object? json) =>
        KpiResult.fromJson(json as Map<String, dynamic>),
  );

  /// `GET /dashboard/kpi-batch?metrics=a,b` — several KPIs in one round
  /// trip. Values are parsed per metric key into [KpiResult] (unknown
  /// metrics come back null and are skipped).
  Future<ApiResult<Map<String, KpiResult>>> kpiBatch({
    required List<String> metrics,
    String? fromDate,
    String? toDate,
  }) => _api.get(
    ApiEndpoints.dashboardKpiBatch,
    queryParameters: {
      'metrics': metrics.join(','),
      'fromDate': ?fromDate,
      'toDate': ?toDate,
    },
    parse: (Object? json) {
      final map = (json ?? <String, dynamic>{}) as Map<String, dynamic>;
      return {
        for (final e in map.entries)
          if (e.value is Map<String, dynamic>)
            e.key: KpiResult.fromJson(e.value as Map<String, dynamic>),
      };
    },
  );

  /// `GET /dashboard/ar-summary`.
  Future<ApiResult<ArSummaryResult>> arSummary() => _api.get(
    ApiEndpoints.dashboardArSummary,
    parse: (Object? json) =>
        ArSummaryResult.fromJson(json as Map<String, dynamic>),
  );

  /// `GET /dashboard/cash-position` — closing balance per cash account
  /// (Cash, Bank, Easypaisa, JazzCash, UPaisa) as of today.
  Future<ApiResult<CashPositionSummary>> cashPosition() => _api.get(
    ApiEndpoints.dashboardCashPosition,
    parse: (Object? json) =>
        CashPositionSummary.fromJson(json as Map<String, dynamic>),
  );

  /// `GET /dashboard/cash-opening-balances` — the starting (seed)
  /// balance each cash account was founded with.
  Future<ApiResult<CashOpeningBalances>> cashOpeningBalances() => _api.get(
    ApiEndpoints.dashboardCashOpeningBalances,
    parse: (Object? json) =>
        CashOpeningBalances.fromJson(json as Map<String, dynamic>),
  );

  /// `PUT /dashboard/cash-opening-balances` — save the starting balances
  /// for the given account keys (e.g. `[{'key': 'cash', 'amount': 20000}]`).
  Future<ApiResult<CashOpeningBalances>> saveCashOpeningBalances(
    List<({String key, num amount})> accounts,
  ) => _api.put(
    ApiEndpoints.dashboardCashOpeningBalances,
    body: {
      'accounts': [
        for (final a in accounts) {'key': a.key, 'amount': a.amount},
      ],
    },
    parse: (Object? json) =>
        CashOpeningBalances.fromJson(json as Map<String, dynamic>),
  );
}

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => DashboardRepository(ref.watch(cachedRepositoryClientProvider)),
);
