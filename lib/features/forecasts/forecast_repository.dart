// Forecast repository — typed against `server/src/controllers/forecastsController.ts`
// (PORTING.md §12). Every endpoint returns the standard `{success, data}`
// envelope; `POST /forecasts/compute-accuracy` additionally carries a
// `message` and puts the payload in the envelope body (not under `data`),
// so it goes through [RepositoryClient.postEnvelope].

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/endpoints.dart' show ApiEndpoints;
import '../../data/repositories/api_result.dart';
import '../../data/repositories/paged_request.dart' show PagedRequest, PagedResponse;
import '../../data/repositories/repository_client.dart';
import 'forecast_models.dart';

/// Server-side filters for `GET /forecasts/demand`.
class ForecastDemandFilters {
  const ForecastDemandFilters({this.category, this.trend, this.recommendation});

  final String? category;
  final String? trend;
  final String? recommendation;

  /// True when any filter narrows the list (drives the reset button's
  /// visibility on the demand screen).
  bool get hasFilters =>
      category != null || trend != null || recommendation != null;

  Map<String, dynamic> toQuery() => {
    if (category != null && category!.isNotEmpty) 'category': category,
    if (trend != null && trend!.isNotEmpty) 'trend': trend,
    if (recommendation != null && recommendation!.isNotEmpty)
      'recommendation': recommendation,
  };
}

class ForecastRepository {
  ForecastRepository(this._api);

  final RepositoryClient _api;

  /// Summary + alerts + top growing/declining.
  Future<ApiResult<ForecastDashboardData>> dashboard() => _api.get(
    '${ApiEndpoints.forecasts}/dashboard',
    parse: (Object? json) =>
        ForecastDashboardData.fromJson(json as Map<String, dynamic>),
  );

  /// One page of demand forecasts, filtered server-side. The server
  /// recomputes the forecasts on each call, then filters and slices by
  /// page/limit (grid-pagination §7.3 — the endpoint returns the flat
  /// paged envelope).
  Future<ApiResult<PagedResponse<ForecastDemand>>> demandPaged(
    ForecastDemandFilters filters,
    PagedRequest request,
  ) => _api.getPaged(
    '${ApiEndpoints.forecasts}/demand',
    queryParameters: {...filters.toQuery(), ...request.toQuery()},
    parseItem: (Object? json) =>
        ForecastDemand.fromJson(json as Map<String, dynamic>),
  );

  /// Monthly sales + moving average + next-month forecast, plus a per-item
  /// volume breakdown. `itemId == null` → the top 10 active items.
  Future<ApiResult<ForecastTrendData>> trends(int? itemId) => _api.get(
    '${ApiEndpoints.forecasts}/trends',
    queryParameters: {'itemId': ?itemId},
    parse: (Object? json) =>
        ForecastTrendData.fromJson(json as Map<String, dynamic>),
  );

  /// Per-item aggregated accuracy (MAPE/MAE/sMAPE), best MAPE first.
  Future<ApiResult<List<ItemAccuracy>>> accuracy() => _api.getList(
    '${ApiEndpoints.forecasts}/accuracy',
    parseItem: (Object? json) =>
        ItemAccuracy.fromJson(json as Map<String, dynamic>),
  );

  /// One item's accuracy time series (past predictions vs actuals).
  Future<ApiResult<List<AccuracyDataPoint>>> accuracyDetail(int itemId) =>
      _api.getList(
        '${ApiEndpoints.forecasts}/accuracy/$itemId',
        parseItem: (Object? json) =>
            AccuracyDataPoint.fromJson(json as Map<String, dynamic>),
      );

  /// Backfill actuals for past predictions. Returns the server's message
  /// plus `{computed, errors}` from the envelope body.
  Future<ApiResult<(String, ComputeAccuracyResult)>> computeAccuracy() =>
      _api.postEnvelope(
        '${ApiEndpoints.forecasts}/compute-accuracy',
        parse: (envelope) => (
          envelope['message'] is String ? envelope['message'] as String : '',
          ComputeAccuracyResult.fromJson(envelope),
        ),
      );
}

final forecastRepositoryProvider = Provider<ForecastRepository>(
  (ref) => ForecastRepository(ref.watch(repositoryClientProvider)),
);
