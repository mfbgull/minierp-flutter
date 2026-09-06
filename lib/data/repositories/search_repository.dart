import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/endpoints.dart' show ApiEndpoints;
import '../models/search_result.dart' show SearchResponse;
import 'api_result.dart' show ApiResult;
import 'repository_client.dart' show RepositoryClient, repositoryClientProvider;

class SearchRepository {
  SearchRepository(this._client);

  final RepositoryClient _client;

  /// `GET /api/search?q=…&limit=…` — enveloped
  /// `{success, data:{query, results, total}}`.
  Future<ApiResult<SearchResponse>> search({
    required String query,
    int limit = 10,
  }) =>
      _client.get(
        ApiEndpoints.search,
        queryParameters: {'q': query, 'limit': limit},
        parse: (json) =>
            SearchResponse.fromJson(json as Map<String, dynamic>),
      );
}

final searchRepositoryProvider = Provider<SearchRepository>(
  (ref) => SearchRepository(ref.watch(repositoryClientProvider)),
);
