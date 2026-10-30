import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart' show isoDate;
import '../../data/models/company_supplier.dart' show CompanySupplier;
import '../../data/models/item.dart' show Item, ItemCompany;
import '../../data/models/physical_count.dart' show PhysicalCount;
import '../../data/models/stock_balance.dart' show StockBalance;
import '../../data/models/stock_movement.dart' show StockMovement;
import '../../data/models/supplier.dart' show Supplier;
import '../../data/models/warehouse.dart' show Warehouse;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/inventory_repository.dart'
    show ItemDetail, PhysicalCountDetail, inventoryRepositoryProvider;
import '../../data/repositories/paged_request.dart'
    show PagedRequest, PagedResponse;
import '../../data/repositories/supplier_repository.dart'
    show supplierRepositoryProvider;
import '../preferences/preference_providers.dart' show initialRange;

/// Server-side search term for the items grid (PORTING.md §2: list
/// endpoints accept `search`; the items endpoint filters code/name/desc).
/// Updated with a debounce by the screen; an empty value omits the param.
final itemsSearchProvider = StateProvider<String>((ref) => '');

/// When true, only items at/below their reorder level are shown — sent
/// as `GET /inventory/items?low_stock=1` (the same paged path; search is
/// enabled in this mode too).
final itemsLowStockOnlyProvider = StateProvider<bool>((ref) => false);

/// Current page (1-based) for the items grid.
final itemsPageProvider = StateProvider<int>((ref) => 1);

/// Rows per page for the items grid; changing it resets to page 1 (the
/// screen does that).
final itemsLimitProvider = StateProvider<int>((ref) => 10);

/// Active server-side sort; null = server default (item_name ASC).
final itemsSortProvider = StateProvider<GridSort?>((ref) => null);

