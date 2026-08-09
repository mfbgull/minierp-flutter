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

  Future<ApiResult<DashboardSummary>> summary() => _api.get(
    ApiEndpoints.dashboardSummary,
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

  /// `GET /dashboard/kpi?metric=stock_health`.
  Future<ApiResult<KpiResult>> kpi({String metric = 'stock_health'}) =>
      _api.get(
        ApiEndpoints.dashboardKpi,
        queryParameters: {'metric': metric},
        parse: (Object? json) =>
            KpiResult.fromJson(json as Map<String, dynamic>),
      );

  /// `GET /dashboard/ar-summary`.
  Future<ApiResult<ArSummaryResult>> arSummary() => _api.get(
    ApiEndpoints.dashboardArSummary,
    parse: (Object? json) =>
        ArSummaryResult.fromJson(json as Map<String, dynamic>),
  );
}

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => DashboardRepository(RepositoryClient(ref.watch(dioProvider))),
);
