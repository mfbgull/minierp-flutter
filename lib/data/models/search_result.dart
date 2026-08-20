/// Models for the global search / command palette response
/// (server `SearchResponse` envelope from `GET /api/search`).

class SearchAction {
  const SearchAction({required this.id, required this.label});

  factory SearchAction.fromJson(Map<String, dynamic> json) => SearchAction(
        id: (json['id'] as String?) ?? '',
        label: (json['label'] as String?) ?? '',
      );

  final String id;
  final String label;
}

class SearchResult {
  const SearchResult({
    required this.type,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.metadata,
    required this.actions,
  });

  factory SearchResult.fromJson(Map<String, dynamic> json) => SearchResult(
        type: (json['type'] as String?) ?? '',
        id: json['id'],
        title: (json['title'] as String?) ?? '',
        subtitle: (json['subtitle'] as String?) ?? '',
        metadata: Map<String, dynamic>.from(
          (json['metadata'] as Map?) ?? const {},
        ),
        actions: [
          for (final a in (json['actions'] as List?) ?? const [])
            SearchAction.fromJson(a as Map<String, dynamic>),
        ],
      );

  final String type;
  final dynamic id;
  final String title;
  final String subtitle;
  final Map<String, dynamic> metadata;
  final List<SearchAction> actions;

  bool get isPage => type == 'page';
}

class SearchResponse {
  const SearchResponse({
    required this.query,
    required this.results,
    required this.total,
  });

  factory SearchResponse.fromJson(Map<String, dynamic> json) => SearchResponse(
        query: (json['query'] as String?) ?? '',
        results: [
          for (final r in (json['results'] as List?) ?? const [])
            SearchResult.fromJson(r as Map<String, dynamic>),
        ],
        total: (json['total'] as num?)?.toInt() ?? 0,
      );

  factory SearchResponse.empty() =>
      const SearchResponse(query: '', results: [], total: 0);

  final String query;
  final List<SearchResult> results;
  final int total;
}
