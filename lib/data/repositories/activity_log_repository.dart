// Activity log repository — typed against docs/API.md §Activity Logs and
// `server/src/controllers/activityLogController.ts` (PORTING.md §2).
//
// The list endpoint returns `{success, data, total, limit, offset}` (raw
// offset counters, not a `pagination` block) — wired through the
// client's [RepositoryClient.getOffsetPaged]. The option endpoints
// (entity-types / actions) are enveloped bare string arrays.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/endpoints.dart' show ApiEndpoints;
import '../models/activity_log.dart'
    show ActivityLog, ActivityLogUser, ActivityStats;
import '../models/json_helpers.dart' show asInt;
import 'api_result.dart';
import 'paged_request.dart' show OffsetPagedResponse;
import 'repository_client.dart';

/// Filters for `GET /activity-logs` — snake_case query params matching the
/// controller's `req.query` reads (`user_id`, `entity_type`, `action`,
/// `start_date`, `end_date`, `search`, `limit`, `offset`).
class ActivityLogFilters {
  const ActivityLogFilters({
    this.userId,
    this.entityType,
    this.action,
    this.startDate,
    this.endDate,
    this.search,
    this.limit = 50,
    this.offset = 0,
  });

  final int? userId;
  final String? entityType;
  final String? action;
  final String? startDate;
  final String? endDate;
  final String? search;
  final int limit;
  final int offset;

  Map<String, dynamic> toQuery() => {
    if (userId != null) 'user_id': userId,
    if (entityType != null && entityType!.isNotEmpty) 'entity_type': entityType,
    if (action != null && action!.isNotEmpty) 'action': action,
    if (startDate != null && startDate!.isNotEmpty) 'start_date': startDate,
    if (endDate != null && endDate!.isNotEmpty) 'end_date': endDate,
    if (search != null && search!.isNotEmpty) 'search': search,
    'limit': limit,
    'offset': offset,
  };
}

class ActivityLogRepository {
  ActivityLogRepository(this._api);

  final RepositoryClient _api;

  /// One page of logs, newest first (server `ORDER BY created_at DESC`).
  Future<ApiResult<OffsetPagedResponse<ActivityLog>>> logs(
    ActivityLogFilters filters,
  ) => _api.getOffsetPaged(
    ApiEndpoints.activityLog,
    queryParameters: filters.toQuery(),
    parseItem: (Object? json) =>
        ActivityLog.fromJson(json as Map<String, dynamic>),
  );

  /// Action breakdown + top users + daily counts + total volume.
  Future<ApiResult<ActivityStats>> stats() => _api.get(
    '${ApiEndpoints.activityLog}/stats',
    parse: (Object? json) => ActivityStats.fromJson(json),
  );

  /// Available `entity_type` values for the filter dropdown.
  Future<ApiResult<List<String>>> entityTypes() => _api.getList(
    '${ApiEndpoints.activityLog}/entity-types',
    parseItem: (Object? json) => json is String ? json : '',
  );

  /// Available `action` values for the filter dropdown.
  Future<ApiResult<List<String>>> actions() => _api.getList(
    '${ApiEndpoints.activityLog}/actions',
    parseItem: (Object? json) => json is String ? json : '',
  );

  /// Active users for the filter dropdown (`{id, username, full_name}`).
  Future<ApiResult<List<ActivityLogUser>>> users() => _api.getList(
    '${ApiEndpoints.activityLog}/users',
    parseItem: (Object? json) =>
        ActivityLogUser.fromJson(json as Map<String, dynamic>),
  );

  /// `POST /activity-logs/cleanup` (admin) — deletes log entries older
  /// than [days] (server validates `days >= 1`, default 90). The response
  /// carries the count in the envelope (`{success, message, deletedCount}`,
  /// no `data` key), parsed via [RepositoryClient.postEnvelope].
  Future<ApiResult<int>> cleanup({int days = 90}) => _api.postEnvelope(
    '${ApiEndpoints.activityLog}/cleanup',
    body: {'days': days},
    parse: (envelope) => asInt(envelope['deletedCount']) ?? 0,
  );
}

final activityLogRepositoryProvider = Provider<ActivityLogRepository>(
  (ref) => ActivityLogRepository(ref.watch(repositoryClientProvider)),
);
