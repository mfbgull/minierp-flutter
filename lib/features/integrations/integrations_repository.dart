// Integrations repository — typed against `server/src/routes/integrations.ts`
// (PORTING.md §13). The status GET returns a *bare* body (no envelope);
// the per-service PUT returns the standard `{success: true, message}`
// envelope. Both go through the client's raw helpers.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart' show dioProvider;
import '../../core/api/endpoints.dart' show ApiEndpoints;
import '../../data/repositories/api_result.dart';
import '../../data/repositories/repository_client.dart';
import 'integration_models.dart' show IntegrationServiceStatus;

class IntegrationsRepository {
  IntegrationsRepository(this._api);

  final RepositoryClient _api;

  /// Status flags per service (`GET /integrations/settings` — bare body
  /// `{email: {enabled, configured}, …}`). Unknown services are skipped.
  Future<ApiResult<Map<String, IntegrationServiceStatus>>> status() =>
      _api.getRaw(
        '${ApiEndpoints.integrations}/settings',
        parse: (Object? json) {
          if (json is! Map<String, dynamic>) return const {};
          return {
            for (final entry in json.entries)
              if (entry.value is Map<String, dynamic>)
                entry.key: IntegrationServiceStatus.fromJson(
                  entry.value as Map<String, dynamic>,
                ),
          };
        },
      );

  /// Update one service (`PUT /integrations/settings/:service`). `body`
  /// carries `{enabled, apiKey?, …}`. The response is the standard
  /// `{success: true, message}` envelope; since [RepositoryClient.putRaw]
  /// passes the body through without envelope checks, the parse validates
  /// `success` itself so a `{success: false}` 200 body surfaces as an
  /// [ApiFailure] instead of a silent success.
  Future<ApiResult<void>> updateService(
    String service,
    Map<String, dynamic> body,
  ) => _api.putRaw<void>(
    '${ApiEndpoints.integrations}/settings/$service',
    body: body,
    parse: (Object? json) {
      if (json is! Map<String, dynamic> || json['success'] == false) {
        throw ApiResponseException(
          'Integration settings update rejected',
          null,
        );
      }
    },
  );
}

final integrationsRepositoryProvider = Provider<IntegrationsRepository>(
  (ref) =>
      IntegrationsRepository(RepositoryClient(ref.watch(dioProvider))),
);
