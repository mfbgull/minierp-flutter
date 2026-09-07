import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart' show isoDate;
import '../../data/models/dashboard_boot.dart' show DashboardBoot;
import '../../data/models/dashboard_layout.dart' show DashboardLayout;
import '../../data/models/report.dart' show ExpiryAlert;
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

/// Resolves an [ApiResult] to its data or throws the failure (the block
/// screens show the error via their own error panels + retry).
T _data<T>(ApiResult<T> result) => switch (result) {
  ApiSuccess(:final data) => data,
  ApiFailure(:final error) => throw error,
};

/// The composite dashboard boot fetch (spec 7.1): `GET /dashboard/boot`
/// returns the summary, active layout, KPI batch, cash position, AR
/// summary, expiry alerts and top customers in ONE round trip — the
/// login boot fires 1 dashboard call instead of 8.
///
/// Every dashboard provider below derives from this payload: watching
/// any of them fires (at most) this single request, and invalidating
/// [dashboardBootProvider] refreshes the whole dashboard in one call.
///
/// Failures surface as [ApiFailure.error]; the screen offers a retry
/// via `ref.invalidate`.
final dashboardBootProvider =
    FutureProvider<DashboardBootSnapshot>((ref) async {
      final from = ref.watch(globalReportFromDateProvider);
      final to = ref.watch(globalReportToDateProvider);
      final result = await ref.watch(dashboardRepositoryProvider).boot(
        metrics: [for (final def in kpiCardCatalog) def.metric],
        fromDate: from == null ? null : isoDate(from),
        toDate: to == null ? null : isoDate(to),
      );
      return DashboardBootSnapshot.from(_data(result));
    });

/// The boot payload flattened for the derived providers: the summary is
/// required (the whole screen errors without it) while the optional
/// blocks degrade to their "not fetched" markers — cash/AR to null, the
/// KPI map to empty, expiry alerts + top customers to empty lists. The
/// per-block providers turn those markers into their own error states
/// so a degraded optional block shows its panel-level retry, not a
/// silently blank panel.
class DashboardBootSnapshot {
  const DashboardBootSnapshot({
    required this.summary,
    required this.layout,
    required this.kpis,
    required this.cash,
    required this.ar,
    required this.expiryAlerts,
    required this.topCustomers,
  });

  factory DashboardBootSnapshot.from(DashboardBoot boot) =>
      DashboardBootSnapshot(
        summary: boot.summary,
        layout: boot.layout,
        kpis: boot.kpis,
        cash: boot.cash,
        ar: boot.ar,
        expiryAlerts: boot.expiryAlerts,
        topCustomers: boot.topCustomers,
      );

  final DashboardSummary summary;
  final DashboardLayout? layout;
  final Map<String, KpiResult> kpis;
  final CashPositionSummary? cash;
  final ArSummaryResult? ar;
  final List<ExpiryAlert> expiryAlerts;
  final List<TopCustomer> topCustomers;
}

/// Dashboard summary (KPIs + the sales/purchases chart). Derived from
/// the boot payload — no separate GET /dashboard/summary. Reacts to the
/// dashboard's global date range: changing the range refetches the boot
/// payload (the money figures + chart follow it).
final dashboardSummaryProvider = FutureProvider<DashboardSummary>((
  ref,
) async {
  final boot = await ref.watch(dashboardBootProvider.future);
  return boot.summary;
});

/// All KPI strip card values — read out of the boot payload's KPI batch
/// (spec 7.3: one batched fetch for the strip). The strip cards read
/// their metric out of the shared map; a missing metric renders '—'.
final dashboardKpiBatchProvider = FutureProvider<Map<String, KpiResult>>((
  ref,
) async {
  final boot = await ref.watch(dashboardBootProvider.future);
  return boot.kpis;
});

/// Cash & bank positions — derived from the boot payload. The opening-
/// balance dialog invalidates this provider after a save; when the boot
/// payload carries no cash data (server-side block failure) the strip
/// surfaces the boot error.
final dashboardCashPositionProvider = FutureProvider<CashPositionSummary>((
  ref,
) async {
  final boot = await ref.watch(dashboardBootProvider.future);
  final cash = boot.cash;
  if (cash == null) throw const _BootBlockMissing('cash-position');
  return cash;
});

