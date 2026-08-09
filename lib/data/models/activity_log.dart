/// Activity log models — shapes from `server/src/models/ActivityLog.ts`
/// and `GET /api/activity-logs*` responses (PORTING.md §5, `/activity-log`
/// module).
///
/// The list rows (`ActivityLogWithUser`) are the union of `activity_log.*`
/// and the joined `users.username`; timestamps arrive as SQLite strings
/// (`2026-08-09 10:30:00`), not ISO. `metadata` is a JSON string (the DB
/// stores the object serialized), kept raw here — the detail dialog shows
/// it read-only.
library;

import 'json_helpers.dart';

/// One activity log entry with the acting user's username (LEFT JOIN).
class ActivityLog {
  const ActivityLog({
    required this.id,
    this.userId,
    this.username,
    required this.action,
    required this.entityType,
    this.entityId,
    required this.description,
    required this.logLevel,
    this.ipAddress,
    this.userAgent,
    this.metadata,
    this.durationMs,
    required this.createdAt,
  });

  factory ActivityLog.fromJson(Map<String, dynamic> json) => ActivityLog(
    id: asInt(json['id']) ?? 0,
    userId: asInt(json['user_id']),
    username: asString(json['username']),
    action: asString(json['action']) ?? '',
    entityType: asString(json['entity_type']) ?? '',
    entityId: asInt(json['entity_id']),
    description: asString(json['description']) ?? '',
    logLevel: asString(json['log_level']) ?? 'INFO',
    ipAddress: asString(json['ip_address']),
    userAgent: asString(json['user_agent']),
    metadata: asString(json['metadata']),
    durationMs: asInt(json['duration_ms']),
    createdAt: asString(json['created_at']) ?? '',
  );

  final int id;
  final int? userId;
  final String? username;
  final String action;

  /// e.g. `Invoice`, `Customer`, `User`, `PurchaseOrder` — raw server value.
  final String entityType;
  final int? entityId;
  final String description;
  final String logLevel;
  final String? ipAddress;
  final String? userAgent;

  /// Raw JSON-string metadata (`null` when the entry has none).
  final String? metadata;
  final int? durationMs;

  /// SQLite timestamp (`YYYY-MM-DD HH:MM:SS`).
  final String createdAt;

  /// "Invoice #12" — empty entity becomes `—`.
  String get entityLabel => entityType.isEmpty
      ? '—'
      : (entityId == null ? entityType : '$entityType #$entityId');
}

/// A user selectable in the log-filter dropdown (`GET /activity-logs/users`,
/// `{id, username, full_name}`).
class ActivityLogUser {
  const ActivityLogUser({
    required this.id,
    required this.username,
    this.fullName,
  });

  factory ActivityLogUser.fromJson(Map<String, dynamic> json) =>
      ActivityLogUser(
        id: asInt(json['id']) ?? 0,
        username: asString(json['username']) ?? '',
        fullName: asString(json['full_name']),
      );

  final int id;
  final String username;
  final String? fullName;
}

/// One `{label, count}` bucket from the stats endpoint — the actions
/// breakdown uses `action`, top users `username`, daily activity `date`.
class ActivityCount {
  const ActivityCount(this.label, this.count);

  final String label;
  final int count;
}

/// `GET /activity-logs/stats` — action breakdown, top users, daily counts
/// and the total log volume (optionally within a date range).
class ActivityStats {
  const ActivityStats({
    required this.totalLogs,
    required this.actions,
    required this.users,
    required this.dailyActivity,
  });

  factory ActivityStats.fromJson(Object? json) {
    final map = json is Map<String, dynamic> ? json : const <String, dynamic>{};
    return ActivityStats(
      totalLogs: asInt(map['totalLogs']) ?? 0,
      actions: _counts(map['actions'], 'action'),
      users: _counts(map['users'], 'username'),
      dailyActivity: _counts(map['dailyActivity'], 'date'),
    );
  }

  final int totalLogs;
  final List<ActivityCount> actions;
  final List<ActivityCount> users;
  final List<ActivityCount> dailyActivity;

  /// Tolerant bucket parse — skips malformed rows instead of crashing.
  static List<ActivityCount> _counts(Object? list, String labelKey) =>
      list is List
      ? [
          for (final entry in list)
            if (entry is Map<String, dynamic>)
              ActivityCount(
                asString(entry[labelKey]) ?? '',
                asInt(entry['count']) ?? 0,
              ),
        ]
      : const <ActivityCount>[];
}
