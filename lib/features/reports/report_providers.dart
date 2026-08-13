import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../preferences/preference_providers.dart' show initialRange;

import '../../core/utils/date_utils.dart' show isoDate;
import '../activity_log/activity_log_providers.dart'
    show activityLogFromDateProvider, activityLogToDateProvider;
import '../../data/models/customer.dart' show Customer;
import '../../data/models/item.dart' show Item;
import '../../data/models/report.dart'
    show
        ArAgingReport,
        ArSummaryReport,
        BomUsageReport,
        CashFlowReport,
        CashReconciliation,
        CustomerStatementRow,
        DSOMetric,
        ExpensesReport,
        InventoryMovementReport,
        LowStockReportRow,
        ProductionSummaryReport,
        ProfitLossReport,
        PurchaseSummaryReport,
        SalesByCustomerRow,
        SalesByItemRow,
        SalesSummaryReport,
        StockLevelReport,
        StockValuationReport,
        SupplierAnalysisRow,
        TopDebtorRow;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/customer_repository.dart'
    show customerRepositoryProvider;
import '../../data/repositories/inventory_repository.dart'
    show inventoryRepositoryProvider;
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

/// Loads GET /reports/ar-aging (server default: as of today).
final arAgingProvider = FutureProvider<ArAgingReport>((ref) async {
  final result = await ref.watch(reportRepositoryProvider).arAging();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

// ── Sales summary ────────────────────────────────────────────────────

/// Date-range filters for the sales summary report (the endpoint
/// requires both dates). Defaults mirror the web app's
/// `SalesSummaryReport` initial state: last month → today.
final reportSalesFromDateProvider =
    StateProvider<DateTime?>((ref) => initialRange(ref).from);
final reportSalesToDateProvider = StateProvider<DateTime?>((ref) => initialRange(ref).to);

/// Loads GET /reports/sales-summary, re-running when the date range
/// changes (the screen's From/To buttons write these providers).
final salesSummaryProvider = FutureProvider<SalesSummaryReport>((ref) async {
  final from = ref.watch(reportSalesFromDateProvider) ?? initialRange(ref).from;
  final to = ref.watch(reportSalesToDateProvider) ?? initialRange(ref).to;
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
final reportSalesByCustomerFromDateProvider =
    StateProvider<DateTime?>((ref) => initialRange(ref).from);
final reportSalesByCustomerToDateProvider =
    StateProvider<DateTime?>((ref) => initialRange(ref).to);

/// Loads GET /reports/sales-by-customer, re-running when the date range
/// changes (the screen's From/To buttons write these providers).
final salesByCustomerReportProvider = FutureProvider<List<SalesByCustomerRow>>((
  ref,
) async {
  final from =
      ref.watch(reportSalesByCustomerFromDateProvider) ?? initialRange(ref).from;
  final to = ref.watch(reportSalesByCustomerToDateProvider) ?? initialRange(ref).to;
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

/// Date-range filters for the cash flow report (the endpoint requires
/// both dates). Defaults mirror the web app: last month → today.
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

/// Date-range filters for the P&L report (the endpoint requires both
/// dates). Defaults mirror the web app: last month → today.
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

// ── Inventory movement ───────────────────────────────────────────────

/// Date-range filters for the inventory movement report. Defaults mirror
/// the web app: last month → today (the endpoint tolerates both omitted).
final reportMovementFromDateProvider =
    StateProvider<DateTime?>((ref) => initialRange(ref).from);
final reportMovementToDateProvider = StateProvider<DateTime?>((ref) => initialRange(ref).to);

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
final reportPurchaseFromDateProvider =
    StateProvider<DateTime?>((ref) => initialRange(ref).from);
final reportPurchaseToDateProvider = StateProvider<DateTime?>((ref) => initialRange(ref).to);

/// Loads GET /reports/purchase-summary, re-running when the date range
/// changes.
final purchaseSummaryReportProvider = FutureProvider<PurchaseSummaryReport>((
  ref,
) async {
  final from = ref.watch(reportPurchaseFromDateProvider) ?? initialRange(ref).from;
  final to = ref.watch(reportPurchaseToDateProvider) ?? initialRange(ref).to;
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
final reportExpensesFromDateProvider =
    StateProvider<DateTime?>((ref) => initialRange(ref).from);
final reportExpensesToDateProvider = StateProvider<DateTime?>((ref) => initialRange(ref).to);

/// Active category filter for the expenses report — null means "all
/// categories" (the `category` query param is omitted).
final reportExpensesCategoryProvider = StateProvider<String?>((ref) => null);

/// Loads GET /reports/expenses, re-running when the date range or the
/// selected category changes.
final expensesReportProvider = FutureProvider<ExpensesReport>((ref) async {
  final from = ref.watch(reportExpensesFromDateProvider) ?? initialRange(ref).from;
  final to = ref.watch(reportExpensesToDateProvider) ?? initialRange(ref).to;
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
final reportStatementsFromDateProvider =
    StateProvider<DateTime?>((ref) => initialRange(ref).from);
final reportStatementsToDateProvider =
    StateProvider<DateTime?>((ref) => initialRange(ref).to);

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

// ── Sales by item ────────────────────────────────────────────────────

/// Date-range filters for the sales-by-item report. Defaults mirror the
/// web app's `SalesByItemReport` initial state: last month → today (the
/// endpoint requires both dates).
final reportSalesByItemFromDateProvider =
    StateProvider<DateTime?>((ref) => initialRange(ref).from);
final reportSalesByItemToDateProvider =
    StateProvider<DateTime?>((ref) => initialRange(ref).to);

/// Loads GET /reports/sales-by-item, re-running when the date range
/// changes.
final salesByItemReportProvider = FutureProvider<List<SalesByItemRow>>((
  ref,
) async {
  final from = ref.watch(reportSalesByItemFromDateProvider) ?? initialRange(ref).from;
  final to = ref.watch(reportSalesByItemToDateProvider) ?? initialRange(ref).to;
  final result = await ref
      .watch(reportRepositoryProvider)
      .salesByItem(fromDate: isoDate(from), toDate: isoDate(to));
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

// ── Supplier analysis ────────────────────────────────────────────────

/// Date-range filters for the supplier-analysis report. Defaults mirror
/// the web app's `SupplierAnalysisReport` initial state: last 3 months
/// → today (the endpoint requires both dates).
final reportSupplierFromDateProvider =
    StateProvider<DateTime?>((ref) => initialRange(ref).from);
final reportSupplierToDateProvider =
    StateProvider<DateTime?>((ref) => initialRange(ref).to);

/// Loads GET /reports/supplier-analysis, re-running when the date range
/// changes.
final supplierAnalysisReportProvider = FutureProvider<List<SupplierAnalysisRow>>(
  (ref) async {
    final from = ref.watch(reportSupplierFromDateProvider) ?? initialRange(ref).from;
    final to = ref.watch(reportSupplierToDateProvider) ?? initialRange(ref).to;
    final result = await ref
        .watch(reportRepositoryProvider)
        .supplierAnalysis(fromDate: isoDate(from), toDate: isoDate(to));
    return switch (result) {
      ApiSuccess(:final data) => data,
      ApiFailure(:final error) => throw error,
    };
  },
);

// ── Production summary ───────────────────────────────────────────────

/// Date-range filters for the production-summary report. Defaults mirror
/// the web app's `ProductionSummaryReport` initial state: last month →
/// today (the endpoint requires both dates).
final reportProductionFromDateProvider =
    StateProvider<DateTime?>((ref) => initialRange(ref).from);
final reportProductionToDateProvider =
    StateProvider<DateTime?>((ref) => initialRange(ref).to);

/// Loads GET /reports/production-summary, re-running when the date range
/// changes.
final productionSummaryReportProvider =
    FutureProvider<ProductionSummaryReport>((ref) async {
  final from = ref.watch(reportProductionFromDateProvider) ?? initialRange(ref).from;
  final to = ref.watch(reportProductionToDateProvider) ?? initialRange(ref).to;
  final result = await ref
      .watch(reportRepositoryProvider)
      .productionSummary(fromDate: isoDate(from), toDate: isoDate(to));
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

// ── Cash reconciliation ──────────────────────────────────────────────

/// The single reconciliation date (defaults to today). The report is a
/// single-day view — the screen's date button writes this provider.
final reportReconciliationDateProvider = StateProvider<DateTime?>((
  ref,
) => initialRange(ref).to);

/// Loads GET /reports/cash-reconciliation, re-running when the date
/// changes.
final cashReconciliationProvider = FutureProvider<CashReconciliation>((
  ref,
) async {
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

// ── BOM usage ────────────────────────────────────────────────────────

/// Date-range filters for the bom-usage report. Defaults mirror the web
/// app's `BOMUsageReport` initial state: last month → today (the
/// endpoint tolerates omitted dates, but the port always sends them).
final reportBomFromDateProvider =
    StateProvider<DateTime?>((ref) => initialRange(ref).from);
final reportBomToDateProvider = StateProvider<DateTime?>((ref) => initialRange(ref).to);

/// Active finished-item filter for the bom-usage report — null means
/// "All Items" (the `itemId` query param is omitted).
final reportBomItemIdProvider = StateProvider<int?>((ref) => null);

/// All finished items for the bom-usage parent-item picker (reuses the
/// inventory repository's items list — the same source the web page's
/// `/inventory/items` select uses).
final finishedItemsForReportProvider = FutureProvider<List<Item>>((ref) async {
  final result = await ref
      .watch(inventoryRepositoryProvider)
      .items(isFinishedGood: true);
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// Loads GET /reports/bom-usage, re-running when the date range or the
/// selected finished item changes.
final bomUsageReportProvider = FutureProvider<BomUsageReport>((ref) async {
  final from = ref.watch(reportBomFromDateProvider) ?? initialRange(ref).from;
  final to = ref.watch(reportBomToDateProvider) ?? initialRange(ref).to;
  final itemId = ref.watch(reportBomItemIdProvider);
  final result = await ref
      .watch(reportRepositoryProvider)
      .bomUsage(
        fromDate: isoDate(from),
        toDate: isoDate(to),
        itemId: itemId,
      );
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

// ── Global report date range ───────────────────────────────────────

/// App-wide default From/To range, set from the dashboard's date-range
/// picker. Every report page inherits this range via
/// [applyGlobalReportRange]; each page's own From/To pickers can still
/// change that page's range afterwards.
final globalReportFromDateProvider = StateProvider<DateTime?>(
  (ref) => initialRange(ref).from,
);
final globalReportToDateProvider = StateProvider<DateTime?>(
  (ref) => initialRange(ref).to,
);

/// Every report page's From/To provider pair — the targets of the
/// dashboard's global date range. Top-level finals initialize lazily,
/// so this list may safely reference providers declared above.
final List<(StateProvider<DateTime?>, StateProvider<DateTime?>)>
    _reportRangePairs = [
      (reportSalesFromDateProvider, reportSalesToDateProvider),
      (reportSalesByCustomerFromDateProvider, reportSalesByCustomerToDateProvider),
      (reportDsoFromDateProvider, reportDsoToDateProvider),
      (reportCashFlowFromDateProvider, reportCashFlowToDateProvider),
      (reportProfitLossFromDateProvider, reportProfitLossToDateProvider),
      (reportMovementFromDateProvider, reportMovementToDateProvider),
      (reportPurchaseFromDateProvider, reportPurchaseToDateProvider),
      (reportExpensesFromDateProvider, reportExpensesToDateProvider),
      (reportStatementsFromDateProvider, reportStatementsToDateProvider),
      (reportSalesByItemFromDateProvider, reportSalesByItemToDateProvider),
      (reportSupplierFromDateProvider, reportSupplierToDateProvider),
      (reportProductionFromDateProvider, reportProductionToDateProvider),
      (reportBomFromDateProvider, reportBomToDateProvider),
      (activityLogFromDateProvider, activityLogToDateProvider),
    ];

/// Applies [from]..[to] to every report page's range providers — called
/// when the dashboard's global picker changes so all pages inherit the
/// new range. Pages keep their own pickers; a page stays on this range
/// until the global range changes again.
void applyGlobalReportRange(WidgetRef ref, DateTime from, DateTime to) {
  for (final (fromProvider, toProvider) in _reportRangePairs) {
    ref.read(fromProvider.notifier).state = from;
    ref.read(toProvider.notifier).state = to;
  }
}