/// AR aging summary — derived from the boot payload.
final dashboardArSummaryProvider = FutureProvider<ArSummaryResult>((
  ref,
) async {
  final boot = await ref.watch(dashboardBootProvider.future);
  final ar = boot.ar;
  if (ar == null) throw const _BootBlockMissing('ar-summary');
  return ar;
});

/// Top customers — derived from the boot payload (limit is fixed at 5,
/// what the server's boot composite fetches).
final dashboardTopCustomersProvider =
    FutureProvider<List<TopCustomer>>((ref) async {
      final boot = await ref.watch(dashboardBootProvider.future);
      return boot.topCustomers;
    });

/// Expiry alerts — derived from the boot payload (the server's boot
/// composite uses the same 30-day window as the default reports view).
/// The expiry panel on the dashboard watches this instead of firing a
/// separate GET /reports/expiry-alerts.
final dashboardExpiryAlertsProvider = FutureProvider<List<ExpiryAlert>>((
  ref,
) async {
  final boot = await ref.watch(dashboardBootProvider.future);
  return boot.expiryAlerts;
});

/// A dashboard block that the boot payload couldn't carry (server-side
/// block failure degraded it to null/empty). Rendered as the panel's
/// generic error + retry.
class _BootBlockMissing implements Exception {
  const _BootBlockMissing(this.block);

  final String block;

  @override
  String toString() => 'Dashboard block unavailable: $block';
}

/// Refreshes the whole dashboard: invalidating the boot provider
/// refetches `GET /dashboard/boot` once, and every derived provider
/// (summary, KPI batch, cash, AR, top customers, expiry alerts) rebuilds
/// from the new payload. Kept as a named helper so the screen's toolbar
/// refresh and the shell's refresh-on-visit map share one path.
void invalidateDashboardBlocks(WidgetRef ref) {
  ref.invalidate(dashboardBootProvider);
}

// ── Non-boot dashboard endpoints (dialog-only / rarely-changing) ────
// These stay standalone GETs: they are not part of the login boot
// payload and are fetched lazily by the dialogs that need them.

/// `GET /dashboard/cash-opening-balances` — the starting (seed)
/// balances each cash account was founded with. Edited from the
/// dashboard cash strip's opening-balance dialog; saving invalidates
/// this + [dashboardBootProvider] (the cash strip derives from the
/// boot payload).
final dashboardCashOpeningBalancesProvider =
    FutureProvider<CashOpeningBalances>((ref) async {
      final result = await ref
          .watch(dashboardRepositoryProvider)
          .cashOpeningBalances();
      return _data(result);
    });

/// `GET /dashboard/sales-summary?period=` — period drill-down dialog.
final dashboardSalesSummaryProvider =
    FutureProvider.family<SalesSummaryResult, String>((ref, period) async {
      final result = await ref
          .watch(dashboardRepositoryProvider)
          .salesSummary(period: period);
      return _data(result);
    });

/// `GET /dashboard/expense-summary?period=` — period drill-down dialog.
final dashboardExpenseSummaryProvider =
    FutureProvider.family<ExpenseSummaryResult, String>((ref, period) async {
      final result = await ref
          .watch(dashboardRepositoryProvider)
          .expenseSummary(period: period);
      return _data(result);
    });

/// `GET /dashboard/production-status`.
final dashboardProductionStatusProvider =
    FutureProvider<ProductionStatusResult>((ref) async {
      final result = await ref
          .watch(dashboardRepositoryProvider)
          .productionStatus();
      return _data(result);
    });

/// `GET /dashboard/stock-movement-summary?days=`.
final dashboardStockMovementSummaryProvider =
    FutureProvider.family<StockMovementSummaryResult, int>((ref, days) async {
      final result = await ref
          .watch(dashboardRepositoryProvider)
          .stockMovementSummary(days: days);
      return _data(result);
    });
