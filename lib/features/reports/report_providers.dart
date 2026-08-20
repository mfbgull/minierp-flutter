import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../preferences/preference_providers.dart' show initialRange;

import '../../core/utils/date_utils.dart' show isoDate;
import '../activity_log/activity_log_providers.dart'
    show activityLogFromDateProvider, activityLogToDateProvider;
import '../../data/models/customer.dart' show Customer;
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
        GeneralLedgerRow,
        IncomeStatementReport,
        ProfitLossReport,
        TaxSummaryReport,
        TopDebtorRow,
        TrialBalanceReport,
        ExpiryAlert,
        ExpiryReportRow;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/customer_repository.dart'
    show customerRepositoryProvider;
import '../../data/repositories/paged_request.dart'
    show PagedRequest;
import '../../data/repositories/report_repository.dart'
    show reportRepositoryProvider;

/// Normalized today — kept for the reconciliation single-date default
/// (range providers seed from [initialRange] instead).
DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

// ── AR aging ─────────────────────────────────────────────────────────

/// As-of date for the AR aging report (defaults to today).
final reportArAgingAsOfDateProvider = StateProvider<DateTime?>(
  (ref) => _today(),
);

/// Loads GET /reports/ar-aging, re-running when the as-of date changes.
final arAgingProvider = FutureProvider<ArAgingReport>((ref) async {
  final asOf = ref.watch(reportArAgingAsOfDateProvider);
  final result = await ref
      .watch(reportRepositoryProvider)
      .arAging(asOfDate: asOf == null ? null : isoDate(asOf));
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

// ── DSO ──────────────────────────────────────────────────────────────

/// Date-range filters for the DSO report.
final reportDsoFromDateProvider =
    StateProvider<DateTime?>((ref) => initialRange(ref).from);
final reportDsoToDateProvider = StateProvider<DateTime?>((ref) => initialRange(ref).to);

/// Loads GET /reports/dso, re-running when the date range changes.
final dsoReportProvider = FutureProvider<DSOMetric>((ref) async {
  final from = ref.watch(reportDsoFromDateProvider) ?? initialRange(ref).from;
  final to = ref.watch(reportDsoToDateProvider) ?? initialRange(ref).to;
  final result = await ref
      .watch(reportRepositoryProvider)
      .dso(fromDate: isoDate(from), toDate: isoDate(to));
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

// ── Cash flow ────────────────────────────────────────────────────────

/// Date-range filters for the cash flow report.
final reportCashFlowFromDateProvider =
    StateProvider<DateTime?>((ref) => initialRange(ref).from);
final reportCashFlowToDateProvider = StateProvider<DateTime?>((ref) => initialRange(ref).to);

/// Loads GET /reports/cash-flow, re-running when the date range changes.
final cashFlowReportProvider = FutureProvider<CashFlowReport>((ref) async {
  final from = ref.watch(reportCashFlowFromDateProvider) ?? initialRange(ref).from;
  final to = ref.watch(reportCashFlowToDateProvider) ?? initialRange(ref).to;
  final result = await ref
      .watch(reportRepositoryProvider)
      .cashFlow(fromDate: isoDate(from), toDate: isoDate(to));
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

// ── Profit & loss ────────────────────────────────────────────────────

/// Date-range filters for the P&L report.
final reportProfitLossFromDateProvider =
    StateProvider<DateTime?>((ref) => initialRange(ref).from);
final reportProfitLossToDateProvider =
    StateProvider<DateTime?>((ref) => initialRange(ref).to);

/// Loads GET /reports/profit-loss, re-running when the date range changes.
final profitLossReportProvider = FutureProvider<ProfitLossReport>((ref) async {
  final from = ref.watch(reportProfitLossFromDateProvider) ?? initialRange(ref).from;
  final to = ref.watch(reportProfitLossToDateProvider) ?? initialRange(ref).to;
  final result = await ref
      .watch(reportRepositoryProvider)
      .profitLoss(fromDate: isoDate(from), toDate: isoDate(to));
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

// ── Customer statements ─────────────────────────────────────────────

/// Date-range filters for the customer statements report.
final reportStatementsFromDateProvider =
    StateProvider<DateTime?>((ref) => initialRange(ref).from);
final reportStatementsToDateProvider =
    StateProvider<DateTime?>((ref) => initialRange(ref).to);

/// Active customer filter for the customer statements report.
final reportStatementsCustomerIdProvider = StateProvider<int?>((ref) => null);

/// All customers for the customer statements customer picker.
final customersForReportProvider = FutureProvider<List<Customer>>((ref) async {
  final result = await ref
      .watch(customerRepositoryProvider)
      .list(const PagedRequest(limit: 500));
  return switch (result) {
    ApiSuccess(:final data) => data.items,
    ApiFailure(:final error) => throw error,
  };
});

/// Loads GET /reports/customer-statements, re-running when the date range
/// or selected customer changes.
final customerStatementsReportProvider =
    FutureProvider<List<CustomerStatementRow>>((ref) async {
  final from = ref.watch(reportStatementsFromDateProvider) ?? initialRange(ref).from;
  final to = ref.watch(reportStatementsToDateProvider) ?? initialRange(ref).to;
  final customerId = ref.watch(reportStatementsCustomerIdProvider);
  final result = await ref
      .watch(reportRepositoryProvider)
      .customerStatements(
        fromDate: isoDate(from),
        toDate: isoDate(to),
        customerId: customerId,
      );
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

// ── Top debtors ──────────────────────────────────────────────────────

/// Row limit for the top-debtors report.
final topDebtorsLimitProvider = StateProvider<int>((ref) => 10);

/// Loads GET /reports/top-debtors, re-running when the limit changes.
final topDebtorsReportProvider = FutureProvider<List<TopDebtorRow>>((ref) async {
  final limit = ref.watch(topDebtorsLimitProvider);
  final result = await ref
      .watch(reportRepositoryProvider)
      .topDebtors(limit: limit);
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

// ── Cash reconciliation ──────────────────────────────────────────────

/// The single reconciliation date (defaults to today).
final reportReconciliationDateProvider = StateProvider<DateTime?>(
  (ref) => initialRange(ref).to,
);

/// Loads GET /reports/cash-reconciliation, re-running when the date changes.
final cashReconciliationProvider = FutureProvider<CashReconciliation>((ref) async {
  final date = ref.watch(reportReconciliationDateProvider) ?? _today();
  final result = await ref
      .watch(reportRepositoryProvider)
      .cashReconciliation(date: isoDate(date));
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

// ── AR summary ───────────────────────────────────────────────────────

/// Loads GET /reports/ar-summary (server default: as of today).
final arSummaryProvider = FutureProvider<ArSummaryReport>((ref) async {
  final result = await ref.watch(reportRepositoryProvider).arSummary();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

// ── AP aging ─────────────────────────────────────────────────────────

/// As-of date for the AP aging report (defaults to today).
final reportApAgingAsOfDateProvider = StateProvider<DateTime?>(
  (ref) => _today(),
);

/// Loads GET /reports/ap-aging, re-running when the as-of date changes.
final apAgingProvider = FutureProvider<ApAgingReport>((ref) async {
  final asOf = ref.watch(reportApAgingAsOfDateProvider);
  final result = await ref
      .watch(reportRepositoryProvider)
      .apAging(asOfDate: asOf == null ? null : isoDate(asOf));
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

// ── Balance sheet ────────────────────────────────────────────────────

/// As-of date for the balance sheet report (defaults to today).
final reportBalanceSheetAsOfDateProvider = StateProvider<DateTime?>(
  (ref) => _today(),
);

/// Loads GET /reports/balance-sheet, re-running when the as-of date changes.
final balanceSheetProvider = FutureProvider<BalanceSheetReport>((ref) async {
  final asOf = ref.watch(reportBalanceSheetAsOfDateProvider);
  final result = await ref
      .watch(reportRepositoryProvider)
      .balanceSheet(asOfDate: asOf == null ? null : isoDate(asOf));
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

// ── Global report date range ───────────────────────────────────────

/// App-wide default From/To range, set from the dashboard's date-range picker.
final globalReportFromDateProvider = StateProvider<DateTime?>(
  (ref) => initialRange(ref).from,
);
final globalReportToDateProvider = StateProvider<DateTime?>(
  (ref) => initialRange(ref).to,
);

/// Every report page's From/To provider pair — the targets of the
/// dashboard's global date range.
final reportTrialBalanceAsOfDateProvider = StateProvider<DateTime?>(
  (ref) => null,
);
final trialBalanceProvider = FutureProvider<TrialBalanceReport>((ref) async {
  final asOf = ref.watch(reportTrialBalanceAsOfDateProvider);
  final repo = ref.watch(reportRepositoryProvider);
  final result = await repo.trialBalance(
    asOfDate: asOf?.toIso8601String().split('T').first,
  );
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

final reportGeneralLedgerFromDateProvider = StateProvider<DateTime?>(
  (ref) => initialRange(ref).from,
);
final reportGeneralLedgerToDateProvider = StateProvider<DateTime?>(
  (ref) => initialRange(ref).to,
);
final generalLedgerProvider = FutureProvider<List<GeneralLedgerRow>>((ref) async {
  final from = ref.watch(reportGeneralLedgerFromDateProvider);
  final to = ref.watch(reportGeneralLedgerToDateProvider);
  final repo = ref.watch(reportRepositoryProvider);
  final result = await repo.generalLedger(
    startDate: from?.toIso8601String().split('T').first ?? '',
    endDate: to?.toIso8601String().split('T').first ?? '',
  );
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

final reportIncomeStatementFromDateProvider = StateProvider<DateTime?>(
  (ref) => initialRange(ref).from,
);
final reportIncomeStatementToDateProvider = StateProvider<DateTime?>(
  (ref) => initialRange(ref).to,
);
final incomeStatementProvider = FutureProvider<IncomeStatementReport>((ref) async {
  final from = ref.watch(reportIncomeStatementFromDateProvider);
  final to = ref.watch(reportIncomeStatementToDateProvider);
  final repo = ref.watch(reportRepositoryProvider);
  final result = await repo.incomeStatement(
    startDate: from?.toIso8601String().split('T').first ?? '',
    endDate: to?.toIso8601String().split('T').first ?? '',
  );
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

final reportTaxSummaryFromDateProvider = StateProvider<DateTime?>(
  (ref) => initialRange(ref).from,
);
final reportTaxSummaryToDateProvider = StateProvider<DateTime?>(
  (ref) => initialRange(ref).to,
);
final taxSummaryProvider = FutureProvider<TaxSummaryReport>((ref) async {
  final from = ref.watch(reportTaxSummaryFromDateProvider);
  final to = ref.watch(reportTaxSummaryToDateProvider);
  final repo = ref.watch(reportRepositoryProvider);
  final result = await repo.taxSummary(
    startDate: from?.toIso8601String().split('T').first ?? '',
    endDate: to?.toIso8601String().split('T').first ?? '',
  );
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

final batchTraceabilityItemIdProvider = StateProvider<int>(
  (ref) => 0,
);
final batchTraceabilityProvider = FutureProvider<BatchTraceabilityReport>((ref) async {
  final itemId = ref.watch(batchTraceabilityItemIdProvider);
  if (itemId <= 0) throw Exception('No item selected');
  final repo = ref.watch(reportRepositoryProvider);
  final result = await repo.batchTraceability(itemId);
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

// ── Expiry report ───────────────────────────────────────────────────

/// Optional warehouse filter for the expiry report.
final expiryReportWarehouseIdProvider = StateProvider<int?>((ref) => null);

/// Status filter: 'all' | 'expired' | 'near_expiry' | 'normal'.
final expiryReportStatusProvider = StateProvider<String>((ref) => 'all');

/// Threshold-days override (null = item default).
final expiryReportThresholdProvider = StateProvider<int?>((ref) => null);

/// Loads GET /reports/expiry, re-running when any filter changes.
final expiryReportProvider =
    FutureProvider.autoDispose<List<ExpiryReportRow>>((ref) async {
  final warehouseId = ref.watch(expiryReportWarehouseIdProvider);
  final status = ref.watch(expiryReportStatusProvider);
  final threshold = ref.watch(expiryReportThresholdProvider);
  final result = await ref
      .watch(reportRepositoryProvider)
      .expiryReport(
        warehouseId: warehouseId,
        status: status == 'all' ? null : status,
        thresholdDays: threshold,
      );
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

// ── Dashboard expiry alerts ─────────────────────────────────────────

/// Look-ahead window (days) for the dashboard expiry-alerts feed.
final expiryAlertsDaysProvider = StateProvider<int>((ref) => 30);

/// Loads GET /dashboard/expiry-alerts, re-running when [days] changes.
final expiryAlertsProvider =
    FutureProvider.autoDispose<List<ExpiryAlert>>((ref) async {
  final days = ref.watch(expiryAlertsDaysProvider);
  final result = await ref
      .watch(reportRepositoryProvider)
      .expiryAlerts(days: days);
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

final List<(StateProvider<DateTime?>, StateProvider<DateTime?>)>
    _reportRangePairs = [
      (reportDsoFromDateProvider, reportDsoToDateProvider),
      (reportCashFlowFromDateProvider, reportCashFlowToDateProvider),
      (reportProfitLossFromDateProvider, reportProfitLossToDateProvider),
      (reportStatementsFromDateProvider, reportStatementsToDateProvider),
      (activityLogFromDateProvider, activityLogToDateProvider),
    ];

/// Applies [from]..[to] to every report page's range providers.
void applyGlobalReportRange(WidgetRef ref, DateTime from, DateTime to) {
  for (final (fromProvider, toProvider) in _reportRangePairs) {
    ref.read(fromProvider.notifier).state = from;
    ref.read(toProvider.notifier).state = to;
  }
}
