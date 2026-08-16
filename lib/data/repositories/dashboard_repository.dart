// Dashboard repository — PORTING.md §10. Typed against the dashboard
// controller (`GET /dashboard/summary` + the seven block data endpoints:
// top-customers, sales-summary, expense-summary, production-status,
// stock-movement-summary, kpi, ar-summary).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart' show dioProvider;
import '../../core/api/endpoints.dart' show ApiEndpoints;
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
  (ref) => DashboardRepository(RepositoryClient(ref.watch(dioProvider))),
);
