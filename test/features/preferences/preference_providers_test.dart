// Phase 2 tests — the date-range preference client
// (date-range-picker-spec.md §6.2 / tasks T2.1–T2.2):
//
//   - PreferencesCache: defaults on empty store, restore from stored
//     values, write-through persistence, defensive decode of corrupt
//     blobs.
//   - PreferencesRepository: GET parse + partial PUT body shapes
//     (including the explicit-null defaultRange clear).
//   - Providers: StateProviders seed synchronously from the cache;
//     userPreferencesProvider adopts the server response as truth
//     (cache + StateProviders); a failed fetch keeps the cached seed.
//   - saveWeekStart: write-through + PUT; a failed PUT keeps the local
//     value and returns the ApiError for the caller to toast.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/core/api/api_client.dart' show dioProvider;
import 'package:minierp_app/core/utils/date_range_math.dart' show WeekStart;
import 'package:minierp_app/data/models/user_preferences.dart'
    show UserPreset, UserPreferences;
import 'package:minierp_app/data/repositories/api_result.dart'
    show ApiError, ApiSuccess;
import 'package:minierp_app/data/repositories/preferences_repository.dart'
    show PreferencesRepository;
import 'package:minierp_app/data/repositories/repository_client.dart'
    show RepositoryClient;
import 'package:minierp_app/features/preferences/preference_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory fake for GET/PUT /api/preferences. Mirrors the server's
/// partial-merge PUT semantics so round-trips behave realistically.
class _PrefsFakeAdapter implements HttpClientAdapter {
  _PrefsFakeAdapter({Map<String, dynamic>? prefs})
    : prefs = prefs ??
          {
            'weekStart': 'monday',
            'defaultRange': null,
            'presets': <Object>[],
          };

  Map<String, dynamic> prefs;
  Map<String, dynamic>? lastPutBody;
  bool rejectPut = false;
  bool rejectGet = false;

  /// When set, the GET response waits for this completer (used to test
  /// the boot-fetch/save race).
  Completer<void>? gateGet;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path == '/preferences' && options.method == 'GET') {
      final gate = gateGet;
      if (gate != null) await gate.future;
      if (rejectGet) return _json({'error': 'Failed to fetch'}, status: 500);
      return _json({'success': true, 'data': prefs});
    }
    if (options.path == '/preferences' && options.method == 'PUT') {
      if (rejectPut) {
        return _json({
          'success': false,
          'error': {'code': 'X', 'message': 'boom'},
        }, status: 400);
      }
      lastPutBody = options.data as Map<String, dynamic>;
      // Partial merge — absent keys keep their current value, explicit
      // nulls land as null (mirrors preferencesController.ts).
      prefs = {...prefs, ...lastPutBody!};
      return _json({'success': true, 'data': prefs});
    }
    return _json({
      'success': false,
      'error': {'code': 'NOT_FOUND', 'message': 'Not found'},
    }, status: 404);
  }

  ResponseBody _json(Object body, {int status = 200}) => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
  );
}

Dio _dio(HttpClientAdapter adapter) =>
    Dio(BaseOptions(baseUrl: 'http://localhost:3011/api'))
      ..httpClientAdapter = adapter;

/// Minimal Consumer widget that runs a save helper and reports the
/// result — the helpers take a `WidgetRef`, which only exists inside a
/// widget tree.
class _SaveHarness extends ConsumerWidget {
  const _SaveHarness({required this.action, required this.onResult});

