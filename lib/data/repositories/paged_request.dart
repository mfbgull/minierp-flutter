/// Shared pagination/sort/filter request for list endpoints — the
/// `page, limit, search, sortBy, sortOrder` pattern (PORTING.md §2,
/// see `GET /customers`).
class PagedRequest {
  const PagedRequest({
    this.page = 1,
    this.limit = 10,
    this.search,
    this.sortBy,
    this.sortOrder = 'ASC',
    this.extra,
  });

  final int page;
  final int limit;
  final String? search;
  final String? sortBy;

  /// `ASC` or `DESC`.
  final String sortOrder;

  /// Endpoint-specific filters, merged into the query (e.g. `status` for
  /// `GET /customers`, `category` for item lists).
  final Map<String, dynamic>? extra;

  /// Query parameters for the request. Empty search/sortBy are omitted so
  /// the server applies its own defaults.
  Map<String, dynamic> toQuery() => {
    'page': page,
    'limit': limit,
    if (search != null && search!.isNotEmpty) 'search': search,
    if (sortBy != null && sortBy!.isNotEmpty) 'sortBy': sortBy,
    'sortOrder': sortOrder,
    ...?extra,
  };
}

/// Enveloped list result including the server's `pagination` block
/// (the `GET /customers` shape: `currentPage`, `totalPages`,
/// `totalItems`, `hasNext`, `hasPrev`).
class PagedResponse<T> {
  const PagedResponse({
    required this.items,
    required this.totalItems,
    required this.currentPage,
    required this.totalPages,
    required this.hasNext,
    required this.hasPrev,
  });

  final List<T> items;
  final int totalItems;
  final int currentPage;
  final int totalPages;
  final bool hasNext;
  final bool hasPrev;
}
