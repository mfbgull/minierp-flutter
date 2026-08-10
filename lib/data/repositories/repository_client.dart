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

import 'package:dio/dio.dart';

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
  RepositoryClient(this._dio);

  final Dio _dio;

  /* ── Enveloped requests ──────────────────────────────────────── */

  Future<ApiResult<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    required T Function(Object?) parse,
  }) => _parse(
    _guard(() => _dio.get(path, queryParameters: queryParameters)),
    parse,
  );

  Future<ApiResult<T>> post<T>(
    String path, {
    Object? body,
    required T Function(Object?) parse,
  }) => _parse(_guard(() => _dio.post(path, data: body)), parse);

  /// Enveloped multipart POST — `{success: true, data}` with a
  /// [FormData] body (the employee-document upload posts the metadata
  /// fields plus the `file` part). Same envelope handling as [post];
  /// dio sets the multipart content type from the FormData.
  Future<ApiResult<T>> postMultipart<T>(
    String path, {
    required FormData formData,
    required T Function(Object?) parse,
  }) => _parse(_guard(() => _dio.post(path, data: formData)), parse);

  Future<ApiResult<T>> put<T>(
    String path, {
    Object? body,
    required T Function(Object?) parse,
  }) => _parse(_guard(() => _dio.put(path, data: body)), parse);

  /// Enveloped delete — `{success: true, message}`, no data payload.
  Future<ApiResult<void>> delete(String path) async {
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
    final guarded = await _guard(
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
    final guarded = await _guard(
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
    final guarded = await _guard(
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
    _guard(() => _dio.get(path, queryParameters: queryParameters)),
    parse,
  );

  /// POST returning the created object directly (item create).
  Future<ApiResult<T>> postRaw<T>(
    String path, {
    Object? body,
    required T Function(Object?) parse,
  }) => _parseRaw(_guard(() => _dio.post(path, data: body)), parse);

  /// PUT returning the updated object directly (item update).
  Future<ApiResult<T>> putRaw<T>(
    String path, {
    Object? body,
    required T Function(Object?) parse,
  }) => _parseRaw(_guard(() => _dio.put(path, data: body)), parse);

  /// PATCH returning the updated object directly (BOM toggle-active).
  /// The standard helpers cover the server's GET/POST/PUT/DELETE verbs;
  /// this one exists for the handful of PATCH endpoints.
  Future<ApiResult<T>> patchRaw<T>(
    String path, {
    Object? body,
    required T Function(Object?) parse,
  }) => _parseRaw(_guard(() => _dio.patch(path, data: body)), parse);

  /// DELETE returning a bare body (invoice delete: `{message}` — no
  /// envelope, unlike the enveloped `delete` used by items/customers).
  Future<ApiResult<void>> deleteRaw(String path) async {
    final result = await _guard(() => _dio.delete(path));
    return result.map<void>((_) {});
  }

  /// GET a bare array (items-categories, items-uom, stock movements).
  Future<ApiResult<List<T>>> getRawList<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    required T Function(Object?) parseItem,
  }) async {
    final guarded = await _guard(
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
