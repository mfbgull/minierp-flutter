import 'package:flutter_riverpod/flutter_riverpod.dart';


import '../../core/utils/date_utils.dart' show isoDate;
import '../../data/models/quotation.dart' show Quotation, QuotationDetail;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../preferences/preference_providers.dart' show initialRange;
import '../../data/repositories/paged_request.dart'
    show PagedRequest, PagedResponse;
import '../../data/repositories/quotation_repository.dart'
    show quotationRepositoryProvider;

/// Server-side status filter for the quotations grid (raw status
/// value). null → all statuses (param omitted).
final quotationsStatusProvider = StateProvider<String?>((ref) => null);

/// Server-side search term (quotation no / customer name); empty omits
/// the param. The endpoint gained a `search` param (grid-pagination §5).
final quotationsSearchProvider = StateProvider<String>((ref) => '');

/// Server-side date-range filters (ISO strings, applied to
/// `quotation_date` via `start_date`/`end_date`).
final quotationsFromDateProvider = StateProvider<DateTime?>((ref) => initialRange(ref).from);
final quotationsToDateProvider = StateProvider<DateTime?>((ref) => initialRange(ref).to);

/// Current page (1-based) for the server-side pagination.
final quotationsPageProvider = StateProvider<int>((ref) => 1);

/// Rows per page; changing it resets to page 1 (the screen does that).
final quotationsLimitProvider = StateProvider<int>((ref) => 10);

/// Server-side sort — the API column name (from the server's
/// `QUOTATION_SORT_COLUMNS` whitelist) plus the order.
class QuotationSort {
  const QuotationSort(this.column, this.order);

  final String column;

  /// `ASC` or `DESC`.
  final String order;
}

/// Active server-side sort; null = server default (quotation_date DESC).
final quotationsSortProvider = StateProvider<QuotationSort?>((ref) => null);

/// One page of quotations — server-paginated like customers/suppliers
/// (`GET /quotations` returns a `pagination` block). Re-runs when any of
/// the paging/filter state changes; the screen invalidates it on
/// refresh.
final quotationsProvider = FutureProvider<PagedResponse<Quotation>>((ref) async {
  final status = ref.watch(quotationsStatusProvider);
  final search = ref.watch(quotationsSearchProvider);
  final from = ref.watch(quotationsFromDateProvider);
  final to = ref.watch(quotationsToDateProvider);
  final page = ref.watch(quotationsPageProvider);
  final limit = ref.watch(quotationsLimitProvider);
  final sort = ref.watch(quotationsSortProvider);

  final result = await ref.watch(quotationRepositoryProvider).listPaged(
    PagedRequest(
      page: page,
      limit: limit,
      search: search.isEmpty ? null : search,
      sortBy: sort?.column,
      sortOrder: sort?.order ?? 'ASC',
      // Endpoint-specific filter: status + date range.
      extra: {
        'status': ?status,
        'start_date': from == null ? null : isoDate(from),
        'end_date': to == null ? null : isoDate(to),
      },
    ),
  );

  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// The full *filtered* quotation list (one large page) — the CSV export
/// must run over every row matching the active filters, not just the
/// current page. Watches the same filters as [quotationsProvider] but
/// ignores page/limit/sort.
final filteredQuotationsProvider =
    FutureProvider<List<Quotation>>((ref) async {
      final status = ref.watch(quotationsStatusProvider);
      final search = ref.watch(quotationsSearchProvider);
      final from = ref.watch(quotationsFromDateProvider);
      final to = ref.watch(quotationsToDateProvider);

      final result = await ref.watch(quotationRepositoryProvider).listPaged(
        PagedRequest(
          page: 1,
          limit: 10000,
          search: search.isEmpty ? null : search,
          // Endpoint-specific filter: status + date range.
          extra: {
            'status': ?status,
            'start_date': from == null ? null : isoDate(from),
            'end_date': to == null ? null : isoDate(to),
          },
        ),
      );

      return switch (result) {
        ApiSuccess(:final data) => data.items,
        ApiFailure(:final error) => throw error,
      };
    });

/// Detail for one quotation (`GET /quotations/:id`, bare object with the
/// `items` array). autoDispose: each dialog instance owns its fetch, so
/// closing it frees the state.
final quotationDetailProvider = FutureProvider.autoDispose
    .family<QuotationDetail, int>((ref, quotationId) async {
      final result = await ref
          .watch(quotationRepositoryProvider)
          .detail(quotationId);
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });
