// Shared test setup — mock Dio, mock TokenStorage, ProviderScope wrapper.
// Used across widget tests to avoid duplicating the fake infrastructure.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:minierp_app/core/api/api_client.dart';
import 'package:minierp_app/core/auth/token_storage.dart';
import 'package:minierp_app/l10n/app_localizations.dart';

/// In-memory fake for [TokenStorage] — avoids flutter_secure_storage's
/// Linux FFI which blocks on the system keyring daemon.
class FakeTokenStorage implements TokenStorage {
  String? token;
  String? refreshToken;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<void> writeToken(String value) async => token = value;

  @override
  Future<void> writeRefreshToken(String value) async => refreshToken = value;

  @override
  Future<void> clear() async {
    token = null;
    refreshToken = null;
  }
}

/// Creates a Dio instance backed by [responses] map (path → handler).
/// The returned Dio doesn't hit the network.
Dio createFakeDio(Map<String, dynamic> responses) {
  final dio = Dio(BaseOptions(baseUrl: 'http://localhost:3011/api'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final path = options.path;
        final response = responses[path];
        if (response != null) {
          handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: response,
          ));
          return;
        }
        handler.reject(DioException(
          requestOptions: options,
          response: Response(
            requestOptions: options,
            statusCode: 404,
            data: {'success': false, 'error': 'Not found'},
          ),
          type: DioExceptionType.badResponse,
        ));
      },
    ),
  );
  return dio;
}

/// Wraps a widget in a [ProviderScope] + [MaterialApp] + localization delegates
/// for widget testing.
Widget buildTestable(
  Widget child, {
  List<Override> overrides = const [],
  TokenStorage? tokenStorage,
  Dio? dio,
}) {
  final storage = tokenStorage ?? FakeTokenStorage();
  final fakeDio = dio ?? createFakeDio({});

  return ProviderScope(
    overrides: [
      tokenStorageProvider.overrideWithValue(storage),
      dioProvider.overrideWithValue(fakeDio),
      ...overrides,
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}

/// Standard JSON envelope for a successful response.
Map<String, dynamic> successEnvelope(dynamic data) => {
      'success': true,
      'data': data,
    };

/// Standard JSON envelope for a paginated list response.
Map<String, dynamic> pagedEnvelope(
  List<dynamic> data, {
  int totalItems = 10,
  int currentPage = 1,
  int totalPages = 1,
}) => {
      'success': true,
      'data': data,
      'pagination': {
        'totalItems': totalItems,
        'currentPage': currentPage,
        'totalPages': totalPages,
        'hasNext': currentPage < totalPages,
        'hasPrev': currentPage > 1,
      },
    };
