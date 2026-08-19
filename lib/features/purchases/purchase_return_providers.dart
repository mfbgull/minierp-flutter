import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart' show isoDate;
import '../../data/models/purchase.dart' show Purchase;
import '../../data/models/purchase_order.dart' show PurchaseOrder;
import '../../data/models/purchase_return.dart' show PurchaseReturn;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/paged_request.dart'
    show PagedRequest, PagedResponse;
import '../../data/repositories/purchase_order_repository.dart'
    show purchaseOrderRepositoryProvider;
import '../../data/repositories/purchase_repository.dart'
    show purchaseRepositoryProvider;

/// Server-side search term (return no / source no / item); empty omits
/// the param (`GET /purchase-returns` accepts `search`).
final purchaseReturnsSearchProvider = StateProvider<String>((ref) => '');

/// Current page (1-based) for the server-side pagination.
final purchaseReturnsPageProvider = StateProvider<int>((ref) => 1);

/// Rows per page; changing it resets to page 1 (the screen does that).
final purchaseReturnsLimitProvider = StateProvider<int>((ref) => 10);

/// Server-side sort — the API column name (from the server's
/// `PURCHASE_RETURN_HEADER_SORT_COLUMNS` whitelist) plus the order.
class PurchaseReturnSort {
  const PurchaseReturnSort(this.column, this.order);

  final String column;

  /// `ASC` or `DESC`.
  final String order;
}

/// Active server-side sort; null = server default (return_date DESC).
final purchaseReturnsSortProvider = StateProvider<PurchaseReturnSort?>((ref) => null);

/// Active status filter — null = all; `POSTED` | `VOIDED` (sent as the
/// `status` query param).
final purchaseReturnsStatusFilterProvider = StateProvider<String?>(
  (ref) => null,
);

/// Inclusive date-range filter — null means unbounded (sent as
/// `start_date`/`end_date`).
final purchaseReturnsFromDateProvider = StateProvider<DateTime?>((ref) => null);
final purchaseReturnsToDateProvider = StateProvider<DateTime?>((ref) => null);

/// One page of purchase-return headers — server-paginated like
/// customers/suppliers (`GET /purchase-returns` returns a `pagination`
/// block). Re-runs when any of the paging/filter state changes; the
/// screen invalidates it on refresh.
final purchaseReturnsProvider =
    FutureProvider<PagedResponse<PurchaseReturn>>((ref) async {
      final search = ref.watch(purchaseReturnsSearchProvider);
      final page = ref.watch(purchaseReturnsPageProvider);
      final limit = ref.watch(purchaseReturnsLimitProvider);
      final sort = ref.watch(purchaseReturnsSortProvider);
      final status = ref.watch(purchaseReturnsStatusFilterProvider);
      final from = ref.watch(purchaseReturnsFromDateProvider);
      final to = ref.watch(purchaseReturnsToDateProvider);

      final result = await ref.watch(purchaseRepositoryProvider).returnsPaged(
        PagedRequest(
          page: page,
          limit: limit,
          search: search.isEmpty ? null : search,
          sortBy: sort?.column,
          sortOrder: sort?.order ?? 'ASC',
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

/// One large page of direct purchases for the return source picker —
/// keyed on the picker's search term (empty = all). Server-filtered, so
/// the list stays current with the term; the picker owns its own search
/// field and does not touch the purchases screen's filter state.
final returnSourcePurchasesProvider =
    FutureProvider.autoDispose.family<List<Purchase>, String>((ref, search) async {
      final result = await ref.watch(purchaseRepositoryProvider).listPaged(
        PagedRequest(
          limit: 500,
          search: search.isEmpty ? null : search,
          sortBy: 'purchase_date',
          sortOrder: 'DESC',
        ),
      );
      return switch (result) {
        ApiSuccess(:final data) => data.items,
        ApiFailure(:final error) => throw error,
      };
    });

/// One large page of purchase orders for the return source picker — keyed
/// on the picker's search term, server-filtered like
/// [returnSourcePurchasesProvider].
final returnSourceOrdersProvider =
    FutureProvider.autoDispose.family<List<PurchaseOrder>, String>((ref, search) async {
      final result = await ref.watch(purchaseOrderRepositoryProvider).listPaged(
        PagedRequest(
          limit: 500,
          search: search.isEmpty ? null : search,
          sortBy: 'po_date',
          sortOrder: 'DESC',
        ),
      );
      return switch (result) {
        ApiSuccess(:final data) => data.items,
        ApiFailure(:final error) => throw error,
      };
    });

/// The full *filtered* purchase-return list (one large page) — the CSV
/// export must run over every row matching the active filters, not just
/// the current page. Watches the same filters as [purchaseReturnsProvider]
/// but ignores page/limit/sort.
final filteredPurchaseReturnsProvider =
    FutureProvider<List<PurchaseReturn>>((ref) async {
      final search = ref.watch(purchaseReturnsSearchProvider);
      final status = ref.watch(purchaseReturnsStatusFilterProvider);
      final from = ref.watch(purchaseReturnsFromDateProvider);
      final to = ref.watch(purchaseReturnsToDateProvider);

      final result = await ref.watch(purchaseRepositoryProvider).returnsPaged(
        PagedRequest(
          page: 1,
          limit: 10000,
          search: search.isEmpty ? null : search,
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
