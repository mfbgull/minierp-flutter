// Forecast providers — one future per screen. The demand list re-runs on
// filter changes (the server recomputes forecasts per call); the accuracy
// detail is a per-item family; the dashboard/trends/accuracy lists are
// invalidated by refresh / compute actions.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/paged_request.dart'
    show PagedRequest, PagedResponse;
import 'forecast_models.dart';
import 'forecast_repository.dart'
    show ForecastDemandFilters, forecastRepositoryProvider;

/// Active tab index of [ForecastShell] (0 dashboard, 1 demand, 2 trends,
/// 3 accuracy). A provider (not local state) so the dashboard's "View
/// All" links can switch tabs.
final forecastShellTabProvider = StateProvider<int>((ref) => 0);

/// Dashboard summary + alerts + top growing/declining.
final forecastDashboardProvider = FutureProvider<ForecastDashboardData>((
  ref,
) async {
  final result = await ref.watch(forecastRepositoryProvider).dashboard();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// Active demand filters; null = all. Changing any field refetches.
final forecastDemandFiltersProvider =
    StateProvider<ForecastDemandFilters>((ref) => const ForecastDemandFilters());

/// Current page (1-based) for the server-side pagination.
final forecastDemandPageProvider = StateProvider<int>((ref) => 1);

/// Rows per page; changing it resets to page 1 (the screen does that).
final forecastDemandLimitProvider = StateProvider<int>((ref) => 10);

/// Server-side search term (item code / name). Empty omits the param.
final forecastDemandSearchProvider = StateProvider<String>((ref) => '');

/// One page of demand forecast rows for the active filters — the
/// endpoint is now server-paginated (grid-pagination §7.3): the server
/// recomputes forecasts, filters, then slices by page/limit.
final forecastDemandProvider =
    FutureProvider<PagedResponse<ForecastDemand>>((ref) async {
      final filters = ref.watch(forecastDemandFiltersProvider);
      final page = ref.watch(forecastDemandPageProvider);
      final limit = ref.watch(forecastDemandLimitProvider);
      final search = ref.watch(forecastDemandSearchProvider);
      final result = await ref.watch(forecastRepositoryProvider).demandPaged(
        filters,
        PagedRequest(
          page: page,
          limit: limit,
          search: search.isEmpty ? null : search,
        ),
      );
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });

/// The full *filtered* demand list (one large page) — used by the mobile
/// card list and any totals. Watches the same filters but ignores
/// page/limit.
final filteredForecastDemandProvider =
    FutureProvider<List<ForecastDemand>>((ref) async {
      final filters = ref.watch(forecastDemandFiltersProvider);
      final search = ref.watch(forecastDemandSearchProvider);
      final result = await ref.watch(forecastRepositoryProvider).demandPaged(
        filters,
        PagedRequest(
          page: 1,
          limit: 10000,
          search: search.isEmpty ? null : search,
        ),
      );
      return switch (result) {
        ApiSuccess(:final data) => data.items,
        ApiFailure(:final error) => throw error,
      };
    });

/// Selected item for the trends charts; null = top 10 active items.
final forecastTrendsItemProvider = StateProvider<int?>((ref) => null);

/// Monthly sales/trend/forecast + per-item volume breakdown.
final forecastTrendsProvider = FutureProvider<ForecastTrendData>((ref) async {
  final itemId = ref.watch(forecastTrendsItemProvider);
  final result = await ref.watch(forecastRepositoryProvider).trends(itemId);
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// Per-item accuracy summary (MAPE/MAE/sMAPE), best first.
final forecastAccuracyProvider = FutureProvider<List<ItemAccuracy>>((ref) async {
  final result = await ref.watch(forecastRepositoryProvider).accuracy();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// Selected item for the accuracy trend chart.
final forecastAccuracyItemProvider = StateProvider<int?>((ref) => null);

/// One item's accuracy time series.
final forecastAccuracyDetailProvider = FutureProvider.autoDispose
    .family<List<AccuracyDataPoint>, int>((ref, itemId) async {
      final result = await ref
          .watch(forecastRepositoryProvider)
          .accuracyDetail(itemId);
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });
