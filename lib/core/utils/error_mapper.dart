import 'package:dio/dio.dart';

import '../api/api_client.dart';

/// Maps transport/API failures to user-facing messages — PORTING.md §2.
///
/// The backend envelope is `{ success: true, data }` or
/// `{ success: false, error: "…" }` (some 401/403/500 paths return bare
/// `{ error }`); 403 responses should surface the server's `error` text.
String mapError(Object error) {
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        // Deliberately does NOT say "failed": these timeouts happen after
        // the request went out, so the server may have applied it (task 42).
        // Retrying with the same idempotency key is safe and is how the
        // caller both recovers and retrieves the existing result.
        return 'No response from the server in time. This request may still '
            'have been saved — retry to confirm safely.';
      case DioExceptionType.connectionTimeout:
        // Never reached the server: nothing could have been written.
        return 'Could not reach ${ApiClient.baseUrl} in time. Nothing was sent.';
      case DioExceptionType.connectionError:
        return 'Cannot reach ${ApiClient.baseUrl}. Nothing was sent.';
      case DioExceptionType.badResponse:
        final status = error.response?.statusCode;
        final body = error.response?.data;
        if (body is Map && body['error'] != null) {
          final err = body['error'];
          // sendError() bodies are `{error: {code, message}}`; a few bare
          // error paths are `{error: 'message'}`.
          if (err is String) return err;
          if (err is Map && err['message'] != null) {
            return err['message'].toString();
          }
          return err.toString();
        }
        return status != null ? 'Server error ($status).' : 'Request failed.';
      case DioExceptionType.cancel:
        return 'Request cancelled.';
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return 'Unexpected network error.';
    }
  }
  return 'Unexpected error.';
}
