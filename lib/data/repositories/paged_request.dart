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
  /// the server applies its own defaults. Null values in [extra] are also
  /// omitted — Dio serialises them as the string `"null"`, which the server
  /// would interpret as a literal filter value (e.g. `status = 'null'`).
  Map<String, dynamic> toQuery() {
    final q = <String, dynamic>{
      'page': page,
      'limit': limit,
      'sortOrder': sortOrder,
    };
    if (search != null && search!.isNotEmpty) q['search'] = search;
    if (sortBy != null && sortBy!.isNotEmpty) q['sortBy'] = sortBy;
    if (extra != null) {
      for (final e in extra!.entries) {
        if (e.value != null) q[e.key] = e.value;
      }
    }
    return q;
  }
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

/// Enveloped list result carrying the server's raw `total/limit/offset`
/// counters instead of a `pagination` block (the `GET /activity-logs`
/// shape — see `activityLogController.getActivityLogs`). Page math is
/// derived here so screens can render a [ServerPaginationBar] without
/// their own arithmetic.
class OffsetPagedResponse<T> {
  const OffsetPagedResponse({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });

  final List<T> items;
  final int total;
  final int limit;
  final int offset;

  /// 1-based page number for the current offset.
  int get page => limit <= 0 ? 1 : (offset ~/ limit) + 1;

  /// `0` results still render as a single page (matches the web's empty
  /// grid + "Page 1 of 1" convention). Guards `limit <= 0` the same way
  /// [page] does — a response omitting `limit` (client defaults it to 0)
  /// must not divide by zero.
  int get totalPages =>
      total <= 0 || limit <= 0 ? 1 : (total + limit - 1) ~/ limit;

  bool get hasNext => offset + items.length < total;
  bool get hasPrev => offset > 0;
}
