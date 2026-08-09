// Dashboard layout repository — PORTING.md §10. Typed against the
// dashboard layout controller (`GET /dashboard/layout/active`,
// `POST /dashboard/layout`, `PUT /dashboard/layout/:id`,
// `DELETE /dashboard/layout/:id`).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart' show dioProvider;
import '../../core/api/endpoints.dart' show ApiEndpoints;
import '../models/dashboard_layout.dart' show DashboardBlock, DashboardLayout;
import 'api_result.dart' show ApiFailure, ApiResult, ApiSuccess;
import 'repository_client.dart';

class DashboardLayoutRepository {
  DashboardLayoutRepository(this._api);

  final RepositoryClient _api;

  /// `GET /dashboard/layout/active` — the current user's active layout,
  /// or `null` when none exists. The server 404s with
  /// `{success: true, data: null}` for the no-layout case; Dio surfaces a
  /// 404 as an error, so that specific failure is normalized back to
  /// "no saved layout" here.
  Future<ApiResult<DashboardLayout?>> activeLayout() async {
    final result = await _api.get<DashboardLayout?>(
      ApiEndpoints.dashboardLayoutActive,
      parse: (Object? json) => json == null
          ? null
          : DashboardLayout.fromJson(json as Map<String, dynamic>),
    );
    return switch (result) {
      ApiSuccess() => result,
      ApiFailure(:final error) when error.statusCode == 404 => ApiSuccess(null),
      ApiFailure() => result,
    };
  }

  /// `POST /dashboard/layout` — creates a new layout (201 enveloped).
  /// The server defaults `layout_name` to "Default" and `is_active` to
  /// true when omitted.
  Future<ApiResult<DashboardLayout>> createLayout({
    String? layoutName,
    List<DashboardBlock>? blocks,
  }) => _api.post(
    ApiEndpoints.dashboardLayout,
    body: {
      'layout_name': ?layoutName,
      if (blocks != null) 'blocks': [for (final b in blocks) b.toJson()],
    },
    parse: (Object? json) =>
        DashboardLayout.fromJson(json as Map<String, dynamic>),
  );

  /// `PUT /dashboard/layout/:id` — updates a layout's name and/or blocks
  /// (message-only envelope, no data payload).
  Future<ApiResult<void>> updateLayout(
    int id, {
    String? layoutName,
    List<DashboardBlock>? blocks,
  }) => _api.put<void>(
    '${ApiEndpoints.dashboardLayout}/$id',
    body: {
      'layout_name': ?layoutName,
      if (blocks != null) 'blocks': [for (final b in blocks) b.toJson()],
    },
    parse: (_) {},
  );

  /// `DELETE /dashboard/layout/:id` — message-only envelope.
  Future<ApiResult<void>> deleteLayout(int id) =>
      _api.delete('${ApiEndpoints.dashboardLayout}/$id');
}

final dashboardLayoutRepositoryProvider = Provider<DashboardLayoutRepository>(
  (ref) => DashboardLayoutRepository(RepositoryClient(ref.watch(dioProvider))),
);
