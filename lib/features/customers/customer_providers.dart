import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/customer.dart' show Customer;
import '../../data/models/ledger_entry.dart' show LedgerEntry;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/customer_repository.dart'
    show customerRepositoryProvider;
import '../../data/repositories/paged_request.dart' show PagedRequest, PagedResponse;

/// Server-side sort — the API column name (from the server's
/// `CUSTOMER_SORT_COLUMNS` whitelist) plus the order.
class CustomerSort {
  const CustomerSort(this.column, this.order);

  final String column;

  /// `ASC` or `DESC`.
  final String order;
}

/// Server-side search term; empty omits the param.
final customersSearchProvider = StateProvider<String>((ref) => '');

/// Current page (1-based) for the server-side pagination.
final customersPageProvider = StateProvider<int>((ref) => 1);

/// Rows per page; changing it resets to page 1 (the screen does that).
final customersLimitProvider = StateProvider<int>((ref) => 10);

/// Active server-side sort; null = server default (customer_name ASC).
final customersSortProvider = StateProvider<CustomerSort?>((ref) => null);

/// One page of customers — the project's only server-paginated list
/// (PORTING.md §2: `page, limit, search, sortBy, sortOrder` on
/// `GET /customers`, which returns a `pagination` block). Re-runs when any
/// of the paging state changes; the screen invalidates it on refresh.
final customersProvider = FutureProvider<PagedResponse<Customer>>((ref) async {
  final search = ref.watch(customersSearchProvider);
  final page = ref.watch(customersPageProvider);
  final limit = ref.watch(customersLimitProvider);
  final sort = ref.watch(customersSortProvider);

  final result = await ref.watch(customerRepositoryProvider).list(
        PagedRequest(
          page: page,
          limit: limit,
          search: search.isEmpty ? null : search,
          sortBy: sort?.column,
          sortOrder: sort?.order ?? 'ASC',
        ),
      );

  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// Detail for one customer (`GET /customers/:id`, bare object). autoDispose:
/// each dialog instance owns its fetch, so closing it frees the state.
final customerDetailProvider =
    FutureProvider.autoDispose.family<Customer, int>((ref, customerId) async {
  final result = await ref.watch(customerRepositoryProvider).get(customerId);
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// The customer's AR ledger (`GET /customers/:id/ledger`, enveloped array,
/// newest-first by transaction_date). autoDispose: each ledger dialog owns
/// its fetch, so closing it frees the state.
final customerLedgerProvider =
    FutureProvider.autoDispose.family<List<LedgerEntry>, int>(
        (ref, customerId) async {
  final result =
      await ref.watch(customerRepositoryProvider).ledger(customerId);
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});
