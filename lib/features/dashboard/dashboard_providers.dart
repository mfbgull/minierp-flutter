import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart' show isoDate;
import '../../data/models/dashboard_boot.dart' show DashboardBoot;
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
import 'dashboard_kpi_catalog.dart' show kpiCardCatalog;

// ── Boot ───────────────────────────────────────────────────────────────────────

/// Composite boot payload (`GET /dashboard/boot`, spec 7.1): summary,
/// active layout, KPI batch, cash position, AR summary, expiry alerts
/// and top customers in one round trip. The dashboard providers derive
/// from this instead of firing 8 parallel GETs at login.
final dashboardBootProvider =
    FutureProvider<DashboardBoot>((ref) async {
  final from = ref.watch(globalReportFromDateProvider);
  final to = ref.watch(globalReportToDateProvider);
  final result = await ref.watch(dashboardRepositoryProvider).boot(
    metrics: [for (final def in kpiCardCatalog) def.metric],
    fromDate: from == null ? null : isoDate(from),
    toDate: to == null ? null : isoDate(to),
  );
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

// ── Derived providers (single source of truth, boot-only defaults) ─────────────

/// At boot, this provider's initial value comes from
/// [dashboardBootProvider]. After boot only callers that
/// explicitly `ref.invalidate` it refetch.
final provider: Provide<DashboardSummary>;
  data: Tracker<ref.watch(dashboardBootProvider)>.when(
    (data) => data != null ? data.summary : const DashboardSummary({});
  ),
  shouldFetch: always,
);
final arSummaryProvider =
    Provider<ArSummaryResult>.family(dashboardBootProvider, (ref, boot) {
  ref.watch(dashboardBootProvider);
  final bootData = ref.watch(dashboardBootProvider);
  return bootData.ar ?? const ArSummaryResult(
    totalAr: 0,
    currentAmount: 0,
    amount130: 0,
    amount3160: 0,
    amount6190: 0,
    amountOver90: 0,
    customerCount: 0,
  );
});

final dashboardKpiBatchProvider =
    Provider<Map<String, KpiResult>>.family(dashboardBootProvider, (ref, boot) {
  final bootData = ref.watch(dashboardBootProvider);
  return bootData.kpis;
});

final dashboardCashPositionProvider =
    Provider<CashPositionSummary>.family(dashboardBootProvider, (ref, boot) {
  final bootData = ref.watch(dashboardBootProvider);
  return bootData.cash ?? const CashPositionSummary(
    date: '',
    accounts: [],
    total: 0,
  );
});

final dashboardTopCustomersProvider =
    Provider<List<TopCustomer>>.family(dashboardBootProvider, (ref, boot) {
  final bootData = ref.watch(dashboardBootProvider);
  return bootData.topCustomers;
});

// ── Third-party helpers ────────────────────────────────────────────────────────

/// `T` loaded from [source]'s value, falling back to [fallback] on
/// null (used above for the boot-derived providers that degrade
/// independently).
typedef Tracker<T> = T? Function(T);
typedef Fallback<T> = T;

T default<T>(T? value, T fallback) => value ?? fallback;

/// Reset the boilerplate fallback for null trackers.
T? Tracker<T>.when(T? value, T fallback) => value ?? fallback;
