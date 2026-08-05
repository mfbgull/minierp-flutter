import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/ledger_entry.dart' show LedgerEntry;
import '../../data/models/supplier.dart' show Supplier;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/paged_request.dart'
    show PagedRequest, PagedResponse;
import '../../data/repositories/supplier_repository.dart'
    show supplierRepositoryProvider;

/// Server-side sort — the API column name (from the server's
/// `SUPPLIER_SORT_COLUMNS` whitelist) plus the order.
class SupplierSort {
  const SupplierSort(this.column, this.order);

  final String column;

  /// `ASC` or `DESC`.
  final String order;
}

/// Server-side search term; empty omits the param.
final suppliersSearchProvider = StateProvider<String>((ref) => '');

/// Current page (1-based) for the server-side pagination.
final suppliersPageProvider = StateProvider<int>((ref) => 1);

/// Rows per page; changing it resets to page 1 (the screen does that).
final suppliersLimitProvider = StateProvider<int>((ref) => 10);

/// Active server-side sort; null = server default (supplier_name ASC).
final suppliersSortProvider = StateProvider<SupplierSort?>((ref) => null);

/// One page of suppliers — server-paginated like customers (`GET
/// /suppliers` returns a `pagination` block; PORTING.md §2). Re-runs when
/// any of the paging state changes; the screen invalidates it on refresh.
final suppliersProvider = FutureProvider<PagedResponse<Supplier>>((ref) async {
  final search = ref.watch(suppliersSearchProvider);
  final page = ref.watch(suppliersPageProvider);
  final limit = ref.watch(suppliersLimitProvider);
  final sort = ref.watch(suppliersSortProvider);

  final result = await ref
      .watch(supplierRepositoryProvider)
      .list(
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

/// Detail for one supplier (`GET /suppliers/:id`, bare object). autoDispose:
/// each dialog instance owns its fetch, so closing it frees the state.
final supplierDetailProvider = FutureProvider.autoDispose.family<Supplier, int>(
  (ref, supplierId) async {
    final result = await ref.watch(supplierRepositoryProvider).get(supplierId);
    return switch (result) {
      ApiSuccess(:final data) => data,
      ApiFailure(:final error) => throw error,
    };
  },
);

/// The supplier's AP ledger (`GET /suppliers/:id/ledger`, enveloped array,
/// newest-first by transaction_date). autoDispose: each ledger dialog owns
/// its fetch, so closing it frees the state.
final supplierLedgerProvider = FutureProvider.autoDispose
    .family<List<LedgerEntry>, int>((ref, supplierId) async {
      final result = await ref
          .watch(supplierRepositoryProvider)
          .ledger(supplierId);
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });
