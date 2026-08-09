/// System setting model — shape from `GET /api/settings` (PORTING.md §13):
/// a *bare* object map `{ key: {value, description, updated_at} }` with no
/// envelope. Values are always strings (the server stores everything as
/// TEXT); `updated_at` arrives as a SQLite timestamp string.
library;

import 'json_helpers.dart';

class AppSetting {
  const AppSetting({
    required this.key,
    required this.value,
    this.description,
    this.updatedAt,
  });

  factory AppSetting.fromJson(String key, Map<String, dynamic> json) =>
      AppSetting(
        key: key,
        value: asString(json['value']) ?? '',
        description: asString(json['description']),
        updatedAt: asString(json['updated_at']),
      );

  final String key;
  final String value;
  final String? description;
  final String? updatedAt;
}
