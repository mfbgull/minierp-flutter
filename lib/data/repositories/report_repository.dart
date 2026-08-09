// Report repository — PORTING.md §11. Typed against the reports
// controller (`server-reference/reportsController.ts`): every report
// endpoint returns `{success, data}`; the data shapes come from
// `server-reference/Reports.ts`. New report methods are added as their
// screens are ported.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart' show dioProvider;
import '../../core/api/endpoints.dart' show ApiEndpoints;
import '../../data/models/report.dart'
    show
        ArAgingReport,
        CashFlowReport,
        CustomerStatementRow,
        DSOMetric,
        ExpensesReport,
        InventoryMovementReport,
        LowStockReportRow,
        ProfitLossReport,
        PurchaseSummaryReport,
        SalesByCustomerRow,
        SalesSummaryReport,
        StockLevelReport,
        StockValuationReport,
        TopDebtorRow;
import 'api_result.dart';
import 'repository_client.dart';

class ReportRepository {
  ReportRepository(this._api);

  final RepositoryClient _api;

  /// GET /reports/ar-aging — per-customer aging buckets + column totals.
  /// The server defaults `asOfDate` to today when omitted.
  Future<ApiResult<ArAgingReport>> arAging({String? asOfDate}) => _api.get(
    ApiEndpoints.reportArAging,
    queryParameters: asOfDate == null
        ? null
        : <String, dynamic>{'asOfDate': asOfDate},
    parse: (Object? json) =>
        ArAgingReport.fromJson(json as Map<String, dynamic>),
  );

  /// GET /reports/sales-summary — stats + per-invoice detail over a date
  /// range (the server defaults to the last month when omitted).
  Future<ApiResult<SalesSummaryReport>> salesSummary({
    String? fromDate,
    String? toDate,
  }) => _api.get(
    ApiEndpoints.reportSalesSummary,
    queryParameters: {'fromDate': ?fromDate, 'toDate': ?toDate},
    parse: (Object? json) =>
        SalesSummaryReport.fromJson(json as Map<String, dynamic>),
  );

  /// GET /reports/low-stock — items at or below their reorder level
  /// (no query params).
  Future<ApiResult<List<LowStockReportRow>>> lowStock() => _api.getList(
    ApiEndpoints.reportLowStock,
    parseItem: (Object? json) =>
        LowStockReportRow.fromJson(json as Map<String, dynamic>),
  );

  /// GET /reports/stock-level — every active item with its current stock,
  /// reorder level and derived status (no query params).
  Future<ApiResult<StockLevelReport>> stockLevel() => _api.get(
    ApiEndpoints.reportStockLevel,
    parse: (Object? json) =>
        StockLevelReport.fromJson(json as Map<String, dynamic>),
  );

  /// GET /reports/stock-valuation — inventory value per item (batch
  /// tracked or standard-cost fallback; no query params).
  Future<ApiResult<StockValuationReport>> stockValuation() => _api.get(
    ApiEndpoints.reportStockValuation,
    parse: (Object? json) =>
        StockValuationReport.fromJson(json as Map<String, dynamic>),
  );

  /// GET /reports/sales-by-customer — per-customer sales over a date
  /// range. The endpoint returns a **bare array** and requires both
  /// dates (the server 400s without them).
  Future<ApiResult<List<SalesByCustomerRow>>> salesByCustomer({
    required String fromDate,
    required String toDate,
  }) => _api.getList(
    ApiEndpoints.reportSalesByCustomer,
    queryParameters: {'fromDate': fromDate, 'toDate': toDate},
    parseItem: (Object? json) =>
        SalesByCustomerRow.fromJson(json as Map<String, dynamic>),
  );

  /// GET /reports/dso — Days Sales Outstanding metric. The server
  /// defaults to the last 30 days when dates are omitted.
  Future<ApiResult<DSOMetric>> dso({String? fromDate, String? toDate}) =>
      _api.get(
        ApiEndpoints.reportDso,
        queryParameters: {'fromDate': ?fromDate, 'toDate': ?toDate},
        parse: (Object? json) =>
            DSOMetric.fromJson(json as Map<String, dynamic>),
      );

