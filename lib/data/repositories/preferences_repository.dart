// Preferences repository — typed against the Phase 1 server endpoints
// (date-range-picker-spec.md §6.1):
//
//   GET /api/preferences → {weekStart, defaultRange, presets}
//   PUT /api/preferences → partial update (absent fields keep their
//     current value; `defaultRange: null` clears it) → saved merged object
//
// Both return the standard `{success, data}` envelope, so the shared
// RepositoryClient's `get`/`put` helpers apply.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/endpoints.dart' show ApiEndpoints;
import '../../core/utils/date_range_math.dart' show DateRange, WeekStart;
import '../../core/utils/date_utils.dart' show isoDate;
import '../models/user_preferences.dart'
    show UserPreset, UserPreferences;
import 'api_result.dart';
import 'repository_client.dart';

class PreferencesRepository {
  PreferencesRepository(this._api);

  final RepositoryClient _api;

  /// GET /api/preferences — the current user's saved preferences
  /// (server defaults when no row exists yet).
  Future<ApiResult<UserPreferences>> get() => _api.get(
    ApiEndpoints.preferences,
    parse: (Object? json) =>
        UserPreferences.fromJson(json as Map<String, dynamic>),
  );

  /// PUT /api/preferences — partial update; only the supplied fields are
  /// sent, everything else keeps its current value on the server.
  ///
  /// [defaultRange] sets the saved range; [clearDefaultRange] sends an
  /// explicit `null` to clear it (the two are mutually exclusive — pass
  /// only one).
  Future<ApiResult<UserPreferences>> update({
    WeekStart? weekStart,
    DateRange? defaultRange,
    bool clearDefaultRange = false,
    List<UserPreset>? presets,
  }) {
    final body = <String, dynamic>{};
    if (weekStart != null) body['weekStart'] = weekStart.name;
    if (clearDefaultRange) {
      body['defaultRange'] = null;
    } else if (defaultRange != null) {
      body['defaultRange'] = {
        'from': isoDate(defaultRange.from),
        'to': isoDate(defaultRange.to),
      };
    }
    if (presets != null) {
      body['presets'] = [for (final preset in presets) preset.toJson()];
    }
    return _api.put(
      ApiEndpoints.preferences,
      body: body,
      parse: (Object? json) =>
          UserPreferences.fromJson(json as Map<String, dynamic>),
    );
  }
}

final preferencesRepositoryProvider = Provider<PreferencesRepository>(
  (ref) => PreferencesRepository(ref.watch(repositoryClientProvider)),
);