  final Future<ApiError?> Function(WidgetRef ref) action;
  final ValueChanged<ApiError?> onResult;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ElevatedButton(
      onPressed: () async {
        onResult(await action(ref));
      },
      child: const Text('save'),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PreferencesCache', () {
    test('starts at the server defaults when nothing is stored', () async {
      SharedPreferences.setMockInitialValues({});
      final cache = await PreferencesCache.load();
      expect(cache.weekStart, WeekStart.monday);
      expect(cache.defaultRange, isNull);
      expect(cache.presets, isEmpty);
    });

    test('restores stored values and write-through persists them', () async {
      SharedPreferences.setMockInitialValues({
        'pref_week_start': 'saturday',
        'pref_default_range':
            '{"from":"2026-08-03","to":"2026-08-09"}',
        'pref_presets':
            '[{"id":"q1","name":"Q1","from":"2026-01-01","to":"2026-03-31"}]',
      });
      final cache = await PreferencesCache.load();
      expect(cache.weekStart, WeekStart.saturday);
      expect(cache.defaultRange?.from, DateTime(2026, 8, 3));
      expect(cache.defaultRange?.to, DateTime(2026, 8, 9));
      expect(cache.presets.single.name, 'Q1');

      // Write-through: an in-memory change is immediately visible and
      // survives a fresh load (new SharedPreferences instance).
      cache.setWeekStart(WeekStart.sunday);
      cache.setDefaultRange(null);
      final reloaded = await PreferencesCache.load();
      expect(reloaded.weekStart, WeekStart.sunday);
      expect(reloaded.defaultRange, isNull);
      expect(reloaded.presets.single.id, 'q1');
    });

    test('corrupt blobs degrade to defaults instead of throwing', () async {
      SharedPreferences.setMockInitialValues({
        'pref_week_start': 'friday', // not in the whitelist
        'pref_default_range': '{not json',
        'pref_presets': '"just a string"',
      });
      final cache = await PreferencesCache.load();
      expect(cache.weekStart, WeekStart.monday); // whitelist fallback
      expect(cache.defaultRange, isNull); // corrupt JSON → no range
      expect(cache.presets, isEmpty); // non-list → empty
    });
  });

  group('PreferencesRepository', () {
    test('GET parses the envelope into UserPreferences', () async {
      final adapter = _PrefsFakeAdapter(prefs: {
        'weekStart': 'saturday',
        'defaultRange': {'from': '2026-08-03', 'to': '2026-08-09'},
        'presets': [
          {'id': 'q1', 'name': 'Q1', 'from': '2026-01-01', 'to': '2026-03-31'},
        ],
      });
      final repo = PreferencesRepository(RepositoryClient(_dio(adapter)));

      final result = await repo.get();
      expect(result, isA<ApiSuccess>());
      final prefs = (result as ApiSuccess<UserPreferences>).data;
      expect(prefs.weekStart, WeekStart.saturday);
      expect(prefs.defaultRange?.from, DateTime(2026, 8, 3));
      expect(prefs.presets.single.id, 'q1');
    });

    test('PUT sends only the supplied fields (partial update)', () async {
      final adapter = _PrefsFakeAdapter();
      final repo = PreferencesRepository(RepositoryClient(_dio(adapter)));

      final result = await repo.update(weekStart: WeekStart.sunday);
      expect(result, isA<ApiSuccess>());
      expect(adapter.lastPutBody, {'weekStart': 'sunday'});

      await repo.update(
        defaultRange: (from: DateTime(2026, 8, 3), to: DateTime(2026, 8, 9)),
      );
      expect(adapter.lastPutBody?['defaultRange'], {
        'from': '2026-08-03',
        'to': '2026-08-09',
      });

      // Explicit clear sends `defaultRange: null` (not "absent").
      await repo.update(defaultRange: null, clearDefaultRange: true);
      expect(adapter.lastPutBody, {'defaultRange': null});

      // No fields supplied → empty body (keeps everything on the server).
      await repo.update();
      expect(adapter.lastPutBody, isEmpty);
    });
  });

  group('UserPreferences model', () {
    test('malformed preset rows are skipped, not fabricated', () {
      final prefs = UserPreferences.fromJson({
        'weekStart': 'monday',
        'defaultRange': null,
        'presets': [
          {'id': 'ok', 'name': 'OK', 'from': '2026-01-01', 'to': '2026-03-31'},
          {'id': '', 'name': 'Empty id', 'from': '2026-01-01', 'to': '2026-03-31'},
          {'id': 'no-dates', 'name': 'No dates', 'from': null, 'to': null},
          'not-a-map',
        ],
      });
      expect(prefs.presets.length, 1);
      expect(prefs.presets.single.id, 'ok');
    });
  });

  group('preference providers', () {
    test('StateProviders seed synchronously from the cache override', () {
      final container = ProviderContainer(
        overrides: [
          preferencesCacheProvider.overrideWithValue(
            PreferencesCache(
              weekStart: WeekStart.saturday,
              defaultRange: (
                from: DateTime(2026, 8, 3),
                to: DateTime(2026, 8, 9),
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      // First reads — no await, no network.
      expect(container.read(weekStartProvider), WeekStart.saturday);
      expect(
        container.read(activeDefaultRangeProvider)?.from,
        DateTime(2026, 8, 3),
      );
      expect(container.read(userPresetsProvider), isEmpty);
    });

    test(
      'initialRange-seeded pairs keep committed state when prefs change',
      () {
        final container = ProviderContainer(
          overrides: [
            preferencesCacheProvider.overrideWithValue(PreferencesCache()),
          ],
        );
        addTearDown(container.dispose);

        // A From/To pair seeded like every report/list screen (no saved
        // default → This week at seed time).
        final from = StateProvider<DateTime?>(
          (ref) => initialRange(ref).from,
        );
        final to = StateProvider<DateTime?>((ref) => initialRange(ref).to);
        expect(container.read(from), isNotNull);
        expect(container.read(to), isNotNull);

        // The user commits a custom range…
        final custom = DateTime(2026, 5, 1);
        container.read(from.notifier).state = custom;
        expect(container.read(from), custom);

        // …then toggles the week-start in the picker footer. The seeded
        // provider must NOT reset to the re-derived seed (Phase 4
        // regression: initialRange used ref.watch, which re-ran the
        // StateProvider initializer and clobbered committed ranges).
        container.read(weekStartProvider.notifier).state =
            WeekStart.saturday;
        expect(container.read(from), custom);

        // Server prefs arriving at boot (with a saved default range)
        // must not reset a committed range either.
        container.read(activeDefaultRangeProvider.notifier).state = (
          from: DateTime(2026, 8, 3),
          to: DateTime(2026, 8, 9),
        );
        expect(container.read(from), custom);
      },
    );

    test('userPreferencesProvider adopts the server response as truth',
        () async {
      final adapter = _PrefsFakeAdapter(prefs: {
        'weekStart': 'sunday',
        'defaultRange': {'from': '2026-08-10', 'to': '2026-08-16'},
        'presets': [
          {'id': 'p1', 'name': 'Pay week', 'from': '2026-08-10', 'to': '2026-08-16'},
        ],
      });
      final cache = PreferencesCache(weekStart: WeekStart.monday);
      final container = ProviderContainer(
        overrides: [
          dioProvider.overrideWithValue(_dio(adapter)),
          preferencesCacheProvider.overrideWithValue(cache),
        ],
      );
      addTearDown(container.dispose);

      final prefs = await container.read(userPreferencesProvider.future);
      expect(prefs.weekStart, WeekStart.sunday);
      // Server truth landed in the StateProviders and the cache.
      expect(container.read(weekStartProvider), WeekStart.sunday);
      expect(
        container.read(activeDefaultRangeProvider)?.to,
        DateTime(2026, 8, 16),
      );
      expect(container.read(userPresetsProvider).single.id, 'p1');
      expect(cache.weekStart, WeekStart.sunday);
      expect(cache.presets.single.id, 'p1');
    });

    test('boot fetch does not clobber a save that lands in flight',
        () async {
      final adapter = _PrefsFakeAdapter(prefs: {
        'weekStart': 'sunday',
        'defaultRange': null,
        'presets': <Object>[],
      })..gateGet = Completer<void>();
      final cache = PreferencesCache(weekStart: WeekStart.monday);
      final container = ProviderContainer(
        overrides: [
          dioProvider.overrideWithValue(_dio(adapter)),
          preferencesCacheProvider.overrideWithValue(cache),
        ],
      );
      addTearDown(container.dispose);

      // Boot fetch starts (gated so it cannot resolve yet)…
      final future = container.read(userPreferencesProvider.future);
      // …a user save lands while the GET is in flight…
      cache.setWeekStart(WeekStart.saturday);
      container.read(weekStartProvider.notifier).state = WeekStart.saturday;
      // …then the stale GET (sunday) resolves.
      adapter.gateGet!.complete();
      await future;

      // The stale response must NOT overwrite the just-saved value.
      expect(container.read(weekStartProvider), WeekStart.saturday);
      expect(cache.weekStart, WeekStart.saturday);
    });

    test('a failed fetch keeps the cached seed', () async {
      final adapter = _PrefsFakeAdapter()..rejectGet = true;
      final cache = PreferencesCache(
        weekStart: WeekStart.saturday,
        defaultRange: (
          from: DateTime(2026, 8, 3),
          to: DateTime(2026, 8, 9),
        ),
      );
      final container = ProviderContainer(
        overrides: [
          dioProvider.overrideWithValue(_dio(adapter)),
          preferencesCacheProvider.overrideWithValue(cache),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(userPreferencesProvider.future),
        throwsA(isA<ApiError>()),
      );
      // Nothing adopted — the seed still stands.
      expect(container.read(weekStartProvider), WeekStart.saturday);
      expect(cache.weekStart, WeekStart.saturday);
    });
  });

  group('saveWeekStart', () {
    testWidgets('writes through locally and PUTs to the server',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final adapter = _PrefsFakeAdapter();
      ApiError? error;
      var completed = false;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dioProvider.overrideWithValue(_dio(adapter)),
            preferencesCacheProvider.overrideWithValue(
              await PreferencesCache.load(),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: _SaveHarness(
                action: (ref) => saveWeekStart(ref, WeekStart.sunday),
                onResult: (e) {
                  error = e;
                  completed = true;
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('save'));
      await tester.pumpAndSettle();

      expect(completed, isTrue);
      expect(error, isNull);
      expect(adapter.lastPutBody, {'weekStart': 'sunday'});
      final container = ProviderScope.containerOf(
        tester.element(find.byType(_SaveHarness)),
      );
      expect(container.read(weekStartProvider), WeekStart.sunday);
      expect(
        container.read(preferencesCacheProvider).weekStart,
        WeekStart.sunday,
      );
    });

    testWidgets('saveDefaultRange writes through and sends the range',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final adapter = _PrefsFakeAdapter();
      ApiError? error;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dioProvider.overrideWithValue(_dio(adapter)),
            preferencesCacheProvider.overrideWithValue(
              await PreferencesCache.load(),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: _SaveHarness(
                action: (ref) => saveDefaultRange(
                  ref,
                  (from: DateTime(2026, 8, 3), to: DateTime(2026, 8, 9)),
                ),
                onResult: (e) => error = e,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('save'));
      await tester.pumpAndSettle();

      expect(error, isNull);
      expect(adapter.lastPutBody?['defaultRange'], {
        'from': '2026-08-03',
        'to': '2026-08-09',
      });
      final container = ProviderScope.containerOf(
        tester.element(find.byType(_SaveHarness)),
      );
      expect(
        container.read(activeDefaultRangeProvider)?.from,
        DateTime(2026, 8, 3),
      );
    });

    testWidgets('saveDefaultRange null clears via an explicit null PUT',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final adapter = _PrefsFakeAdapter(prefs: {
        'weekStart': 'monday',
        'defaultRange': {'from': '2026-08-03', 'to': '2026-08-09'},
        'presets': <Object>[],
      });
      ApiError? error;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dioProvider.overrideWithValue(_dio(adapter)),
            preferencesCacheProvider.overrideWithValue(
              await PreferencesCache.load(),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: _SaveHarness(
                action: (ref) => saveDefaultRange(ref, null),
                onResult: (e) => error = e,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('save'));
      await tester.pumpAndSettle();

      expect(error, isNull);
      expect(adapter.lastPutBody, {'defaultRange': null});
      final container = ProviderScope.containerOf(
        tester.element(find.byType(_SaveHarness)),
      );
      expect(container.read(activeDefaultRangeProvider), isNull);
    });

    testWidgets('saveUserPresets writes through and sends the presets',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final adapter = _PrefsFakeAdapter();
      ApiError? error;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dioProvider.overrideWithValue(_dio(adapter)),
            preferencesCacheProvider.overrideWithValue(
              await PreferencesCache.load(),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: _SaveHarness(
                action: (ref) => saveUserPresets(ref, [
                  UserPreset(
                    id: 'q1',
                    name: 'Q1',
                    from: DateTime(2026, 1, 1),
                    to: DateTime(2026, 3, 31),
                  ),
                ]),
                onResult: (e) => error = e,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('save'));
      await tester.pumpAndSettle();

      expect(error, isNull);
      expect(adapter.lastPutBody?['presets'], [
        {'id': 'q1', 'name': 'Q1', 'from': '2026-01-01', 'to': '2026-03-31'},
      ]);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(_SaveHarness)),
      );
      expect(container.read(userPresetsProvider).single.id, 'q1');
    });

    testWidgets('a failed PUT keeps the local value and returns the error',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final adapter = _PrefsFakeAdapter()..rejectPut = true;
      ApiError? error;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dioProvider.overrideWithValue(_dio(adapter)),
            preferencesCacheProvider.overrideWithValue(
              await PreferencesCache.load(),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: _SaveHarness(
                action: (ref) => saveWeekStart(ref, WeekStart.sunday),
                onResult: (e) => error = e,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('save'));
      await tester.pumpAndSettle();

      expect(error, isNotNull);
      expect(error!.message, 'boom');
      final container = ProviderScope.containerOf(
        tester.element(find.byType(_SaveHarness)),
      );
      // Local value kept despite the failure (server never adopted).
      expect(container.read(weekStartProvider), WeekStart.sunday);
      expect(
        container.read(preferencesCacheProvider).weekStart,
        WeekStart.sunday,
      );
    });
  });
}