  /// GET /reports/cash-flow — cash inflow/outflow over a date range.
  /// The endpoint requires both dates.
  Future<ApiResult<CashFlowReport>> cashFlow({
    required String fromDate,
    required String toDate,
  }) => _api.get(
    ApiEndpoints.reportCashFlow,
    queryParameters: {'fromDate': fromDate, 'toDate': toDate},
    parse: (Object? json) =>
        CashFlowReport.fromJson(json as Map<String, dynamic>),
  );

  /// GET /reports/profit-loss — revenue/COGS/expenses breakdown over a
  /// date range. The endpoint requires both dates.
  Future<ApiResult<ProfitLossReport>> profitLoss({
    required String fromDate,
    required String toDate,
  }) => _api.get(
    ApiEndpoints.reportProfitLoss,
    queryParameters: {'fromDate': fromDate, 'toDate': toDate},
    parse: (Object? json) =>
        ProfitLossReport.fromJson(json as Map<String, dynamic>),
  );

  /// GET /reports/inventory-movement — stock movements over a date
  /// range (dates optional; the server defaults to no filter). The
  /// endpoint also accepts an optional `itemId`, but the web port
  /// omits the item picker (same call as the other report ports).
  Future<ApiResult<InventoryMovementReport>> inventoryMovement({
    String? fromDate,
    String? toDate,
  }) => _api.get(
    ApiEndpoints.reportInventoryMovement,
    queryParameters: {'fromDate': ?fromDate, 'toDate': ?toDate},
    parse: (Object? json) =>
        InventoryMovementReport.fromJson(json as Map<String, dynamic>),
  );

  /// GET /reports/purchase-summary — purchase orders over a date range.
  /// The endpoint requires both dates.
  Future<ApiResult<PurchaseSummaryReport>> purchaseSummary({
    required String fromDate,
    required String toDate,
  }) => _api.get(
    ApiEndpoints.reportPurchaseSummary,
    queryParameters: {'fromDate': fromDate, 'toDate': toDate},
    parse: (Object? json) =>
        PurchaseSummaryReport.fromJson(json as Map<String, dynamic>),
  );

  /// GET /reports/expenses — expense rows over a date range, optionally
  /// narrowed to one category. The endpoint requires both dates (the
  /// server returns a 400 without either).
  Future<ApiResult<ExpensesReport>> expenses({
    required String fromDate,
    required String toDate,
    String? category,
  }) => _api.get(
    ApiEndpoints.reportExpenses,
    queryParameters: {
      'fromDate': fromDate,
      'toDate': toDate,
      'category': ?category,
    },
    parse: (Object? json) =>
        ExpensesReport.fromJson(json as Map<String, dynamic>),
  );

  /// GET /reports/customer-statements — per-customer statement summary
  /// over a date range, optionally narrowed by customer. Returns
  /// `{ statements: [...] }`.
  Future<ApiResult<List<CustomerStatementRow>>> customerStatements({
    String? fromDate,
    String? toDate,
    int? customerId,
  }) => _api.getList(
    ApiEndpoints.reportCustomerStatements,
    queryParameters: {
      'fromDate': ?fromDate,
      'toDate': ?toDate,
      'customerId': ?customerId,
    },
    parseItem: (Object? json) =>
        CustomerStatementRow.fromJson(json as Map<String, dynamic>),
  );

  /// GET /reports/top-debtors — customers with the highest outstanding
  /// balances. Returns a **bare array**; `limit` defaults to 10.
  Future<ApiResult<List<TopDebtorRow>>> topDebtors({int limit = 10}) =>
      _api.getList(
        ApiEndpoints.reportTopDebtors,
        queryParameters: {'limit': limit},
        parseItem: (Object? json) =>
            TopDebtorRow.fromJson(json as Map<String, dynamic>),
      );
}

final reportRepositoryProvider = Provider<ReportRepository>(
  (ref) => ReportRepository(RepositoryClient(ref.watch(dioProvider))),
);
