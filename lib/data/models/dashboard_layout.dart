import 'json_helpers.dart';

// ============================================================
//  DASHBOARD LAYOUT PERSISTENCE MODELS (PORTING.md §10)
//  Per-user customizable dashboard layouts + their blocks.
//  Shapes taken from `server/src/models/DashboardLayout.ts`.
// ============================================================

/// `config` on a [DashboardBlock]. The server treats this as an open map
/// (`[key: string]: unknown`), so the known fields are typed here and any
/// unrecognized keys are preserved in [extras] so a save→load round-trip
/// never drops block settings.
class DashboardBlockConfig {
  const DashboardBlockConfig({
    this.refreshInterval,
    this.text,
    this.metric,
    this.limit,
    this.period,
    this.days,
    this.extras = const {},
  });

  factory DashboardBlockConfig.fromJson(Map<String, dynamic> json) {
    const known = {
      'refreshInterval',
      'text',
      'metric',
      'limit',
      'period',
      'days',
    };
    return DashboardBlockConfig(
      refreshInterval: asNum(json['refreshInterval']),
      text: asString(json['text']),
      metric: asString(json['metric']),
      limit: asNum(json['limit']),
      period: asString(json['period']),
      days: asNum(json['days']),
      extras: {
        for (final entry in json.entries)
          if (!known.contains(entry.key)) entry.key: entry.value,
      },
    );
  }

  final num? refreshInterval;
  final String? text;
  final String? metric;
  final num? limit;
  final String? period;
  final num? days;

  /// Unrecognized config keys, preserved verbatim for round-trips.
  final Map<String, dynamic> extras;

  Map<String, dynamic> toJson() => {
    if (refreshInterval != null) 'refreshInterval': refreshInterval,
    if (text != null) 'text': text,
    if (metric != null) 'metric': metric,
    if (limit != null) 'limit': limit,
    if (period != null) 'period': period,
    if (days != null) 'days': days,
    ...extras,
  };
}

/// A single block on a dashboard layout — `DashboardBlock.ts`.
class DashboardBlock {
  const DashboardBlock({
    required this.id,
    required this.type,
    required this.title,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.visible = true,
    this.version = 1,
    this.config = const DashboardBlockConfig(),
  });

  factory DashboardBlock.fromJson(Map<String, dynamic> json) => DashboardBlock(
    id: asString(json['id']) ?? '',
    type: asString(json['type']) ?? '',
    title: asString(json['title']) ?? '',
    x: asNum(json['x']) ?? 0,
    y: asNum(json['y']) ?? 0,
    width: asNum(json['width']) ?? 1,
    height: asNum(json['height']) ?? 1,
    visible: asBool(json['visible'], fallback: true),
    version: asInt(json['version']) ?? 1,
    config: json['config'] is Map<String, dynamic>
        ? DashboardBlockConfig.fromJson(json['config'] as Map<String, dynamic>)
        : const DashboardBlockConfig(),
  );

  final String id;
  final String type;
  final String title;
  final num x;
  final num y;
  final num width;
  final num height;
  final bool visible;
  final int version;
  final DashboardBlockConfig config;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'title': title,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'visible': visible,
    'version': version,
    'config': config.toJson(),
  };
}

/// A saved per-user dashboard layout — `DashboardLayout.ts`. The `blocks`
/// column arrives as a JSON array, already parsed by the server's
/// `parseRow` before it reaches the envelope.
class DashboardLayout {
  const DashboardLayout({
    required this.id,
    required this.userId,
    required this.layoutName,
    required this.blocks,
    this.isActive = false,
    this.createdAt = '',
    this.updatedAt = '',
  });

  factory DashboardLayout.fromJson(Map<String, dynamic> json) =>
      DashboardLayout(
        id: asInt(json['id']) ?? 0,
        userId: asInt(json['user_id']) ?? 0,
        layoutName: asString(json['layout_name']) ?? '',
        blocks: _parseList(json['blocks'], DashboardBlock.fromJson),
        isActive: asBool(json['is_active']),
        createdAt: asString(json['created_at']) ?? '',
        updatedAt: asString(json['updated_at']) ?? '',
      );

  final int id;
  final int userId;
  final String layoutName;
  final List<DashboardBlock> blocks;
  final bool isActive;
  final String createdAt;
  final String updatedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'layout_name': layoutName,
    'blocks': [for (final block in blocks) block.toJson()],
    'is_active': isActive,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  /// Parses a JSON array of objects into typed blocks, skipping junk rows.
  static List<T> _parseList<T>(
    Object? value,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item is Map<String, dynamic>) fromJson(item),
    ];
  }
}
