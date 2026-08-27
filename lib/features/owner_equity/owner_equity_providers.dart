import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../preferences/preference_providers.dart' show initialRange;

import '../../core/utils/date_utils.dart' show isoDate;
import '../../data/models/expense.dart' show ExpenseOption;
import '../../data/models/item.dart' show Item;
import '../../data/models/owner_equity.dart'
    show EquitySummary, OwnerCapitalEntry, OwnerWithdrawal;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/inventory_repository.dart'
    show inventoryRepositoryProvider;
import '../../data/repositories/owner_equity_repository.dart'
    show ownerEquityRepositoryProvider;
import '../../data/repositories/paged_request.dart'
    show PagedRequest, PagedResponse;

// --- Capital tab state -----------------------------------------------

final capitalSearchProvider = StateProvider<String>((ref) => '');
final capitalFromDateProvider = StateProvider<DateTime?>((ref) => initialRange(ref).from);
final capitalToDateProvider = StateProvider<DateTime?>((ref) => initialRange(ref).to);
final capitalPageProvider = StateProvider<int>((ref) => 1);
final capitalLimitProvider = StateProvider<int>((ref) => 10);
final capitalSortProvider = StateProvider<EquitySort?>((ref) => null);

/// Rows for the capital grid (server-paged; voided rows excluded by the
/// server unless a status filter says otherwise).
final ownerCapitalProvider = FutureProvider<PagedResponse<OwnerCapitalEntry>>((
  ref,
) async {
  final search = ref.watch(capitalSearchProvider);
  final from = ref.watch(capitalFromDateProvider);
  final to = ref.watch(capitalToDateProvider);
  final page = ref.watch(capitalPageProvider);
  final limit = ref.watch(capitalLimitProvider);
  final sort = ref.watch(capitalSortProvider);
  final repo = ref.watch(ownerEquityRepositoryProvider);

  final result = await repo.capital(
    PagedRequest(
      page: page,
      limit: limit,
      search: search.isEmpty ? null : search,
      sortBy: sort?.column,
      sortOrder: sort?.order ?? 'DESC',
      extra: {
        'from_date': from != null ? isoDate(from) : null,
        'to_date': to != null ? isoDate(to) : null,
      },
    ),
  );
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// Full filtered capital list (10k fetch) for CSV export.
final allOwnerCapitalProvider = FutureProvider<List<OwnerCapitalEntry>>((
  ref,
) async {
  final search = ref.watch(capitalSearchProvider);
  final from = ref.watch(capitalFromDateProvider);
  final to = ref.watch(capitalToDateProvider);
  final repo = ref.watch(ownerEquityRepositoryProvider);

  final result = await repo.capital(
    PagedRequest(limit: 10000, extra: {
      'search': search.isEmpty ? null : search,
      'from_date': from != null ? isoDate(from) : null,
      'to_date': to != null ? isoDate(to) : null,
    }),
  );
  return switch (result) {
    ApiSuccess(:final data) => data.items,
    ApiFailure(:final error) => throw error,
  };
});

// --- Withdrawals tab state --------------------------------------------

final withdrawalsSearchProvider = StateProvider<String>((ref) => '');

/// 'cash' | 'goods' | null (= all kinds).
final withdrawalsKindProvider = StateProvider<String?>((ref) => null);
final withdrawalsFromDateProvider = StateProvider<DateTime?>((ref) => initialRange(ref).from);
final withdrawalsToDateProvider = StateProvider<DateTime?>((ref) => initialRange(ref).to);
final withdrawalsPageProvider = StateProvider<int>((ref) => 1);
final withdrawalsLimitProvider = StateProvider<int>((ref) => 10);
final withdrawalsSortProvider = StateProvider<EquitySort?>((ref) => null);

final ownerWithdrawalsProvider =
    FutureProvider<PagedResponse<OwnerWithdrawal>>((ref) async {
  final search = ref.watch(withdrawalsSearchProvider);
  final kind = ref.watch(withdrawalsKindProvider);
  final from = ref.watch(withdrawalsFromDateProvider);
  final to = ref.watch(withdrawalsToDateProvider);
  final page = ref.watch(withdrawalsPageProvider);
  final limit = ref.watch(withdrawalsLimitProvider);
  final sort = ref.watch(withdrawalsSortProvider);
  final repo = ref.watch(ownerEquityRepositoryProvider);

  final result = await repo.withdrawals(
    PagedRequest(
      page: page,
      limit: limit,
      search: search.isEmpty ? null : search,
      sortBy: sort?.column,
      sortOrder: sort?.order ?? 'DESC',
      extra: {
        'kind': kind,
        'from_date': from != null ? isoDate(from) : null,
        'to_date': to != null ? isoDate(to) : null,
      },
    ),
  );
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// Full filtered withdrawals list (10k fetch) for CSV export.
final allOwnerWithdrawalsProvider = FutureProvider<List<OwnerWithdrawal>>((
  ref,
) async {
  final search = ref.watch(withdrawalsSearchProvider);
  final kind = ref.watch(withdrawalsKindProvider);
  final from = ref.watch(withdrawalsFromDateProvider);
  final to = ref.watch(withdrawalsToDateProvider);
  final repo = ref.watch(ownerEquityRepositoryProvider);

  final result = await repo.withdrawals(
    PagedRequest(limit: 10000, extra: {
      'search': search.isEmpty ? null : search,
      'kind': kind,
      'from_date': from != null ? isoDate(from) : null,
      'to_date': to != null ? isoDate(to) : null,
    }),
  );
  return switch (result) {
    ApiSuccess(:final data) => data.items,
    ApiFailure(:final error) => throw error,
  };
});

// --- Shared -------------------------------------------------------------

/// Summary cards above the tabs (`GET /owner-equity/summary`, posted rows
/// only). Invalidated together with the grids after create/edit/delete.
final equitySummaryProvider = FutureProvider<EquitySummary>((ref) async {
  final result = await ref.watch(ownerEquityRepositoryProvider).summary();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// Payment method options for both forms.
final equityPaymentMethodsProvider = FutureProvider<List<ExpenseOption>>((
  ref,
) async {
  final result = await ref
      .watch(ownerEquityRepositoryProvider)
      .paymentMethodOptions();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// All items for the goods-withdrawal line selects — one large page via
/// the inventory repository (same approach as the PO form's
/// [poItemsProvider]; the shared itemsProvider is bound to the inventory
/// screen's filter/paging state).
final equityItemsProvider = FutureProvider<List<Item>>((ref) async {
  final result = await ref
      .watch(inventoryRepositoryProvider)
      .items(const PagedRequest(limit: 10000));
  return switch (result) {
    ApiSuccess(:final data) => data.items,
    ApiFailure(:final error) => throw error,
  };
});

/// Sort column/order shared by both grids.
class EquitySort {
  const EquitySort(this.column, this.order);
  final String column;
  final String order;
}
