import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/dashboard_summary.dart' show DashboardSummary;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/dashboard_repository.dart'
    show dashboardRepositoryProvider;

/// Loads the aggregated dashboard KPIs (GET /dashboard/summary). Failures
/// surface as [ApiFailure.error]; the screen offers a retry via
/// `ref.invalidate` (which re-runs this provider).
final dashboardSummaryProvider = FutureProvider<DashboardSummary>((ref) async {
  final result = await ref.watch(dashboardRepositoryProvider).summary();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});
