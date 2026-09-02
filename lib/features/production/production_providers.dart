// Production module providers — BOMs + productions over the paged
// endpoints (PORTING.md §5 `/bom`, `/production`; grid-pagination §7 —
// both lists are server-paginated with `search` + sort). Detail
// providers are autoDispose families owned by their dialogs. Item
// options are fetched from the inventory repository so the forms can
// filter by role (finished goods vs raw materials).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart' show isoDate;
import '../../data/models/bom.dart';
import '../../data/models/item.dart' show Item;
import '../../data/models/production.dart';
import '../../data/models/warehouse.dart' show Warehouse;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/inventory_repository.dart'
    show inventoryRepositoryProvider;
import '../../data/repositories/paged_request.dart'
    show PagedRequest, PagedResponse;
import '../../data/repositories/production_repository.dart'
    show productionRepositoryProvider;
import '../preferences/preference_providers.dart' show initialRange;

/// Server-side search term for the BOM grid (`GET /boms` gained a
/// `search` param — grid-pagination §7.2).
final bomsSearchProvider = StateProvider<String>((ref) => '');

/// Current page (1-based) for the server-side pagination.
final bomsPageProvider = StateProvider<int>((ref) => 1);

/// Rows per page; changing it resets to page 1 (the screen does that).
final bomsLimitProvider = StateProvider<int>((ref) => 10);

/// Server-side sort — the API column name (from the server's
/// `BOM_SORT_COLUMNS` whitelist) plus the order.
class BomSort {
  const BomSort(this.column, this.order);

  final String column;

  /// `ASC` or `DESC`.
  final String order;
}

/// Active server-side sort; null = server default (created_at DESC).
final bomsSortProvider = StateProvider<BomSort?>((ref) => null);

