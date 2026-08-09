import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart' show isoDate;
import '../../data/models/customer.dart' show Customer;
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
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/customer_repository.dart'
    show customerRepositoryProvider;
import '../../data/repositories/paged_request.dart'
    show PagedRequest;
import '../../data/repositories/report_repository.dart'
    show reportRepositoryProvider;

// Shared date helpers now live in lib/core/utils/date_utils.dart and
// lib/widgets/date_picker_helpers.dart — the report screens keep
// importing them through this file, so re-export the two names they use.
export '../../core/utils/date_utils.dart' show isoDate;
export '../../widgets/date_picker_helpers.dart' show pickReportDate;

// ── AR aging ─────────────────────────────────────────────────────────

/// Loads GET /reports/ar-aging (server default: as of today).
final arAgingProvider = FutureProvider<ArAgingReport>((ref) async {
  final result = await ref.watch(reportRepositoryProvider).arAging();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

// ── Sales summary ────────────────────────────────────────────────────

/// Date-range filters for the sales summary report — always non-null
/// (the endpoint requires both dates). Defaults mirror the web app's
/// `SalesSummaryReport` initial state: last month → today.
final reportSalesFromDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month - 1, now.day);
});
final reportSalesToDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

/// Loads GET /reports/sales-summary, re-running when the date range
/// changes (the screen's From/To buttons write these providers).
final salesSummaryProvider = FutureProvider<SalesSummaryReport>((ref) async {
  final from = ref.watch(reportSalesFromDateProvider);
  final to = ref.watch(reportSalesToDateProvider);
  final result = await ref
      .watch(reportRepositoryProvider)
      .salesSummary(fromDate: isoDate(from), toDate: isoDate(to));
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

// ── Low stock ────────────────────────────────────────────────────────

/// Loads GET /reports/low-stock.
final lowStockReportProvider = FutureProvider<List<LowStockReportRow>>((
  ref,
) async {
  final result = await ref.watch(reportRepositoryProvider).lowStock();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

// ── Stock level ──────────────────────────────────────────────────────

/// Loads GET /reports/stock-level.
final stockLevelReportProvider = FutureProvider<StockLevelReport>((ref) async {
  final result = await ref.watch(reportRepositoryProvider).stockLevel();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

// ── Stock valuation ──────────────────────────────────────────────────

/// Loads GET /reports/stock-valuation.
final stockValuationReportProvider = FutureProvider<StockValuationReport>((
  ref,
) async {
  final result = await ref.watch(reportRepositoryProvider).stockValuation();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

// ── Sales by customer ────────────────────────────────────────────────

/// Date-range filters for the sales-by-customer report. Defaults mirror
/// the web app's `SalesByCustomerReport` initial state: last month →
/// today (the endpoint requires both dates).
final reportSalesByCustomerFromDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month - 1, now.day);
});
final reportSalesByCustomerToDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

/// Loads GET /reports/sales-by-customer, re-running when the date range
/// changes (the screen's From/To buttons write these providers).
final salesByCustomerReportProvider = FutureProvider<List<SalesByCustomerRow>>((
  ref,
) async {
  final from = ref.watch(reportSalesByCustomerFromDateProvider);
  final to = ref.watch(reportSalesByCustomerToDateProvider);
  final result = await ref
      .watch(reportRepositoryProvider)
      .salesByCustomer(fromDate: isoDate(from), toDate: isoDate(to));
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

// ── DSO ──────────────────────────────────────────────────────────────

/// Date-range filters for the DSO report. Defaults mirror the web app's
/// `DSOReport` initial state: last month → today (the endpoint defaults
/// to the last 30 days when both are omitted, so these are always sent).
final reportDsoFromDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month - 1, now.day);
});
final reportDsoToDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

/// Loads GET /reports/dso, re-running when the date range changes.
final dsoReportProvider = FutureProvider<DSOMetric>((ref) async {
  final from = ref.watch(reportDsoFromDateProvider);
  final to = ref.watch(reportDsoToDateProvider);
  final result = await ref
      .watch(reportRepositoryProvider)
      .dso(fromDate: isoDate(from), toDate: isoDate(to));
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

// ── Cash flow ────────────────────────────────────────────────────────

/// Date-range filters for the cash flow report (the endpoint requires
/// both dates). Defaults mirror the web app: last month → today.
final reportCashFlowFromDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month - 1, now.day);
});
final reportCashFlowToDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

/// Loads GET /reports/cash-flow, re-running when the date range changes.
final cashFlowReportProvider = FutureProvider<CashFlowReport>((ref) async {
  final from = ref.watch(reportCashFlowFromDateProvider);
  final to = ref.watch(reportCashFlowToDateProvider);
  final result = await ref
      .watch(reportRepositoryProvider)
      .cashFlow(fromDate: isoDate(from), toDate: isoDate(to));
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

// ── Profit & loss ────────────────────────────────────────────────────

/// Date-range filters for the P&L report (the endpoint requires both
/// dates). Defaults mirror the web app: last month → today.
final reportProfitLossFromDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month - 1, now.day);
});
final reportProfitLossToDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

/// Loads GET /reports/profit-loss, re-running when the date range changes.
final profitLossReportProvider = FutureProvider<ProfitLossReport>((ref) async {
  final from = ref.watch(reportProfitLossFromDateProvider);
  final to = ref.watch(reportProfitLossToDateProvider);
  final result = await ref
      .watch(reportRepositoryProvider)
      .profitLoss(fromDate: isoDate(from), toDate: isoDate(to));
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

// ── Inventory movement ───────────────────────────────────────────────

/// Date-range filters for the inventory movement report. Defaults mirror
/// the web app: last month → today (the endpoint tolerates both omitted).
final reportMovementFromDateProvider = StateProvider<DateTime?>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month - 1, now.day);
});
final reportMovementToDateProvider = StateProvider<DateTime?>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

/// Loads GET /reports/inventory-movement, re-running when the date range
/// changes.
final inventoryMovementReportProvider = FutureProvider<InventoryMovementReport>(
  (ref) async {
    final from = ref.watch(reportMovementFromDateProvider);
    final to = ref.watch(reportMovementToDateProvider);
    final result = await ref
        .watch(reportRepositoryProvider)
        .inventoryMovement(
          fromDate: from == null ? null : isoDate(from),
          toDate: to == null ? null : isoDate(to),
        );
    return switch (result) {
      ApiSuccess(:final data) => data,
      ApiFailure(:final error) => throw error,
    };
  },
);

// ── Purchase summary ─────────────────────────────────────────────────

/// Date-range filters for the purchase summary report. Defaults mirror
/// the web app: last 3 months → today (the endpoint requires both
/// dates).
final reportPurchaseFromDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month - 3, now.day);
});
final reportPurchaseToDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

