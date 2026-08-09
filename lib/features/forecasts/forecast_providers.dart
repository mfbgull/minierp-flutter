// Forecast providers — one future per screen. The demand list re-runs on
// filter changes (the server recomputes forecasts per call); the accuracy
// detail is a per-item family; the dashboard/trends/accuracy lists are
// invalidated by refresh / compute actions.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import 'forecast_models.dart';
import 'forecast_repository.dart'
    show ForecastDemandFilters, forecastRepositoryProvider;

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

/// Demand forecast rows for the active filters.
final forecastDemandProvider = FutureProvider<List<ForecastDemand>>((ref) async {
  final filters = ref.watch(forecastDemandFiltersProvider);
  final result = await ref
      .watch(forecastRepositoryProvider)
      .demand(filters);
  return switch (result) {
    ApiSuccess(:final data) => data,
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
