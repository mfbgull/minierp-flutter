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
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return 'Request timed out. Check the server at ${ApiClient.baseUrl}.';
      case DioExceptionType.connectionError:
        return 'Cannot reach the server. Is it running?';
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
