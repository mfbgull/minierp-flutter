// Activity log providers — one offset-paged list provider watching the
// search/page/limit/filter state (each change refetches), plus the stats
// and filter-option providers the screen's toolbar and summary strip read.
//
// List endpoint: `GET /activity-logs` returns `{data, total, limit,
// offset}` (no `pagination` block) — see ActivityLogRepository.logs.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart' show isoDate;
import '../../data/models/activity_log.dart'
    show ActivityLog, ActivityLogUser, ActivityStats;
import '../../data/repositories/activity_log_repository.dart'
    show ActivityLogFilters, activityLogRepositoryProvider;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/paged_request.dart' show OffsetPagedResponse;

/// Server-side search term; empty omits the param (matches description
/// and entity_type with LIKE).
final activityLogSearchProvider = StateProvider<String>((ref) => '');

/// 1-based page; the screen resets it to 1 whenever a filter changes.
final activityLogPageProvider = StateProvider<int>((ref) => 1);

/// Rows per page (server default is 50).
final activityLogLimitProvider = StateProvider<int>((ref) => 50);

/// Active entity-type filter; null = all (`GET /activity-logs/entity-types`
/// supplies the dropdown options).
final activityLogEntityTypeProvider = StateProvider<String?>((ref) => null);

/// Active action filter; null = all (`GET /activity-logs/actions`).
final activityLogActionProvider = StateProvider<String?>((ref) => null);

/// Active user filter; null = all (`GET /activity-logs/users`).
final activityLogUserIdProvider = StateProvider<int?>((ref) => null);

/// Inclusive date-range filter — null means unbounded (sent as
/// `start_date`/`end_date`).
final activityLogFromDateProvider = StateProvider<DateTime?>((ref) => null);
final activityLogToDateProvider = StateProvider<DateTime?>((ref) => null);

/// One page of logs. Re-runs when any filter/paging state changes; the
/// screen invalidates it on refresh.
final activityLogsProvider = FutureProvider<OffsetPagedResponse<ActivityLog>>((
  ref,
) async {
  final search = ref.watch(activityLogSearchProvider);
  final page = ref.watch(activityLogPageProvider);
  final limit = ref.watch(activityLogLimitProvider);
  final entityType = ref.watch(activityLogEntityTypeProvider);
  final action = ref.watch(activityLogActionProvider);
  final userId = ref.watch(activityLogUserIdProvider);
  final from = ref.watch(activityLogFromDateProvider);
  final to = ref.watch(activityLogToDateProvider);

  final result = await ref
      .watch(activityLogRepositoryProvider)
      .logs(
        ActivityLogFilters(
          search: search.isEmpty ? null : search,
          offset: (page - 1) * limit,
          limit: limit,
          entityType: entityType,
          action: action,
          userId: userId,
          startDate: from == null ? null : isoDate(from),
          endDate: to == null ? null : isoDate(to),
        ),
      );
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// Stats strip data: total volume, action breakdown, top users, daily
/// counts.
final activityStatsProvider = FutureProvider<ActivityStats>((ref) async {
  final result = await ref.watch(activityLogRepositoryProvider).stats();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// Filter-dropdown options (entity types present in the log).
final activityEntityTypesProvider = FutureProvider<List<String>>((ref) async {
  final result = await ref.watch(activityLogRepositoryProvider).entityTypes();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// Filter-dropdown options (actions present in the log).
final activityActionsProvider = FutureProvider<List<String>>((ref) async {
  final result = await ref.watch(activityLogRepositoryProvider).actions();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// Filter-dropdown options (active users).
final activityUsersProvider = FutureProvider<List<ActivityLogUser>>((
  ref,
) async {
  final result = await ref.watch(activityLogRepositoryProvider).users();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});
