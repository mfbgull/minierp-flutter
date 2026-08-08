import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart' show isoDate;
import '../../data/models/report.dart'
    show
        ArAgingReport,
        CashFlowReport,
        DSOMetric,
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
