import 'dashboard_layout.dart' show DashboardLayout;
import 'dashboard_summary.dart'
    show
        ArSummaryResult,
        CashPositionSummary,
        DashboardSummary,
        KpiResult,
        TopCustomer;
import 'report.dart' show ExpiryAlert;

import 'json_helpers.dart';

/// `GET /dashboard/boot` (spec 7.1) — the whole dashboard's initial
/// payload in ONE round trip: summary, active layout, KPI batch, cash
/// position, AR summary, expiry alerts and top customers. Cuts the
/// login boot from 8 parallel GETs to 1 (plus /auth/me + /preferences
/// = the ≤ 3 boot-call criterion).
///
/// Optional blocks degrade independently: [cash], [ar] and [kpis] may
/// be null/empty on a server-side block failure while the rest of the
/// payload stays usable.
class DashboardBoot {
  const DashboardBoot({
    required this.summary,
    required this.layout,
    required this.kpis,
    required this.cash,
    required this.ar,
    required this.expiryAlerts,
    required this.topCustomers,
  });

  factory DashboardBoot.fromJson(Map<String, dynamic> json) => DashboardBoot(
    summary: DashboardSummary.fromJson(
      (json['summary'] ?? const <String, dynamic>{}) as Map<String, dynamic>,
    ),
    layout: json['layout'] == null
        ? null
        : DashboardLayout.fromJson(json['layout'] as Map<String, dynamic>),
    kpis: {
      for (final e
          in ((json['kpis'] ?? const <String, dynamic>{})
                  as Map<String, dynamic>)
              .entries)
        if (e.value is Map<String, dynamic>)
          e.key: KpiResult.fromJson(e.value as Map<String, dynamic>),
    },
    cash: json['cash'] == null
        ? null
        : CashPositionSummary.fromJson(json['cash'] as Map<String, dynamic>),
    ar: json['ar'] == null
        ? null
        : ArSummaryResult.fromJson(json['ar'] as Map<String, dynamic>),
    expiryAlerts: [
      for (final row in json['expiryAlerts'] as List? ?? const [])
        ExpiryAlert.fromJson(row as Map<String, dynamic>),
    ],
    topCustomers: [
      for (final row in json['topCustomers'] as List? ?? const [])
        TopCustomer.fromJson(row as Map<String, dynamic>),
    ],
  );

  final DashboardSummary summary;

  /// The user's active layout, or null when none is saved (the
  /// dashboard renders its curated default).
  final DashboardLayout? layout;

  /// KPI batch keyed by metric (the same shape as kpi-batch).
  final Map<String, KpiResult> kpis;

  final CashPositionSummary? cash;
  final ArSummaryResult? ar;
  final List<ExpiryAlert> expiryAlerts;
  final List<TopCustomer> topCustomers;
}
