// Database backup repository — typed against
// `server/src/routes/adminBackup.ts` (admin-only, mounted under /api/admin).
//
// Endpoint shapes (verified against server tests):
// - `GET /admin/backup` → `{success, data: {backups: [BackupFile],
//   lastBackupAt: iso|null}}`
// - `POST /admin/backup` → `{success, data: {fileName}}` (runs the backup)
// - `DELETE /admin/backup/:name` → `{success, data: {deleted}}`
// - `GET /admin/backup/:name/download` → binary attachment stream

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart' show dioProvider;
import '../../core/api/endpoints.dart' show ApiEndpoints;
import '../models/backup.dart';
import 'api_result.dart';
import 'repository_client.dart';

class BackupRepository {
  BackupRepository(this._client, this._dio);

  final RepositoryClient _client;
  final Dio _dio;

  /// `GET /admin/backup` — files + last backup time.
  Future<ApiResult<BackupStatus>> status() => _client.get(
    ApiEndpoints.adminBackup,
    parse: (Object? json) =>
        BackupStatus.fromJson(json! as Map<String, dynamic>),
  );

  /// `POST /admin/backup` — trigger an on-demand backup; resolves to the
  /// created file name.
  Future<ApiResult<String>> create() => _client.post(
    ApiEndpoints.adminBackup,
    parse: (Object? json) =>
        ((json! as Map<String, dynamic>)['fileName'] ?? '') as String,
  );

  /// `DELETE /admin/backup/:name`.
  Future<ApiResult<void>> delete(String name) =>
      _client.delete('${ApiEndpoints.adminBackup}/$name');

  /// Raw bytes of a backup file for saving locally. Goes through the
  /// authenticated [Dio] so the Bearer-token interceptor applies.
  Future<ApiResult<Uint8List>> downloadBytes(String name) async {
    try {
      final res = await _dio.get<List<int>>(
        '${ApiEndpoints.adminBackup}/$name/download',
        options: Options(responseType: ResponseType.bytes),
      );
      return ApiSuccess(Uint8List.fromList(res.data ?? <int>[]));
    } on DioException catch (e) {
      final body = e.response?.data;
      final message = body is Map && body['error'] is String
          ? body['error']! as String
          : 'Download failed';
      return ApiFailure(ApiError(
        message: message,
        statusCode: e.response?.statusCode,
        isNetwork: e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout,
      ));
    }
  }
}

final backupRepositoryProvider = Provider<BackupRepository>(
  (ref) => BackupRepository(
    ref.watch(repositoryClientProvider),
    ref.watch(dioProvider),
  ),
);
