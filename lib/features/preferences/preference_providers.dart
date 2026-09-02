// Date-range preference providers (date-range-picker-spec.md §6.2).
//
// Contract: **local cache = seed, server = truth.**
//
// - `PreferencesCache` is a synchronous, SharedPreferences-backed holder
//   for the week start / default range / user presets. `main()` preloads
//   it before `runApp` and overrides [preferencesCacheProvider], so every
//   `StateProvider` initializer below reads its seed value synchronously
//   on first build (before any network round-trip).
// - [userPreferencesProvider] fires `GET /api/preferences` at shell boot
//   (AppShell watches it). On success its values are adopted into the
//   cache + the StateProviders; on failure the cached seed stays.
// - Writes (`saveWeekStart` / `saveDefaultRange` / `saveUserPresets`)
//   update local state + the cache immediately (write-through), then PUT
//   to the server; a failed PUT keeps the local value and returns the
//   [ApiError] for the caller to toast (app conventions: no silent
//   failures).

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/date_range_math.dart'
    show DatePreset, DateRange, WeekStart, presetRange;
import '../../core/utils/date_utils.dart' show isoDate;
import '../../data/models/user_preferences.dart'
    show UserPreset, UserPreferences;
import '../../data/repositories/api_result.dart'
    show ApiError, ApiFailure, ApiSuccess;
import '../../data/repositories/preferences_repository.dart'
    show preferencesRepositoryProvider;

/// Synchronous SharedPreferences-backed cache of the user's date-range
/// preferences. Constructed in `main()` (see lib/main.dart) after
/// `SharedPreferences.getInstance()` resolves and injected via
/// [preferencesCacheProvider]; without an override (widget tests) it
/// starts at the server defaults.
class PreferencesCache {
  PreferencesCache({
    this._prefs,
    this.weekStart = WeekStart.monday,
    this.defaultRange,
    List<UserPreset>? presets,
  }) : presets = presets ?? const [];

  static const _weekStartKey = 'pref_week_start';
  static const _defaultRangeKey = 'pref_default_range';
  static const _presetsKey = 'pref_presets';

  final SharedPreferences? _prefs;

  WeekStart weekStart;
  DateRange? defaultRange;
  List<UserPreset> presets;

  /// Bumped by every local write (setWeekStart/setDefaultRange/setPresets
  /// and [reset]). The boot fetch compares its start value against this
  /// before adopting, so a user save that lands while the GET is in
  /// flight is never clobbered by the stale server response.
  int revision = 0;

  /// Loads the cache from SharedPreferences. Storage failures degrade to
  /// the defaults rather than crashing boot (token_storage pattern).
  static Future<PreferencesCache> load() async {
    final prefs = await SharedPreferences.getInstance();
    final cache = PreferencesCache(prefs: prefs);
    cache._restore(prefs);
    return cache;
  }

  void _restore(SharedPreferences prefs) {
    weekStart = _wireToWeekStart(prefs.getString(_weekStartKey));
    defaultRange = _decodeRange(prefs.getString(_defaultRangeKey));
    presets = _decodePresets(prefs.getString(_presetsKey));
  }

  /// Write-through: updates the in-memory value immediately (so providers
  /// read it synchronously) and persists fire-and-forget. A storage write
  /// failure only affects the next boot — the session value is already set.
  void setWeekStart(WeekStart value) {
    weekStart = value;
    revision++;
    _persist(_weekStartKey, value.name);
  }

  void setDefaultRange(DateRange? value) {
    defaultRange = value;
    revision++;
    _persist(
      _defaultRangeKey,
      value == null
          ? null
          : jsonEncode({
              'from': isoDate(value.from),
              'to': isoDate(value.to),
            }),
    );
  }

  void setPresets(List<UserPreset> value) {
    presets = List.unmodifiable(value);
    revision++;
    _persist(
      _presetsKey,
      jsonEncode([for (final preset in value) preset.toJson()]),
    );
  }

  /// Resets every value to the server defaults and clears the stored
  /// keys — called on logout so the next user doesn't inherit the
  /// previous user's preferences before their own fetch lands.
  Future<void> reset() async {
    weekStart = WeekStart.monday;
    defaultRange = null;
    presets = const [];
    revision++;
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      await Future.wait([
        prefs.remove(_weekStartKey),
        prefs.remove(_defaultRangeKey),
        prefs.remove(_presetsKey),
      ]);
    } catch (_) {
      // Storage unavailable — the in-memory reset still applies.
    }
  }

  void _persist(String key, String? value) {
    final prefs = _prefs;
    if (prefs == null) return;
    unawaited(_write(prefs, key, value));
  }

  Future<void> _write(SharedPreferences prefs, String key, String? value) async {
    try {
      if (value == null) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, value);
      }
    } catch (_) {
      // Storage unavailable — in-memory value still applies this session.
    }
  }

  WeekStart _wireToWeekStart(String? value) => switch (value) {
    'saturday' => WeekStart.saturday,
    'sunday' => WeekStart.sunday,
    _ => WeekStart.monday,
  };

  /// Decodes a cached `{from, to}` JSON string; any corrupt blob returns
  /// null (treat as "no default range") instead of throwing.
  DateRange? _decodeRange(String? raw) {
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw);
      if (map is! Map<String, dynamic>) return null;
      final from = DateTime.tryParse('${map['from']}');
      final to = DateTime.tryParse('${map['to']}');
      if (from == null || to == null) return null;
      return (from: from, to: to);
    } catch (_) {
      return null;
    }
  }

  /// Decodes a cached presets JSON array; corrupt blobs and malformed
  /// rows are skipped, so nothing is ever fabricated.
  List<UserPreset> _decodePresets(String? raw) {
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      final presets = <UserPreset>[];
      for (final row in list) {
        if (row is Map<String, dynamic>) {
          final preset = UserPreset.tryFromJson(row);
          if (preset != null) presets.add(preset);
        }
      }
      return presets;
    } catch (_) {
      return const [];
    }
  }
}

/// The boot-loaded cache — `main()` overrides this with the preloaded
/// instance; widget tests fall back to a defaults-only cache.
final preferencesCacheProvider = Provider<PreferencesCache>(
  (ref) => PreferencesCache(),
);

/// Active week-start day (monday default). Seeded synchronously from the
/// cache; [userPreferencesProvider] syncs it with the server on boot.
final weekStartProvider = StateProvider<WeekStart>(
  (ref) => ref.watch(preferencesCacheProvider).weekStart,
);

/// The saved default report range (null = none). Report/list screens seed
/// their From/To from this in Phase 4; kept here so the boot cache is the
/// single seeding source.
final activeDefaultRangeProvider = StateProvider<DateRange?>(
  (ref) => ref.watch(preferencesCacheProvider).defaultRange,
);

/// The initial From/To range for report and list screens (spec §6.2 / Q17):
/// the saved default range when one is set, else the **"This week"** preset
/// computed with the saved week start. Reads the boot-seeded StateProviders
/// synchronously, so a screen's first frame already shows the seeded range
/// with no network round-trip — and the seeding follows the user's saved
/// default from the very first build.
///
/// Uses `ref.read` (not `ref.watch`) deliberately: a StateProvider's
/// initializer re-runs when a provider it watches changes, which would
/// recreate its state and **reset the committed range to the re-derived
/// seed** — e.g. toggling the week-start in the picker footer or the server
/// preferences arriving at boot would clobber every screen's selection.
/// Read captures the seed once, at first build; a *server-only* saved
/// default (fresh device whose local cache has none) takes effect on the
/// next boot, since the cache is the seeding source (§6.2).
DateRange initialRange(Ref ref) {
  final saved = ref.read(activeDefaultRangeProvider);
  if (saved != null) return saved;
  return presetRange(
    DatePreset.thisMonth,
    DateTime.now(),
    ref.read(weekStartProvider),
  );
}

/// User-defined presets (server `presets` array is the source of truth;
/// the picker sidebar renders this for the ✕-remove + active matching).
final userPresetsProvider = StateProvider<List<UserPreset>>(
  (ref) => ref.watch(preferencesCacheProvider).presets,
);

/// GET /api/preferences — fired at shell boot. On success the server
/// response is written into the cache and the StateProviders (server =
/// truth); on failure the cached seed stands and the error is held here.
final userPreferencesProvider = FutureProvider<UserPreferences>((ref) async {
  // Guard against the boot-fetch/save race: a user save that lands while
  // the GET is in flight bumps the cache revision, so a stale server
  // response never clobbers the just-saved value.
  final revisionAtStart = ref.read(preferencesCacheProvider).revision;
  final result = await ref.watch(preferencesRepositoryProvider).get();
  return switch (result) {
    ApiSuccess(:final data) =>
      ref.read(preferencesCacheProvider).revision == revisionAtStart
          ? _adopt(ref.container, data)
          : data,
    ApiFailure(:final error) => throw error,
  };
});

/// Adopts the server's [prefs] as truth at the container level: updates
/// the cache (write-through) and every preference StateProvider, then
/// returns [prefs] unchanged. Reached from both the boot fetch (via
/// `Ref.container`) and the UI save helpers (via `WidgetRef.context` →
/// `ProviderScope.containerOf`) — `Ref` and `WidgetRef` are unrelated
/// types in Riverpod 2, so the container is the shared seam.
UserPreferences _adopt(ProviderContainer container, UserPreferences prefs) {
  final cache = container.read(preferencesCacheProvider);
  cache
    ..setWeekStart(prefs.weekStart)
    ..setDefaultRange(prefs.defaultRange)
    ..setPresets(prefs.presets);
  container.read(weekStartProvider.notifier).state = prefs.weekStart;
  container.read(activeDefaultRangeProvider.notifier).state = prefs.defaultRange;
  container.read(userPresetsProvider.notifier).state = prefs.presets;
  return prefs;
}

/// Resets the per-user preference state to the server defaults and
/// invalidates the boot fetch — called on logout so the next login never
/// shows the previous user's week start / default range / presets, even
/// before the new user's GET /api/preferences resolves.
void resetUserPreferences(WidgetRef ref) {
  ref.read(weekStartProvider.notifier).state = WeekStart.monday;
  ref.read(activeDefaultRangeProvider.notifier).state = null;
  ref.read(userPresetsProvider.notifier).state = const [];
  ref.read(preferencesCacheProvider).reset();
  ref.invalidate(userPreferencesProvider);
}

/// Persists a week-start change: local state + cache update immediately
/// (write-through), then PUT; on failure the local value is kept and the
/// [ApiError] returned so the caller can toast it.
Future<ApiError?> saveWeekStart(WidgetRef ref, WeekStart value) async {
  final container = ProviderScope.containerOf(ref.context);
  ref.read(weekStartProvider.notifier).state = value;
  ref.read(preferencesCacheProvider).setWeekStart(value);
  final result = await ref.read(preferencesRepositoryProvider).update(
    weekStart: value,
  );
  switch (result) {
    case ApiSuccess(:final data):
      _adopt(container, data);
      return null;
    case ApiFailure(:final error):
      return error;
  }
}

/// Persists the default range (null clears it). Same write-through
/// contract as [saveWeekStart].
Future<ApiError?> saveDefaultRange(WidgetRef ref, DateRange? range) async {
  final container = ProviderScope.containerOf(ref.context);
  ref.read(activeDefaultRangeProvider.notifier).state = range;
  ref.read(preferencesCacheProvider).setDefaultRange(range);
  final result = await ref.read(preferencesRepositoryProvider).update(
    defaultRange: range,
    clearDefaultRange: range == null,
  );
  switch (result) {
    case ApiSuccess(:final data):
      _adopt(container, data);
      return null;
    case ApiFailure(:final error):
      return error;
  }
}

/// Persists the user-defined presets list. Same write-through contract.
Future<ApiError?> saveUserPresets(WidgetRef ref, List<UserPreset> presets) async {
  final container = ProviderScope.containerOf(ref.context);
  ref.read(userPresetsProvider.notifier).state = presets;
  ref.read(preferencesCacheProvider).setPresets(presets);
  final result = await ref.read(preferencesRepositoryProvider).update(
    presets: presets,
  );
  switch (result) {
    case ApiSuccess(:final data):
      _adopt(container, data);
      return null;
    case ApiFailure(:final error):
      return error;
  }
}
