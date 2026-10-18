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
class ApiDependency {
  const ApiDependency({
    required this.sourceId,
    required this.consumed,
    required this.invoices,
  });

  final int sourceId;
  final num consumed;
  final List<int> invoices;
}

class ApiError {
  const ApiError({
    required this.message,
    this.statusCode,
    this.isNetwork = false,
    this.outcomeUnknown = false,
    this.code,
    this.blockedBy = const [],
  });

  factory ApiError.fromResponse({
    required String message,
    int? statusCode,
    Object? body,
    bool isNetwork = false,
    bool outcomeUnknown = false,
  }) {
    final error = body is Map ? body['error'] : null;
    final code = error is Map && error['code'] is String
        ? error['code'] as String
        : null;
    final blockers = error is Map ? error['blockedBy'] : null;
    return ApiError(
      message: message,
      statusCode: statusCode,
      code: code,
      isNetwork: isNetwork,
      outcomeUnknown: outcomeUnknown,
      blockedBy: List.unmodifiable([
        if (blockers is List)
          for (final blocker in blockers)
            if (blocker is Map &&
                blocker['sourceId'] is int &&
                blocker['consumed'] is num &&
                blocker['invoices'] is List)
              ApiDependency(
                sourceId: blocker['sourceId'] as int,
                consumed: blocker['consumed'] as num,
                invoices: List.unmodifiable(
                  (blocker['invoices'] as List).whereType<int>(),
                ),
              ),
      ]),
    );
  }

  final String message;
  final int? statusCode;
  final bool isNetwork;
  final String? code;
  final List<ApiDependency> blockedBy;

  /// The request may already have been applied server-side, so a *write*
  /// must not be reported as a plain failure and must not be blindly
  /// repeated. True only for timeouts that happen after the bytes were
  /// handed to the socket (`sendTimeout`/`receiveTimeout`) — a
  /// `connectionTimeout`/`connectionError` means the request was never
  /// delivered and is therefore a definite failure, not an unknown one.
  ///
  /// Retrying such a request is safe only with the same idempotency key
  /// (P11): a fresh key would create a second document.
  final bool outcomeUnknown;

  /// Convenience for call sites deciding whether to offer a safe retry.
  bool get isRetryableWrite => outcomeUnknown;

  @override
  String toString() =>
      'ApiError(${statusCode ?? 'no-status'}, code=$code, network=$isNetwork, '
      'outcomeUnknown=$outcomeUnknown): $message';
}
