// Pin the dio 401 interceptor rule (PORTING.md §2 + change-password):
//
// - A 401 from /auth/login or /auth/change-password means "bad
//   credentials" — the stored JWT is still valid, so the interceptor must
//   NOT clear the token or fire the session-expiry event (a wrong current
//   password must not log the user out).
// - A 401 from any other endpoint means "expired/invalid token" → clear
//   the token + notify the app so it routes to /login.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/core/api/api_client.dart';
import 'package:minierp_app/core/api/endpoints.dart';
import 'package:minierp_app/core/auth/session_events.dart';
import 'package:minierp_app/core/auth/token_storage.dart';

class _MemoryStorage implements TokenStorage {
  String? token;
  String? refreshToken;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> writeToken(String value) async => token = value;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<void> writeRefreshToken(String value) async => refreshToken = value;

  @override
  Future<void> clear() async {
    token = null;
    refreshToken = null;
  }
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => handler(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, {int status = 200}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

/// The change-password handler's wrong-current-password 401 (`sendError`
/// envelope: `error` is a map with `message`).
ResponseBody _wrongPassword401() => _json({
  'success': false,
  'error': {'code': 'UNAUTHORIZED', 'message': 'Current password is incorrect'},
}, status: 401);

/// The auth middleware's expired-token 401 (`error` is a string).
ResponseBody _expiredToken401() =>
    _json({'error': 'Token expired', 'code': 'TOKEN_EXPIRED'}, status: 401);

void main() {
  group('dio 401 interceptor', () {
    late Dio dio;
    late _MemoryStorage storage;
    late SessionEvents events;
    late List<void> unauthorizedFires;

    setUp(() {
      storage = _MemoryStorage()..token = 'valid-token';
      events = SessionEvents();
      unauthorizedFires = [];
      events.unauthorized.listen((_) => unauthorizedFires.add(null));
      dio = Dio(BaseOptions(baseUrl: ApiClient.baseUrl));
      // Attaches the real interceptors to this test dio.
      ApiClient(dio: dio, tokenStorage: storage, sessionEvents: events);
    });

    test(
      '401 from /auth/change-password (wrong password) keeps token + session',
      () async {
        dio.httpClientAdapter = _Adapter((_) => _wrongPassword401());
        await expectLater(
          dio.post(
            ApiEndpoints.changePassword,
            data: {'currentPassword': 'x', 'newPassword': 'y'},
          ),
          throwsA(isA<DioException>()),
        );
        await Future<void>.delayed(Duration.zero);
        expect(storage.token, 'valid-token');
        expect(unauthorizedFires, isEmpty);
      },
    );

    test(
      '401 from /auth/change-password (expired token) still expires session',
      () async {
        dio.httpClientAdapter = _Adapter((_) => _expiredToken401());
        await expectLater(
          dio.post(
            ApiEndpoints.changePassword,
            data: {'currentPassword': 'x', 'newPassword': 'y'},
          ),
          throwsA(isA<DioException>()),
        );
        await Future<void>.delayed(Duration.zero);
        expect(storage.token, isNull);
        expect(unauthorizedFires, hasLength(1));
      },
    );

    test('401 from /auth/login keeps the token and session', () async {
      dio.httpClientAdapter = _Adapter((_) => _wrongPassword401());
      await expectLater(
        dio.post(ApiEndpoints.login, data: {'username': 'a', 'password': 'b'}),
        throwsA(isA<DioException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(storage.token, 'valid-token');
      expect(unauthorizedFires, isEmpty);
    });

    test(
      '401 from a regular API call clears the token and fires the event',
      () async {
        dio.httpClientAdapter = _Adapter((_) => _expiredToken401());
        await expectLater(dio.get('/invoices'), throwsA(isA<DioException>()));
        await Future<void>.delayed(Duration.zero);
        expect(storage.token, isNull);
        expect(unauthorizedFires, hasLength(1));
      },
    );

    test(
      '401 retries transparently when the refresh token works',
      () async {
        storage.refreshToken = 'valid-refresh-token';
        var invoiceHits = 0;
        dio.httpClientAdapter = _Adapter((options) {
          if (options.path == ApiEndpoints.refresh) {
            return _json({
              'success': true,
              'data': {'token': 'fresh-access-token'},
            });
          }
          if (options.path == '/invoices') {
            invoiceHits++;
            if (invoiceHits == 1) return _expiredToken401();
            return _json({'success': true, 'data': []});
          }
          return _json({'success': true, 'data': null});
        });

        final response = await dio.get('/invoices');
        expect(response.statusCode, 200);
        expect(invoiceHits, 2); // original + one retry
        expect(storage.token, 'fresh-access-token');
        expect(unauthorizedFires, isEmpty);
      },
    );

    test(
      'concurrent 401s share a single refresh round-trip',
      () async {
        storage.refreshToken = 'valid-refresh-token';
        var refreshHits = 0;
        var invoiceHits = 0;
        dio.httpClientAdapter = _Adapter((options) async {
          if (options.path == ApiEndpoints.refresh) {
            refreshHits++;
            return _json({
              'success': true,
              'data': {'token': 'fresh-access-token'},
            });
          }
          if (options.path == '/invoices') {
            invoiceHits++;
            if (invoiceHits <= 2) return _expiredToken401();
            return _json({'success': true, 'data': []});
          }
          return _json({'success': true, 'data': null});
        });

        final results = await Future.wait([
          dio.get('/invoices'),
          dio.get('/invoices'),
        ]);
        expect(results.every((r) => r.statusCode == 200), isTrue);
        expect(refreshHits, 1);
        expect(unauthorizedFires, isEmpty);
      },
    );

    test('refresh failure falls back to clearing the session', () async {
      storage.refreshToken = 'expired-refresh-token';
      dio.httpClientAdapter = _Adapter((options) {
        if (options.path == ApiEndpoints.refresh) {
          return _json({'error': 'Invalid or expired refresh token'},
              status: 401);
        }
        return _expiredToken401();
      });

      await expectLater(dio.get('/invoices'), throwsA(isA<DioException>()));
      await Future<void>.delayed(Duration.zero);
      expect(storage.token, isNull);
      expect(unauthorizedFires, hasLength(1));
    });
  });
}
