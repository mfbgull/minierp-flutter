import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart' show isoDate;
import '../../data/models/invoice.dart' show InvoicePaymentRecord;
import '../../data/models/purchase.dart' show Purchase;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/paged_request.dart'
    show PagedRequest, PagedResponse;
import '../../data/repositories/purchase_repository.dart'
    show purchaseRepositoryProvider;
import '../preferences/preference_providers.dart' show initialRange;

/// Server-side search term (purchase no / item / supplier); empty omits
/// the param. The endpoint gained a `search` param (grid-pagination §6).
final purchasesSearchProvider = StateProvider<String>((ref) => '');

/// Current page (1-based) for the server-side pagination.
final purchasesPageProvider = StateProvider<int>((ref) => 1);

/// Rows per page; changing it resets to page 1 (the screen does that).
final purchasesLimitProvider = StateProvider<int>((ref) => 10);

/// Server-side sort — the API column name (from the server's
/// `PURCHASE_SORT_COLUMNS` whitelist) plus the order.
class PurchaseSort {
  const PurchaseSort(this.column, this.order);

  final String column;

  /// `ASC` or `DESC`.
  final String order;
}

/// Active server-side sort; null = server default (purchase_date DESC).
final purchasesSortProvider = StateProvider<PurchaseSort?>((ref) => null);

/// Whether voided purchases are shown in the grid. Default false — the
/// server hides them (`p.voided_at IS NULL`) unless this sends
/// `include_voided=1` (the toolbar's "Show Voided" chip).
final purchasesIncludeVoidedProvider = StateProvider<bool>((ref) => false);

/// Inclusive date-range filter — null means unbounded (sent as
/// `start_date`/`end_date`).
final purchasesFromDateProvider =
    StateProvider<DateTime?>((ref) => initialRange(ref).from);
final purchasesToDateProvider =
    StateProvider<DateTime?>((ref) => initialRange(ref).to);

/// One page of direct purchases — server-paginated like customers/suppliers
/// (`GET /purchases` returns a `pagination` block). Re-runs when any of
/// the paging/filter state changes; the screen invalidates it on refresh,
/// and the return-processing dialog invalidates it after a successful
/// return.
final purchasesProvider = FutureProvider<PagedResponse<Purchase>>((ref) async {
  final search = ref.watch(purchasesSearchProvider);
  final page = ref.watch(purchasesPageProvider);
  final limit = ref.watch(purchasesLimitProvider);
  final sort = ref.watch(purchasesSortProvider);
  final includeVoided = ref.watch(purchasesIncludeVoidedProvider);
  final fromDate = ref.watch(purchasesFromDateProvider);
  final toDate = ref.watch(purchasesToDateProvider);

  final result = await ref.watch(purchaseRepositoryProvider).listPaged(
    PagedRequest(
      page: page,
      limit: limit,
      search: search.isEmpty ? null : search,
      sortBy: sort?.column,
      sortOrder: sort?.order ?? 'ASC',
      extra: {
        if (includeVoided) 'include_voided': '1',
        if (fromDate != null) 'start_date': isoDate(fromDate),
        if (toDate != null) 'end_date': isoDate(toDate),
      },
    ),
  );

  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// The full *filtered* purchase list (one large page) — used when a
/// consumer needs the whole filtered set (e.g. detail lookups across
/// pages). Watches the same filters as [purchasesProvider] but ignores
/// page/limit/sort.
final filteredPurchasesProvider =
    FutureProvider<List<Purchase>>((ref) async {
      final search = ref.watch(purchasesSearchProvider);
      final includeVoided = ref.watch(purchasesIncludeVoidedProvider);
      final fromDate = ref.watch(purchasesFromDateProvider);
      final toDate = ref.watch(purchasesToDateProvider);

      final result = await ref.watch(purchaseRepositoryProvider).listPaged(
        PagedRequest(
          page: 1,
          limit: 10000,
          search: search.isEmpty ? null : search,
          extra: {
            if (includeVoided) 'include_voided': '1',
            if (fromDate != null) 'start_date': isoDate(fromDate),
            if (toDate != null) 'end_date': isoDate(toDate),
          },
        ),
      );

      return switch (result) {
        ApiSuccess(:final data) => data.items,
        ApiFailure(:final error) => throw error,
      };
    });

/// Payment history for one purchase (`GET /purchases/:id/payments`,
/// enveloped list). autoDispose: each dialog instance owns its fetch, so
/// closing it frees the state.
final purchasePaymentsProvider = FutureProvider.autoDispose
    .family<List<InvoicePaymentRecord>, int>((ref, purchaseId) async {
      final result = await ref
          .watch(purchaseRepositoryProvider)
          .payments(purchaseId);
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });

/// Purchase detail (`GET /purchases/:id`, bare object). autoDispose:
/// each dialog instance owns its fetch, so closing it frees the state.
final purchaseDetailProvider = FutureProvider.autoDispose.family<Purchase, int>(
  (ref, id) async {
    final result = await ref.watch(purchaseRepositoryProvider).detail(id);
    return switch (result) {
      ApiSuccess(:final data) => data,
      ApiFailure(:final error) => throw error,
    };
  },
);
