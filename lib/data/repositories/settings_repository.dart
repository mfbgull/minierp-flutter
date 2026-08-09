// Settings repository — typed against `server/src/controllers/settingsController.ts`
// (PORTING.md §13). Every endpoint returns a *bare* body (no envelope):
//
//   GET  /settings        → {key: {value, description, updated_at}, …}
//   GET  /settings/:key   → {key, value, description, updated_at}
//   PUT  /settings/:key   → body {value, description} → updated setting
//   POST /settings/bulk   → body {key: value} (or {key: {value, …}}) → all settings
//
// Wired through the client's `getRaw` / `putRaw` / `postRaw` helpers. The
// screen saves whole groups atomically via the bulk endpoint (the server
// runs it in a transaction).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart' show dioProvider;
import '../../core/api/endpoints.dart' show ApiEndpoints;
import '../models/setting.dart' show AppSetting;
import 'api_result.dart';
import 'repository_client.dart';

class SettingsRepository {
  SettingsRepository(this._api);

  final RepositoryClient _api;

  /// Parses the bare `{key: {value, description, updated_at}}` body into an
  /// ordered map (server row order). Non-object entries are skipped.
  Map<String, AppSetting> _parseAll(Object? json) {
    if (json is! Map<String, dynamic>) return const {};
    return {
      for (final entry in json.entries)
        if (entry.value is Map<String, dynamic>)
          entry.key: AppSetting.fromJson(
            entry.key,
            entry.value as Map<String, dynamic>,
          ),
    };
  }

  /// Full key-value store.
  Future<ApiResult<Map<String, AppSetting>>> all() => _api.getRaw(
    ApiEndpoints.settings,
    parse: _parseAll,
  );

  /// Atomic multi-key update (`POST /settings/bulk`). The response is the
  /// refreshed full settings map, which callers use to re-sync local state.
  Future<ApiResult<Map<String, AppSetting>>> updateBulk(
    Map<String, String> values,
  ) => _api.postRaw(
    '${ApiEndpoints.settings}/bulk',
    body: values,
    parse: _parseAll,
  );
}

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(RepositoryClient(ref.watch(dioProvider))),
);