/// Loads GET /reports/purchase-summary, re-running when the date range
/// changes.
final purchaseSummaryReportProvider = FutureProvider<PurchaseSummaryReport>((
  ref,
) async {
  final from = ref.watch(reportPurchaseFromDateProvider);
  final to = ref.watch(reportPurchaseToDateProvider);
  final result = await ref
      .watch(reportRepositoryProvider)
      .purchaseSummary(fromDate: isoDate(from), toDate: isoDate(to));
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

// ── Top debtors ──────────────────────────────────────────────────────

/// Row limit for the top-debtors report (5/10/20/50, default 10 — same
/// options as the web page's filter).
final topDebtorsLimitProvider = StateProvider<int>((ref) => 10);

/// Loads GET /reports/top-debtors, re-running when the limit changes.
final topDebtorsReportProvider = FutureProvider<List<TopDebtorRow>>((
  ref,
) async {
  final limit = ref.watch(topDebtorsLimitProvider);
  final result = await ref
      .watch(reportRepositoryProvider)
      .topDebtors(limit: limit);
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

// ── Expenses report ─────────────────────────────────────────────────

/// Date-range filters for the expenses report (the endpoint requires
/// both dates). Defaults mirror the web app's `ExpensesReport` initial
/// state: last month → today.
final reportExpensesFromDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month - 1, now.day);
});
final reportExpensesToDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

/// Active category filter for the expenses report — null means "all
/// categories" (the `category` query param is omitted).
final reportExpensesCategoryProvider = StateProvider<String?>((ref) => null);

/// Loads GET /reports/expenses, re-running when the date range or the
/// selected category changes.
final expensesReportProvider = FutureProvider<ExpensesReport>((ref) async {
  final from = ref.watch(reportExpensesFromDateProvider);
  final to = ref.watch(reportExpensesToDateProvider);
  final category = ref.watch(reportExpensesCategoryProvider);
  final result = await ref
      .watch(reportRepositoryProvider)
      .expenses(
        fromDate: isoDate(from),
        toDate: isoDate(to),
        category: category,
      );
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

// ── Customer statements ─────────────────────────────────────────────

/// Date-range filters for the customer statements report. Defaults mirror
/// the web app's `CustomerStatementsReport` initial state: last 3 months
/// → today (the endpoint tolerates omitted dates, but the port always
/// sends them).
final reportStatementsFromDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month - 3, now.day);
});
final reportStatementsToDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

/// Active customer filter for the customer statements report — null means
/// "All Customers" (the `customerId` query param is omitted).
final reportStatementsCustomerIdProvider = StateProvider<int?>((ref) => null);

/// All customers for the customer statements customer picker (reuses the
/// same large-page pattern as the payments dialog).
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
  final from = ref.watch(reportStatementsFromDateProvider);
  final to = ref.watch(reportStatementsToDateProvider);
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
