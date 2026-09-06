// Typed wrapper over the shared Dio client that understands the server
// response variants (PORTING.md §2):
//
// - Enveloped:  `{success: true, data}` / `{success: false, error}` →
//   `get` / `getList` / `getPaged` / `post` / `put` / `delete`.
// - Bare object: detail/create/update endpoints that return the entity
//   directly without the envelope (item detail/create/update,
//   `GET /invoices/:id`) → `getRaw` / `postRaw` / `putRaw`.
// - Bare array:  reference endpoints (`items-categories`, `items-uom`) →
//   `getRawList`.
// - Paged:       enveloped lists with a `pagination` block (customers,
//   payments) → `getPaged`.
//
// Timeouts and the Bearer/401 interceptor live on the shared client
// (`core/api/api_client.dart`). Failures map to `ApiError` via the
// existing `mapError` helper so 403/500 `{error}` bodies surface the
// server's message.
//
// Offline cache (SHORTCOMINGS-FIX 4.1): when a [CacheManager] is wired
// in (see [CachedRepositoryClient]), successful GET responses are
// snapshotted under `path?query` keys and served from cache when the
// network is unreachable; writes invalidate the affected read keys.

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart' show dioProvider;
import '../../core/cache/cache_manager.dart' show CacheManager;
import '../../core/utils/error_mapper.dart' show mapError;
import 'api_result.dart';
import 'paged_request.dart';

/// Thrown internally when the server responds `{success: false, error}`
/// or the payload has an unexpected shape.
class ApiResponseException implements Exception {
  ApiResponseException(this.message, this.statusCode);

  final String message;
  final int? statusCode;

  @override
  String toString() => 'ApiResponseException($statusCode): $message';
}

class RepositoryClient {
  RepositoryClient(
    this._dio, {
    CacheManager? cache,
    this.cacheTtl = const Duration(minutes: 5),
    this.ttlForPath = const {},
    // The named `cache` parameter stays public (callers pass it by name)
    // while the field is private.
  }) : _cache = cache; // ignore: prefer_initializing_formals

  final Dio _dio;
  final CacheManager? _cache;

  /// Default TTL for cached reads.
  final Duration cacheTtl;

  /// Per-path TTL overrides (exact-path match), e.g. dashboard endpoints
  /// refresh faster than the item/customer lists. Read-heavy endpoints
  /// that need a different TTL override it per-path via [ttlForPath] in
  /// [CachedRepositoryClient].
  final Map<String, Duration> ttlForPath;

  /// True when the most recent read was served from the offline cache
  /// (server unreachable) — screens render an "Offline" badge off this.
  final ValueNotifier<bool> servingCached = ValueNotifier<bool>(false);

  /* ── Enveloped requests ──────────────────────────────────────── */

  Future<ApiResult<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    required T Function(Object?) parse,
  }) => _parse(
    _guardGet(path, queryParameters, () => _dio.get(path, queryParameters: queryParameters)),
    parse,
  );

  Future<ApiResult<T>> post<T>(
    String path, {
    Object? body,
    required T Function(Object?) parse,
  }) async {
    unawaited(_invalidateFor(path));
    return _parse(_guard(() => _dio.post(path, data: body)), parse);
  }

  /// Enveloped multipart POST — `{success: true, data}` with a
  /// [FormData] body (the employee-document upload posts the metadata
  /// fields plus the `file` part). Same envelope handling as [post];
  /// dio sets the multipart content type from the FormData.
  Future<ApiResult<T>> postMultipart<T>(
    String path, {
    required FormData formData,
    required T Function(Object?) parse,
  }) async {
    unawaited(_invalidateFor(path));
    return _parse(_guard(() => _dio.post(path, data: formData)), parse);
  }

  Future<ApiResult<T>> put<T>(
    String path, {
    Object? body,
    required T Function(Object?) parse,
  }) async {
    unawaited(_invalidateFor(path));
    return _parse(_guard(() => _dio.put(path, data: body)), parse);
  }

  /// Enveloped delete — `{success: true, message}`, no data payload.
  Future<ApiResult<void>> delete(String path) async {
    unawaited(_invalidateFor(path));
    final guarded = await _guard(() => _dio.delete(path));
    try {
      return guarded.map<void>((response) {
        _envelopeData(response); // throws on {success: false}
      });
    } on ApiResponseException catch (e) {
      return ApiFailure(ApiError(message: e.message, statusCode: e.statusCode));
    }
  }

  /// Enveloped array response (`{success: true, data: [...]}`).
  Future<ApiResult<List<T>>> getList<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    required T Function(Object?) parseItem,
  }) async {
    final guarded = await _guardGet(
      path,
      queryParameters,
      () => _dio.get(path, queryParameters: queryParameters),
    );
    try {
      return guarded.map((response) {
        final data = _envelopeData(response);
        if (data is! List) {
          throw ApiResponseException(
            'Expected a list response',
            response.statusCode,
          );
        }
        return _parseItems(data, parseItem);
      });
    } on ApiResponseException catch (e) {
      return ApiFailure(ApiError(message: e.message, statusCode: e.statusCode));
    }
  }

  /// Enveloped array + `pagination` block (`GET /customers` shape).
  Future<ApiResult<PagedResponse<T>>> getPaged<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    required T Function(Object?) parseItem,
  }) async {
    final guarded = await _guardGet(
      path,
      queryParameters,
      () => _dio.get(path, queryParameters: queryParameters),
    );
    try {
      return guarded.map((response) {
        final body = response.data;
        final data = _envelopeData(response);
        if (data is! List) {
          throw ApiResponseException(
            'Expected a list response',
            response.statusCode,
          );
        }
        final pagination = body is Map<String, dynamic>
            ? body['pagination']
            : null;
        if (pagination is! Map<String, dynamic>) {
          throw ApiResponseException(
            'Missing pagination block',
            response.statusCode,
          );
        }
        return PagedResponse(
          items: _parseItems(data, parseItem),
          totalItems: _asInt(pagination['totalItems']) ?? 0,
          currentPage: _asInt(pagination['currentPage']) ?? 1,
          totalPages: _asInt(pagination['totalPages']) ?? 1,
          hasNext: pagination['hasNext'] == true,
          hasPrev: pagination['hasPrev'] == true,
        );
      });
    } on ApiResponseException catch (e) {
      return ApiFailure(ApiError(message: e.message, statusCode: e.statusCode));
    }
  }

  /// Enveloped POST whose result lives in the envelope body itself
  /// rather than `data` — e.g. `{success: true, message, deletedCount}`
  /// (the activity-log cleanup shape). The envelope is still validated
  /// like [post], so a `{success: false, error}` body surfaces as an
  /// [ApiFailure] instead of silently parsing to a default.
  Future<ApiResult<T>> postEnvelope<T>(
    String path, {
    Object? body,
    required T Function(Map<String, dynamic> envelope) parse,
  }) async {
    unawaited(_invalidateFor(path));
    final guarded = await _guard(() => _dio.post(path, data: body));
    try {
      return guarded.map((response) {
        final raw = response.data;
        if (raw is! Map<String, dynamic>) {
          throw ApiResponseException(
            'Expected an enveloped response',
            response.statusCode,
          );
        }
        _envelopeData(response); // throws on {success: false, error}
        return parse(raw);
      });
    } on ApiResponseException catch (e) {
      return ApiFailure(ApiError(message: e.message, statusCode: e.statusCode));
    }
  }

  /// Enveloped array + top-level `total/limit/offset` counters
  /// (`GET /activity-logs` shape — no `pagination` block).
  Future<ApiResult<OffsetPagedResponse<T>>> getOffsetPaged<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    required T Function(Object?) parseItem,
  }) async {
    final guarded = await _guardGet(
      path,
      queryParameters,
      () => _dio.get(path, queryParameters: queryParameters),
    );
    try {
      return guarded.map((response) {
        final body = response.data;
        final data = _envelopeData(response);
        if (data is! List) {
          throw ApiResponseException(
            'Expected a list response',
            response.statusCode,
          );
        }
        final meta = body is Map<String, dynamic> ? body : const {};
        return OffsetPagedResponse(
          items: _parseItems(data, parseItem),
          total: _asInt(meta['total']) ?? 0,
          limit: _asInt(meta['limit']) ?? 0,
          offset: _asInt(meta['offset']) ?? 0,
        );
      });
    } on ApiResponseException catch (e) {
      return ApiFailure(ApiError(message: e.message, statusCode: e.statusCode));
    }
  }

  /// GET a bare object (item detail: `{...item, stock_by_warehouse}`).
  /// Unlike [get], the whole response body reaches `parse` unwrapped —
  /// used for envelopes the standard helpers can't express (e.g. the
  /// employees list's `{data, pagination: {page, limit, total,
  /// totalPages}}` block). A `{success: false, error}` body still becomes
  /// an [ApiFailure] when `parse` throws [ApiResponseException].
  Future<ApiResult<T>> getRaw<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    required T Function(Object?) parse,
  }) => _parseRaw(
    _guardGet(path, queryParameters, () => _dio.get(path, queryParameters: queryParameters)),
    parse,
  );

  /// POST returning the created object directly (item create).
  Future<ApiResult<T>> postRaw<T>(
    String path, {
    Object? body,
    required T Function(Object?) parse,
  }) async {
    unawaited(_invalidateFor(path));
    return _parseRaw(_guard(() => _dio.post(path, data: body)), parse);
  }

  /// PUT returning the updated object directly (item update).
  Future<ApiResult<T>> putRaw<T>(
    String path, {
    Object? body,
    required T Function(Object?) parse,
  }) async {
    unawaited(_invalidateFor(path));
    return _parseRaw(_guard(() => _dio.put(path, data: body)), parse);
  }

  /// PATCH returning the updated object directly (BOM toggle-active).
  /// The standard helpers cover the server's GET/POST/PUT/DELETE verbs;
  /// this one exists for the handful of PATCH endpoints.
  Future<ApiResult<T>> patchRaw<T>(
    String path, {
    Object? body,
    required T Function(Object?) parse,
  }) async {
    unawaited(_invalidateFor(path));
    return _parseRaw(_guard(() => _dio.patch(path, data: body)), parse);
  }

  /// DELETE returning a bare body (invoice delete: `{message}` — no
  /// envelope, unlike the enveloped `delete` used by items/customers).
  Future<ApiResult<void>> deleteRaw(String path) async {
    unawaited(_invalidateFor(path));
    final result = await _guard(() => _dio.delete(path));
    return result.map<void>((_) {});
  }

  /// GET a bare array (items-categories, items-uom, stock movements).
  Future<ApiResult<List<T>>> getRawList<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    required T Function(Object?) parseItem,
  }) async {
    final guarded = await _guardGet(
      path,
      queryParameters,
      () => _dio.get(path, queryParameters: queryParameters),
    );
    try {
      return guarded.map((response) {
        final data = response.data;
        if (data is! List) {
          throw ApiResponseException(
            'Expected a list response',
            response.statusCode,
          );
        }
        return _parseItems(data, parseItem);
      });
    } on ApiResponseException catch (e) {
      return ApiFailure(ApiError(message: e.message, statusCode: e.statusCode));
    }
  }

  /* ── Internals ───────────────────────────────────────────────── */

  Future<ApiResult<Response<dynamic>>> _guard(
    Future<Response<dynamic>> Function() request,
  ) async {
    try {
      return ApiSuccess(await request());
    } on DioException catch (e) {
      return ApiFailure(_toError(e));
    }
  }

  /// GET guarded like [_guard] but with the offline-cache layer (spec
  /// 4.1): on success the raw response body is snapshotted under
  /// `path?query`; on a *network* failure the cached body is replayed as
  /// a synthetic [Response] so the caller's envelope/parse logic runs
  /// unchanged. Non-network failures and cache misses pass through as-is.
  /// Server-side errors are never served from cache.
  Future<ApiResult<Response<dynamic>>> _guardGet(
    String path,
    Map<String, dynamic>? queryParameters,
    Future<Response<dynamic>> Function() request,
  ) async {
    final cache = _cache;
    final key = cache == null ? null : _cacheKey(path, queryParameters);
    final guarded = await _guard(request);
    if (guarded case ApiSuccess(:final data)) {
      final body = data.data;
      // Snapshot the raw body (only JSON-safe payloads — the server
      // always returns JSON, so encode only if it round-trips). A cache
      // write must never break the request, so any failure (e.g. the
      // storage plugin missing in tests) is swallowed.
      if (cache != null && key != null && body != null) {
        try {
          final json = jsonEncode(body);
          // Keep the cache small (spec: <10MB): skip oversized bodies.
          if (json.length <= _maxCacheBytes) {
            unawaited(
              cache.put(key, json, ttl: ttlForPath[path] ?? cacheTtl).catchError((_) {}),
            );
          }
        } on JsonUnsupportedObjectError {
          // Non-JSON body (unexpected) — just don't cache it.
        }
      }
      if (servingCached.value) servingCached.value = false;
      return guarded;
    }

    final failure = guarded as ApiFailure<Response<dynamic>>;
    // Serve last-known data only for connectivity failures — a 400/500
    // means the server is up and its answer is authoritative.
    if (failure.error.isNetwork && cache != null && key != null) {
      try {
        final cached = await cache.get(key);
        if (cached != null) {
          try {
            servingCached.value = true;
            return ApiSuccess(
              Response<dynamic>(
                requestOptions: RequestOptions(path: path),
                statusCode: 200,
                data: jsonDecode(cached),
              ),
            );
          } on FormatException {
            // Corrupt entry — fall through to the real failure.
          }
        }
      } catch (_) {
        // Storage plugin unavailable — treat as a cache miss.
      }
    }
    return failure;
  }

  /// Cache key: `path` or `path?k=v&k2=v2` (sorted) so distinct filter
  /// combos cache separately but a write can invalidate by path prefix.
  String? _cacheKey(String path, Map<String, dynamic>? queryParameters) {
    if (queryParameters == null || queryParameters.isEmpty) return path;
    final pairs = queryParameters.entries
        .where((e) => e.value != null)
        .map((e) => '${e.key}=${e.value}')
        .toList()
      ..sort();
    return pairs.isEmpty ? path : '$path?${pairs.join('&')}';
  }

  /// Drops cached reads for [path] and its parent (a write to
  /// `/items/5` invalidates both `/items/5` and `/items?...`).
  Future<void> _invalidateFor(String path) async {
    final cache = _cache;
    if (cache == null) return;
    try {
      await cache.invalidate(path);
      final slash = path.lastIndexOf('/');
      if (slash > 0) {
        await cache.invalidate(path.substring(0, slash));
      }
    } catch (_) {
      // Storage plugin unavailable — nothing to invalidate.
    }
    if (servingCached.value) servingCached.value = false;
  }

  /// Upper bound per cached body — keeps total cache well under the
  /// 10MB acceptance ceiling for the handful of read-heavy endpoints.
  static const int _maxCacheBytes = 256 * 1024;

  Future<ApiResult<T>> _parse<T>(
    Future<ApiResult<Response<dynamic>>> guarded,
    T Function(Object?) parse,
  ) async {
    try {
      final result = await guarded;
      return result.map(
        (response) => _tryParse(_envelopeData(response), parse),
      );
    } on ApiResponseException catch (e) {
      return ApiFailure(ApiError(message: e.message, statusCode: e.statusCode));
    }
  }

  Future<ApiResult<T>> _parseRaw<T>(
    Future<ApiResult<Response<dynamic>>> guarded,
    T Function(Object?) parse,
  ) async {
    try {
      final result = await guarded;
      return result.map((response) => _tryParse(response.data, parse));
    } on ApiResponseException catch (e) {
      return ApiFailure(ApiError(message: e.message, statusCode: e.statusCode));
    }
  }

  /// Runs `parse`, converting cast/type errors into a catchable
  /// `ApiResponseException` so a malformed payload (non-map row, `data:
  /// null` on a typed get, …) becomes an `ApiFailure` instead of an
  /// uncaught `TypeError` crashing the UI.
  T _tryParse<T>(Object? json, T Function(Object?) parse) {
    try {
      return parse(json);
    } on TypeError catch (e) {
      throw ApiResponseException('Failed to parse server response: $e', null);
    }
  }

  /// Unwraps `data` from `{success: true, data}`; throws for
  /// `{success: false, error}`; passes non-envelope bodies through.
  Object? _envelopeData(Response<dynamic> response) {
    final body = response.data;
    if (body is Map<String, dynamic>) {
      if (body['success'] == true) return body['data'];
      final error = body['error'];
      // sendError() bodies are `{error: {code, message}}`; a few bare
      // error paths are `{error: 'message'}`.
      if (error is String) {
        throw ApiResponseException(error, response.statusCode);
      }
      if (error is Map<String, dynamic> && error['message'] is String) {
        throw ApiResponseException(
          error['message'] as String,
          response.statusCode,
        );
      }
      throw ApiResponseException('Request failed', response.statusCode);
    }
    return body;
  }

  List<T> _parseItems<T>(List<dynamic> data, T Function(Object?) parseItem) => [
    for (final item in data) _tryParse(item, parseItem),
  ];

  ApiError _toError(DioException e) {
    final isNetwork = switch (e.type) {
      DioExceptionType.connectionError ||
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.transformTimeout => true,
      _ => false,
    };
    return ApiError(
      message: mapError(e),
      statusCode: e.response?.statusCode,
      isNetwork: isNetwork,
    );
  }

  int? _asInt(Object? value) => value is num ? value.toInt() : null;
}

/// Single shared [RepositoryClient] for the whole provider tree (spec 1.2):
/// every feature repository injects this instead of constructing its own
/// client, so exactly one instance exists per app run and the dependency
/// graph stays traceable.
final repositoryClientProvider = Provider<RepositoryClient>(
  (ref) => RepositoryClient(ref.watch(dioProvider)),
);