/// One page of BOMs (`GET /boms`, paged envelope). The screen
/// invalidates it on refresh; the BOM form/detail dialogs invalidate it
/// after writes.
final bomsProvider = FutureProvider<PagedResponse<Bom>>((ref) async {
  final search = ref.watch(bomsSearchProvider);
  final page = ref.watch(bomsPageProvider);
  final limit = ref.watch(bomsLimitProvider);
  final sort = ref.watch(bomsSortProvider);

  final result = await ref.watch(productionRepositoryProvider).bomsPaged(
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

/// The full *filtered* BOM list (one large page) — the CSV export must
/// run over every row matching the active search, not just the current
/// page. Watches the same search filter but ignores page/limit/sort.
final filteredBomsProvider = FutureProvider<List<Bom>>((ref) async {
  final search = ref.watch(bomsSearchProvider);
  final result = await ref.watch(productionRepositoryProvider).bomsPaged(
    PagedRequest(page: 1, limit: 10000, search: search.isEmpty ? null : search),
  );
  return switch (result) {
    ApiSuccess(:final data) => data.items,
    ApiFailure(:final error) => throw error,
  };
});

/// Server-side search term for the productions grid (`GET /productions`
/// gained a `search` param — grid-pagination §7.1).
final searchTextProvider = StateProvider<String>((ref) => '');

/// Current page (1-based) for the server-side pagination.
final productionsPageProvider = StateProvider<int>((ref) => 1);

/// Rows per page; changing it resets to page 1 (the screen does that).
final productionsLimitProvider = StateProvider<int>((ref) => 10);

/// Active server-side sort; null = server default (production_date DESC).
final productionsSortProvider = StateProvider<ProductionSort?>((ref) => null);

/// Inclusive date-range filter for productions.
final productionsFromDateProvider =
    StateProvider<DateTime?>((ref) => initialRange(ref).from);
final productionsToDateProvider =
    StateProvider<DateTime?>((ref) => initialRange(ref).to);

/// Server-side sort for productions — the API column name (from the
/// server's `PRODUCTION_SORT_COLUMNS` whitelist) plus the order.
class ProductionSort {
  const ProductionSort(this.column, this.order);

  final String column;

  /// `ASC` or `DESC`.
  final String order;
}

/// One page of production runs (`GET /productions`, paged envelope).
final productionsProvider = FutureProvider<PagedResponse<Production>>((ref) async {
  final search = ref.watch(searchTextProvider);
  final page = ref.watch(productionsPageProvider);
  final limit = ref.watch(productionsLimitProvider);
  final sort = ref.watch(productionsSortProvider);
  final fromDate = ref.watch(productionsFromDateProvider);
  final toDate = ref.watch(productionsToDateProvider);

  final result = await ref
      .watch(productionRepositoryProvider)
      .productionsPaged(
        PagedRequest(
          page: page,
          limit: limit,
          search: search.isEmpty ? null : search,
          sortBy: sort?.column,
          sortOrder: sort?.order ?? 'ASC',
          extra: {
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

/// The full *filtered* productions list (one large page) — the CSV
/// export must run over every row matching the active search, not just
/// the current page.
final filteredProductionsProvider = FutureProvider<List<Production>>((ref) async {
  final search = ref.watch(searchTextProvider);
  final result = await ref
      .watch(productionRepositoryProvider)
      .productionsPaged(
        PagedRequest(
          page: 1,
          limit: 10000,
          search: search.isEmpty ? null : search,
        ),
      );
  return switch (result) {
    ApiSuccess(:final data) => data.items,
    ApiFailure(:final error) => throw error,
  };
});

/// Detail for one BOM (`GET /boms/:id`, bare object with `items`).
/// autoDispose: each dialog instance owns its fetch.
final bomDetailProvider = FutureProvider.autoDispose.family<BomDetail, int>((
  ref,
  bomId,
) async {
  final result = await ref.watch(productionRepositoryProvider).bom(bomId);
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// All BOMs for the production form's BOM picker — the screen's
/// `bomsProvider` only holds one page, so the form pulls a large page
/// directly.
final productionBomOptionsProvider = FutureProvider<List<Bom>>((ref) async {
  final result = await ref
      .watch(productionRepositoryProvider)
      .bomsPaged(const PagedRequest(limit: 10000));
  return switch (result) {
    ApiSuccess(:final data) => data.items,
    ApiFailure(:final error) => throw error,
  };
});

/// Detail for one production run (`GET /productions/:id`, bare object
/// with `inputs`). autoDispose: owned by the detail dialog.
final productionDetailProvider = FutureProvider.autoDispose
    .family<Production, int>((ref, productionId) async {
      final result = await ref
          .watch(productionRepositoryProvider)
          .production(productionId);
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });

/// Finished goods for the BOM/production output pickers — the server
/// filters `GET /inventory/items?is_finished_good=1` (one large page).
/// When that list is empty (a DB without the flag set) the form falls
/// back to every item so a production can still be recorded.
final productionOutputItemsProvider = FutureProvider<List<Item>>((ref) async {
  final repo = ref.watch(inventoryRepositoryProvider);
  final result = await repo.items(
    const PagedRequest(limit: 10000, extra: {'is_finished_good': '1'}),
  );
  return switch (result) {
    ApiSuccess(:final data) => data.items.isEmpty
        ? await ref.read(productionAllItemsProvider.future)
        : data.items,
    ApiFailure(:final error) => throw error,
  };
});

/// Every item, for the BOM material pickers and the fallback above.
/// The material list must not be filtered — BOMs can consume raw
/// materials, components or semi-finished goods alike. Fetched as one
/// large page.
final productionAllItemsProvider = FutureProvider<List<Item>>((ref) async {
  final result = await ref
      .watch(inventoryRepositoryProvider)
      .items(const PagedRequest(limit: 10000));
  return switch (result) {
    ApiSuccess(:final data) => data.items,
    ApiFailure(:final error) => throw error,
  };
});

/// Warehouses for the production form (finished-goods + raw-materials
/// pickers) — shares the inventory module's provider.
final productionWarehousesProvider = FutureProvider<List<Warehouse>>((
  ref,
) async {
  final result = await ref.watch(inventoryRepositoryProvider).warehouses();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});