/// One page of items (`GET /inventory/items` returns a `pagination`
/// block). Re-runs when search / low-stock toggle / paging / sort
/// change; the screen invalidates it on refresh.
final itemsProvider = FutureProvider<PagedResponse<Item>>((ref) async {
  final lowStockOnly = ref.watch(itemsLowStockOnlyProvider);
  final search = ref.watch(itemsSearchProvider);
  final page = ref.watch(itemsPageProvider);
  final limit = ref.watch(itemsLimitProvider);
  final sort = ref.watch(itemsSortProvider);
  final repo = ref.watch(inventoryRepositoryProvider);

  final result = await repo.items(
    PagedRequest(
      page: page,
      limit: limit,
      search: search.isEmpty ? null : search,
      sortBy: sort?.column,
      sortOrder: sort?.order ?? 'ASC',
      extra: lowStockOnly ? {'low_stock': '1'} : null,
    ),
  );

  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// All items (unfiltered, active, alphabetical) for pickers and filters
/// that need the full list — the grid's own `itemsProvider` only holds
/// the current page (limit 10). Fetched as one large page (the endpoint
/// has no limit cap; matches the pre-pagination behavior of loading the
/// full list). Watched by item-picker dialogs (transfer/adjustment/
/// purchase) and the forecast screens' item/category filters.
final allItemsProvider = FutureProvider<List<Item>>((ref) async {
  final result = await ref
      .watch(inventoryRepositoryProvider)
      .items(PagedRequest(limit: 10000));
  return switch (result) {
    ApiSuccess(:final data) => data.items,
    ApiFailure(:final error) => throw error,
  };
});

/// Detail for one item (`GET /inventory/items/:id`, bare object with the
/// `stock_by_warehouse` breakdown). autoDispose: each dialog instance
/// owns its fetch, so closing it frees the state.
final itemDetailProvider = FutureProvider.autoDispose.family<ItemDetail, int>((
  ref,
  itemId,
) async {
  final result = await ref
      .watch(inventoryRepositoryProvider)
      .itemDetail(itemId);
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// Existing categories for the item form's dropdown
/// (`GET /inventory/items-categories`, bare `[{category}]`).
final itemCategoriesProvider = FutureProvider<List<String>>((ref) async {
  final result = await ref.watch(inventoryRepositoryProvider).categories();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

final itemCompaniesProvider = FutureProvider<List<ItemCompany>>((ref) async {
  final repository = ref.watch(inventoryRepositoryProvider);
  final companies = <ItemCompany>[];
  var page = 1;
  while (true) {
    final result = await repository.companies(PagedRequest(
      page: page, limit: 200, extra: const {'status': 'active'},
    ));
    switch (result) {
      case ApiSuccess(:final data):
        companies.addAll(data.items);
        if (!data.hasNext) return companies;
        page++;
      case ApiFailure(:final error):
        throw error;
    }
  }
});

final itemCompanyProvider = FutureProvider.family<ItemCompany, int>((ref, id) async {
  final result = await ref.watch(inventoryRepositoryProvider).company(id);
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

class ManagedCompaniesArgs {
  const ManagedCompaniesArgs({
    required this.page,
    required this.limit,
    this.search = '',
    this.status = 'active',
  });

  final int page;
  final int limit;
  final String search;
  final String status;

  @override
  bool operator ==(Object other) =>
      other is ManagedCompaniesArgs &&
      other.page == page &&
      other.limit == limit &&
      other.search == search &&
      other.status == status;

  @override
  int get hashCode => Object.hash(page, limit, search, status);
}

final managedCompaniesProvider = FutureProvider.autoDispose
    .family<PagedResponse<ItemCompany>, ManagedCompaniesArgs>((ref, args) async {
      final result = await ref
          .watch(inventoryRepositoryProvider)
          .companies(
            PagedRequest(
              page: args.page,
              limit: args.limit,
              search: args.search.isEmpty ? null : args.search,
              extra: {'status': args.status},
            ),
          );
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });

class CompanyProductsArgs {
  const CompanyProductsArgs({
    required this.companyId,
    required this.page,
    required this.limit,
  });

  final int companyId;
  final int page;
  final int limit;

  @override
  bool operator ==(Object other) =>
      other is CompanyProductsArgs &&
      other.companyId == companyId &&
      other.page == page &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(companyId, page, limit);
}

final companyProductsProvider = FutureProvider.autoDispose
    .family<PagedResponse<Item>, CompanyProductsArgs>((ref, args) async {
      final result = await ref
          .watch(inventoryRepositoryProvider)
          .companyProducts(
            args.companyId,
            PagedRequest(page: args.page, limit: args.limit),
          );
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });

class CompanySupplierListArgs {
  const CompanySupplierListArgs({
    required this.companyId,
    required this.page,
    required this.limit,
  });

  final int companyId;
  final int page;
  final int limit;

  @override
  bool operator ==(Object other) =>
      other is CompanySupplierListArgs &&
      other.companyId == companyId &&
      other.page == page &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(companyId, page, limit);
}

final companySuppliersProvider = FutureProvider.autoDispose
    .family<PagedResponse<CompanySupplier>, CompanySupplierListArgs>((
      ref,
      args,
    ) async {
      final result = await ref
          .watch(inventoryRepositoryProvider)
          .companySuppliers(
            args.companyId,
            PagedRequest(page: args.page, limit: args.limit),
          );
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });

/// Active suppliers offered by the company detail's manual-link picker.
/// One large page matches the other picker providers; the picker filters
/// locally.
final linkableSuppliersProvider = FutureProvider<List<Supplier>>((ref) async {
  final result = await ref.watch(supplierRepositoryProvider).list(
    PagedRequest(limit: 10000, extra: const {'status': 'active'}),
  );
  return switch (result) {
    ApiSuccess(:final data) => data.items,
    ApiFailure(:final error) => throw error,
  };
});

/// Refreshes every company-scoped query after a company or link mutation.
void invalidateCompanyQueries(WidgetRef ref) {
  ref.invalidate(managedCompaniesProvider);
  ref.invalidate(itemCompaniesProvider);
  ref.invalidate(itemCompanyProvider);
  ref.invalidate(itemsProvider);
  ref.invalidate(itemDetailProvider);
  ref.invalidate(companyProductsProvider);
  ref.invalidate(companySuppliersProvider);
}

/// Units of measure for the item form's dropdown
/// (`GET /inventory/items-uom`, bare `[string]`).
final itemUomsProvider = FutureProvider<List<String>>((ref) async {
  final result = await ref.watch(inventoryRepositoryProvider).unitsOfMeasure();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

// --- Warehouse providers ---

final warehousesProvider = FutureProvider<List<Warehouse>>((ref) async {
  final result = await ref.watch(inventoryRepositoryProvider).warehouses();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

final warehouseSearchProvider = StateProvider<String>((ref) => '');

final warehousesSearchFilteredProvider = Provider<List<Warehouse>>((ref) {
  final warehouses = ref.watch(warehousesProvider);
  final term = ref.watch(warehouseSearchProvider).toLowerCase().trim();

  return switch (warehouses) {
    AsyncData(:final value) when term.isEmpty => value,
    AsyncData(:final value) => value.where((w) {
      final q = term;
      return w.warehouseCode.toLowerCase().contains(q) ||
          (w.warehouseName ?? '').toLowerCase().contains(q) ||
          (w.location ?? '').toLowerCase().contains(q);
    }).toList(),
    _ => const <Warehouse>[],
  };
});

// --- Stock movement providers ---

/// A single stock movement's detail (`GET /inventory/stock-movements/:id`:
/// bare joined movement). autoDispose: owned by the movement detail dialog,
/// so every open refetches fresh data.
final stockMovementDetailProvider = FutureProvider.autoDispose
    .family<StockMovement, int>((ref, movementId) async {
      final result = await ref
          .watch(inventoryRepositoryProvider)
          .stockMovement(movementId);
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });

/// Selected movement-type filter for the movements tab (null = all).
final movementTypeFilterProvider = StateProvider<String?>((ref) => null);

/// Server-side sort — the API column name (from the endpoint's
/// `*_SORT_COLUMNS` whitelist) plus the order.
class GridSort {
  const GridSort(this.column, this.order);

  final String column;

  /// `ASC` or `DESC`.
  final String order;
}

/// Current page (1-based) for the stock-movements pagination.
final stockMovementsPageProvider = StateProvider<int>((ref) => 1);

/// Rows per page; changing it resets to page 1 (the screen does that).
final stockMovementsLimitProvider = StateProvider<int>((ref) => 10);

/// Active server-side sort; null = server default (movement_date DESC).
final stockMovementsSortProvider = StateProvider<GridSort?>((ref) => null);

/// Inclusive date-range filter for stock movements.
final stockMovementsFromDateProvider = StateProvider<DateTime?>(
  (ref) => initialRange(ref).from,
);
final stockMovementsToDateProvider = StateProvider<DateTime?>(
  (ref) => initialRange(ref).to,
);

/// All movements (unfiltered, newest-first) for the movement-detail
/// dialog's counterpart lookup — the grid's own provider only holds the
/// current page, and the counterpart (e.g. a transfer's other leg) can
/// sit anywhere in the list. Fetched as one large page (the endpoint has
/// no limit cap; matches the pre-pagination behavior of loading the full
/// list). autoDispose: owned by the open dialog.
final allStockMovementsProvider =
    FutureProvider.autoDispose<List<StockMovement>>((ref) async {
      final repo = ref.watch(inventoryRepositoryProvider);
      final result = await repo.stockMovements(PagedRequest(limit: 10000));
      return switch (result) {
        ApiSuccess(:final data) => data.items,
        ApiFailure(:final error) => throw error,
      };
    });

/// One page of stock movements, keyed by the movement-type filter
/// (null = all) — server-paginated like customers (`GET
/// /inventory/stock-movements` returns a `pagination` block). Re-runs
/// when any of the paging state changes; the screen invalidates it on
/// refresh and on the "back to All" filter switch.
final stockMovementsProvider =
    FutureProvider.family<PagedResponse<StockMovement>, String?>((
      ref,
      type,
    ) async {
      final page = ref.watch(stockMovementsPageProvider);
      final limit = ref.watch(stockMovementsLimitProvider);
      final sort = ref.watch(stockMovementsSortProvider);
      final fromDate = ref.watch(stockMovementsFromDateProvider);
      final toDate = ref.watch(stockMovementsToDateProvider);
      final repo = ref.watch(inventoryRepositoryProvider);
      final result = await repo.stockMovements(
        PagedRequest(
          page: page,
          limit: limit,
          sortBy: sort?.column,
          sortOrder: sort?.order ?? 'ASC',
          extra: {
            'movement_type': ?type,
            if (fromDate != null) 'date_from': isoDate(fromDate),
            if (toDate != null) 'date_to': isoDate(toDate),
          },
        ),
      );
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });

// --- Stock balance providers ---

/// Server-side search term for the stock-balances grid (sent as the
/// endpoint's `search` param — filters item code/name, warehouse name).
final stockBalancesSearchProvider = StateProvider<String>((ref) => '');

/// Selected warehouse filter for the stock-balances grid (empty string =
/// all warehouses) — sent as the endpoint's `warehouse_code` param.
final stockBalancesWarehouseFilterProvider = StateProvider<String>((ref) => '');

/// Current page (1-based) for the stock-balances grid.
final stockBalancesPageProvider = StateProvider<int>((ref) => 1);

/// Rows per page; changing it resets to page 1 (the screen does that).
final stockBalancesLimitProvider = StateProvider<int>((ref) => 10);

/// Active server-side sort; null = server default (item_code ASC).
final stockBalancesSortProvider = StateProvider<GridSort?>((ref) => null);

/// One page of stock balances (`GET /inventory/stock-balances` returns a
/// `pagination` block). Re-runs when search / warehouse filter / paging /
/// sort change; the screen invalidates it on refresh.
final stockBalancesProvider = FutureProvider<PagedResponse<StockBalance>>((
  ref,
) async {
  final search = ref.watch(stockBalancesSearchProvider);
  final warehouse = ref.watch(stockBalancesWarehouseFilterProvider);
  final page = ref.watch(stockBalancesPageProvider);
  final limit = ref.watch(stockBalancesLimitProvider);
  final sort = ref.watch(stockBalancesSortProvider);
  final repo = ref.watch(inventoryRepositoryProvider);

  final result = await repo.stockBalances(
    PagedRequest(
      page: page,
      limit: limit,
      search: search.isEmpty ? null : search,
      sortBy: sort?.column,
      sortOrder: sort?.order ?? 'ASC',
      extra: warehouse.isEmpty ? null : {'warehouse_code': warehouse},
    ),
  );
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// One item's stock ledger (`GET /inventory/stock-ledger/:itemId` — its
/// movement history newest-first, warehouse join only). Keyed on
/// `(itemId, warehouseId)` — a null warehouseId = all warehouses. The
/// dialog owns the filter in local state, so each open refetches fresh.
final stockLedgerProvider = FutureProvider.autoDispose
    .family<List<StockMovement>, (int, int?)>((ref, key) async {
      final (itemId, warehouseId) = key;
      final repo = ref.watch(inventoryRepositoryProvider);
      final result = await repo.stockLedger(itemId, warehouseId: warehouseId);
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });

// --- Physical count providers ---

/// Server-side search term for the physical-counts grid (sent as the
/// endpoint's `search` param — filters count no, warehouse, status).
final physicalCountsSearchProvider = StateProvider<String>((ref) => '');

/// Current page (1-based) for the physical-counts grid.
final physicalCountsPageProvider = StateProvider<int>((ref) => 1);

/// Rows per page; changing it resets to page 1 (the screen does that).
final physicalCountsLimitProvider = StateProvider<int>((ref) => 10);

/// Active server-side sort; null = server default (created_at DESC).
final physicalCountsSortProvider = StateProvider<GridSort?>((ref) => null);

/// One page of physical counts (`GET /inventory/physical-counts` returns
/// a `pagination` block). Re-runs when search / paging / sort change;
/// the screen invalidates it on refresh.
final physicalCountsProvider = FutureProvider<PagedResponse<PhysicalCount>>((
  ref,
) async {
  final search = ref.watch(physicalCountsSearchProvider);
  final page = ref.watch(physicalCountsPageProvider);
  final limit = ref.watch(physicalCountsLimitProvider);
  final sort = ref.watch(physicalCountsSortProvider);
  final repo = ref.watch(inventoryRepositoryProvider);

  final result = await repo.physicalCounts(
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

/// A single physical count's detail (`GET /inventory/physical-counts/:id`:
/// header + item lines). autoDispose: owned by the detail dialog.
final physicalCountDetailProvider = FutureProvider.autoDispose
    .family<PhysicalCountDetail, int>((ref, countId) async {
      final result = await ref
          .watch(inventoryRepositoryProvider)
          .physicalCountDetail(countId);
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });
