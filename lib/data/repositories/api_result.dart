/// Result of an API call — PORTING.md §2 maps the server envelope
/// (`{success: true, data}` / `{success: false, error: "…"}`) to this
/// sealed type so callers must handle both branches (no silent failures).
sealed class ApiResult<T> {
  const ApiResult();

  /// Collapse to a single value.
  R fold<R>({
    required R Function(T data) onSuccess,
    required R Function(ApiError error) onFailure,
  });

  /// Transform the success value; failures pass through unchanged.
  ApiResult<R> map<R>(R Function(T data) transform);

  /// Async transform of the success value; failures pass through.
  Future<ApiResult<R>> asyncMap<R>(Future<R> Function(T data) transform);

  /// Unwrap or throw — for flows where a failure is a programming error.
  T get requireData => switch (this) {
    ApiSuccess(:final data) => data,
    ApiFailure() => throw StateError(
      'ApiResult.requireData called on a failure',
    ),
  };
}

class ApiSuccess<T> extends ApiResult<T> {
  const ApiSuccess(this.data);

  final T data;

  @override
  R fold<R>({
    required R Function(T data) onSuccess,
    required R Function(ApiError error) onFailure,
  }) => onSuccess(data);

  @override
  ApiResult<R> map<R>(R Function(T data) transform) =>
      ApiSuccess(transform(data));

  @override
  Future<ApiResult<R>> asyncMap<R>(
    Future<R> Function(T data) transform,
  ) async => ApiSuccess(await transform(data));

  @override
  String toString() => 'ApiSuccess($data)';
}

class ApiFailure<T> extends ApiResult<T> {
  const ApiFailure(this.error);

  final ApiError error;

  @override
  R fold<R>({
    required R Function(T data) onSuccess,
    required R Function(ApiError error) onFailure,
  }) => onFailure(error);

  @override
  ApiResult<R> map<R>(R Function(T data) transform) => ApiFailure(error);

  @override
  Future<ApiResult<R>> asyncMap<R>(
    Future<R> Function(T data) transform,
  ) async => ApiFailure(error);

  @override
  String toString() => 'ApiFailure($error)';
}

/// Structured failure: message (server `error` text or transport message),
/// HTTP status when present, and whether it was a transport-level problem
/// (timeout/connection) vs a server response.
class ApiError {
  const ApiError({
    required this.message,
    this.statusCode,
    this.isNetwork = false,
  });

  final String message;
  final int? statusCode;
  final bool isNetwork;

  @override
  String toString() =>
      'ApiError(${statusCode ?? 'no-status'}, network=$isNetwork): $message';
}
