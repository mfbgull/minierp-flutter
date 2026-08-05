// Dashboard repository — PORTING.md §10. Typed against the dashboard
// controller (`GET /dashboard/summary` → `{success, data: DashboardSummary}`);
// the remaining block endpoints (top-customers, kpi, ar-summary, …) are
// added as their dashboard blocks are ported.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart' show dioProvider;
import '../../core/api/endpoints.dart' show ApiEndpoints;
import '../models/dashboard_summary.dart' show DashboardSummary;
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
}

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => DashboardRepository(RepositoryClient(ref.watch(dioProvider))),
);
