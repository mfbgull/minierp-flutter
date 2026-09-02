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
        ApAgingReport,
        ArAgingReport,
        ArSummaryReport,
        BalanceSheetReport,
        BatchTraceabilityReport,
        CashFlowReport,
        CashReconciliation,
        CustomerStatementRow,
        DSOMetric,
        ExpiryAlert,
        ExpiryReportRow,
        GeneralLedgerRow,
        IncomeStatementReport,
        ProfitLossReport,
        TaxSummaryReport,
        TopDebtorRow,
        TrialBalanceReport;
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
    String? fromDate,
    String? toDate,
  }) => _api.get(
    ApiEndpoints.reportCashFlow,
    queryParameters: {'fromDate': ?fromDate, 'toDate': ?toDate},
    parse: (Object? json) =>
        CashFlowReport.fromJson(json as Map<String, dynamic>),
  );

  /// GET /reports/profit-loss — revenue/COGS/expenses breakdown over a
  /// date range. The endpoint requires both dates.
  Future<ApiResult<ProfitLossReport>> profitLoss({
    String? fromDate,
    String? toDate,
  }) => _api.get(
    ApiEndpoints.reportProfitLoss,
    queryParameters: {'fromDate': ?fromDate, 'toDate': ?toDate},
    parse: (Object? json) =>
        ProfitLossReport.fromJson(json as Map<String, dynamic>),
  );

  /// GET /reports/customer-statements — per-customer statement summary
  /// over a date range, optionally narrowed by customer. Returns
  /// `{ statements: [...] }`.
  Future<ApiResult<List<CustomerStatementRow>>> customerStatements({
    String? fromDate,
    String? toDate,
    int? customerId,
  }) => _api.get(
    ApiEndpoints.reportCustomerStatements,
    queryParameters: {
      'fromDate': ?fromDate,
      'toDate': ?toDate,
      'customerId': ?customerId,
    },
    parse: (Object? json) =>
        (json as Map<String, dynamic>)['statements'] == null
            ? <CustomerStatementRow>[]
            : [
                for (final item in json['statements'] as List)
                  CustomerStatementRow.fromJson(
                    item as Map<String, dynamic>,
                  ),
              ],
  );

  /// GET /reports/top-debtors — customers with the highest outstanding
  /// balances. Returns a **bare array**; `limit` defaults to 10.
  Future<ApiResult<List<TopDebtorRow>>> topDebtors({
    int limit = 10,
    String? asOfDate,
  }) =>
      _api.getList(
        ApiEndpoints.reportTopDebtors,
        queryParameters: {
          'limit': limit,
          if (asOfDate != null) 'asOfDate': asOfDate,
        },
        parseItem: (Object? json) =>
            TopDebtorRow.fromJson(json as Map<String, dynamic>),
      );

  /// GET /reports/ar-summary — rolling receivables summary as of a date
  /// (server default: today). Takes an optional `asOfDate` query param.
  Future<ApiResult<ArSummaryReport>> arSummary({String? asOfDate}) => _api.get(
    ApiEndpoints.reportArSummary,
    queryParameters: asOfDate == null
        ? null
        : <String, dynamic>{'asOfDate': asOfDate},
    parse: (Object? json) =>
        ArSummaryReport.fromJson(json as Map<String, dynamic>),
  );

  /// GET /reports/cash-reconciliation — end-of-day cash/till
  /// reconciliation for a single date: per-account opening/expected
  /// balances merged with any saved counted amounts.
  Future<ApiResult<CashReconciliation>> cashReconciliation({
    required String date,
  }) => _api.get(
    ApiEndpoints.reportCashReconciliation,
    queryParameters: {'date': date},
    parse: (Object? json) =>
        CashReconciliation.fromJson(json as Map<String, dynamic>),
  );

  /// POST /reports/cash-reconciliation — saves the counted end-of-day
  /// amounts for a date. `accounts` entries are `{key, counted_balance,
  /// notes}`; a null `counted_balance` clears the count. Returns the
  /// refreshed reconciliation.
  Future<ApiResult<CashReconciliation>> saveCashReconciliation({
    required String date,
    required List<Map<String, dynamic>> accounts,
  }) => _api.post(
    ApiEndpoints.reportCashReconciliation,
    body: {'date': date, 'accounts': accounts},
    parse: (Object? json) =>
        CashReconciliation.fromJson(json as Map<String, dynamic>),
  );

  /// GET /reports/ap-aging — per-supplier aging buckets + column totals.
  /// The server defaults `asOfDate` to today when omitted.
  Future<ApiResult<ApAgingReport>> apAging({String? asOfDate}) => _api.get(
    ApiEndpoints.reportApAging,
    queryParameters: asOfDate == null
        ? null
        : <String, dynamic>{'asOfDate': asOfDate},
    parse: (Object? json) =>
        ApAgingReport.fromJson(json as Map<String, dynamic>),
  );

  /// GET /reports/balance-sheet — assets / liabilities / equity as of a
  /// date. The server defaults `asOfDate` to today when omitted.
  Future<ApiResult<BalanceSheetReport>> balanceSheet({String? asOfDate}) =>
      _api.get(
        ApiEndpoints.reportBalanceSheet,
        queryParameters: asOfDate == null
            ? null
            : <String, dynamic>{'asOfDate': asOfDate},
        parse: (Object? json) =>
            BalanceSheetReport.fromJson(json as Map<String, dynamic>),
      );

  /// GET /reports/trial-balance — account balances as of a date.
  Future<ApiResult<TrialBalanceReport>> trialBalance({String? asOfDate}) =>
      _api.get(
        ApiEndpoints.reportTrialBalance,
        queryParameters: asOfDate == null
            ? null
            : <String, dynamic>{'asOfDate': asOfDate},
        parse: (Object? json) =>
            TrialBalanceReport.fromJson(json as Map<String, dynamic>),
      );

  /// GET /reports/general-ledger — ledger entries within a date range.
  Future<ApiResult<List<GeneralLedgerRow>>> generalLedger({
    String? startDate,
    String? endDate,
  }) =>
      _api.getList(
        ApiEndpoints.reportGeneralLedger,
        queryParameters: <String, dynamic>{
          'startDate': ?startDate,
          'endDate': ?endDate,
        },
        parseItem: (Object? json) =>
            GeneralLedgerRow.fromJson(json as Map<String, dynamic>),
      );

  /// GET /reports/income-statement — revenue, COGS, expenses, net income.
  Future<ApiResult<IncomeStatementReport>> incomeStatement({
    String? startDate,
    String? endDate,
  }) =>
      _api.get(
        ApiEndpoints.reportIncomeStatement,
        queryParameters: <String, dynamic>{
          'startDate': ?startDate,
          'endDate': ?endDate,
        },
        parse: (Object? json) =>
            IncomeStatementReport.fromJson(json as Map<String, dynamic>),
      );

  /// GET /reports/tax-summary — total tax for a date range.
  Future<ApiResult<TaxSummaryReport>> taxSummary({
    String? startDate,
    String? endDate,
  }) =>
      _api.get(
        ApiEndpoints.reportTaxSummary,
        queryParameters: <String, dynamic>{
          'startDate': ?startDate,
          'endDate': ?endDate,
        },
        parse: (Object? json) =>
            TaxSummaryReport.fromJson(json as Map<String, dynamic>),
      );

  /// GET /reports/batch-traceability/:itemId — stock movements for an item.
  Future<ApiResult<BatchTraceabilityReport>> batchTraceability(int itemId) =>
      _api.get(
        '${ApiEndpoints.reportBatchTraceability}/$itemId',
        parse: (Object? json) =>
            BatchTraceabilityReport.fromJson(json as Map<String, dynamic>),
      );

  /// GET /reports/expiry — batches with expiry info, filtered by warehouse,
  /// status, and a threshold-day override.
  Future<ApiResult<List<ExpiryReportRow>>> expiryReport({
    int? warehouseId,
    int? thresholdDays,
    String? status,
  }) => _api.getRawList(
    ApiEndpoints.reportExpiry,
    queryParameters: <String, dynamic>{
      if (warehouseId != null) 'warehouse_id': warehouseId,
      if (thresholdDays != null) 'threshold_days': thresholdDays,
      if (status != null) 'status': status,
    },
    parseItem: (Object? json) =>
        ExpiryReportRow.fromJson(json as Map<String, dynamic>),
  );

  /// GET /dashboard/expiry-alerts — top batches expiring within [days].
  Future<ApiResult<List<ExpiryAlert>>> expiryAlerts({int days = 30}) =>
      _api.getRawList(
        ApiEndpoints.dashboardExpiryAlerts,
        queryParameters: <String, dynamic>{'days': days},
        parseItem: (Object? json) =>
            ExpiryAlert.fromJson(json as Map<String, dynamic>),
      );
}

final reportRepositoryProvider = Provider<ReportRepository>(
  (ref) => ReportRepository(RepositoryClient(ref.watch(dioProvider))),
);
