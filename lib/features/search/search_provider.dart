import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/search_result.dart' show SearchResponse, SearchResult;
import '../../data/repositories/search_repository.dart'
    show searchRepositoryProvider;

/// The current search box text. Updated after a 200ms debounce so we
/// don't hammer the API on every keystroke.
final searchQueryProvider = StateProvider<String>((_) => '');

/// The result the user has highlighted (drives the action panel).
final selectedResultProvider = StateProvider<SearchResult?>((_) => null);

/// Debounced, query-driven search. Returns an empty response for
/// queries shorter than 2 chars (the backend minimum).
final searchResultsProvider =
    FutureProvider.autoDispose<SearchResponse>((ref) async {
  final query = ref.watch(searchQueryProvider).trim();
  if (query.length < 2) return SearchResponse.empty();
  final repo = ref.watch(searchRepositoryProvider);
  final result = await repo.search(query: query, limit: 10);
  return result.fold(
    onSuccess: (data) => data,
    onFailure: (e) => throw e,
  );
});
