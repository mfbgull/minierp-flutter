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

/// One journal line that lands on the first negative-cash day, from the
/// cash guard's 409 `details` list (ACCT-013). The client needs this to say
/// *what* must be reversed first, not just that the day is overdrawn.
class CashBlocker {
  const CashBlocker({
    required this.id,
    required this.date,
    required this.amount,
    required this.type,
  });

  final int id;
  final String date;
  final num amount;

  /// Journal `reference_type`, for example `EXPENSE` or `SUPPLIER_REFUND`.
  final String type;
}

class ApiError {
  const ApiError({
    required this.message,
    this.statusCode,
    this.isNetwork = false,
    this.outcomeUnknown = false,
    this.code,
    this.blockedBy = const [],
    this.cashBlockers = const [],
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
    // The cash guard posts its per-line list as `details` (a sibling of
    // `error`, not a child). Missing or malformed entries are dropped rather
    // than thrown — a 409 must still reach the user with its message.
    final details = body is Map ? body['details'] : null;
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
      cashBlockers: List.unmodifiable([
        if (details is List)
          for (final blocker in details)
            if (blocker is Map &&
                blocker['id'] is int &&
                blocker['date'] is String &&
                blocker['amount'] is num &&
                blocker['type'] is String)
              CashBlocker(
                id: blocker['id'] as int,
                date: blocker['date'] as String,
                amount: blocker['amount'] as num,
                type: blocker['type'] as String,
              ),
      ]),
    );
  }

  final String message;
  final int? statusCode;
  final bool isNetwork;
  final String? code;
  final List<ApiDependency> blockedBy;

  /// Lines that must be reversed first when the cash guard rejects a write.
  /// Empty when the 409 carried no `details` list.
  final List<CashBlocker> cashBlockers;

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
