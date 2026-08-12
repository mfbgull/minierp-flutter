import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/ledger_entry.dart' show LedgerEntry;
import '../../data/models/payment.dart' show Payment;
import '../../data/models/purchase_order.dart' show PurchaseOrder;
import '../../data/models/supplier.dart' show Supplier;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/invoice_repository.dart'
    show invoiceRepositoryProvider;
import '../../data/repositories/paged_request.dart'
    show PagedRequest, PagedResponse;
import '../../data/repositories/purchase_order_repository.dart'
    show POSummary, purchaseOrderRepositoryProvider;
import '../../data/repositories/supplier_repository.dart'
    show SupplierBalance, SupplierStatement, supplierRepositoryProvider;

/// Server-side sort — the API column name (from the server's
/// `SUPPLIER_SORT_COLUMNS` whitelist) plus the order.
class SupplierSort {
  const SupplierSort(this.column, this.order);

  final String column;

  /// `ASC` or `DESC`.
  final String order;
}

/// Server-side status filter (`?status=active` / `?status=inactive`);
/// null → all suppliers (param omitted). Mirrors the web suppliers page's
/// All/Active/Inactive tabs.
final suppliersStatusProvider = StateProvider<String?>((ref) => null);

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
  final status = ref.watch(suppliersStatusProvider);

  final result = await ref
      .watch(supplierRepositoryProvider)
      .list(
        PagedRequest(
          page: page,
          limit: limit,
          search: search.isEmpty ? null : search,
          sortBy: sort?.column,
          sortOrder: sort?.order ?? 'ASC',
          // Endpoint-specific filter: the suppliers list endpoint accepts
          // `?status=active|inactive`.
          extra: status == null ? null : {'status': status},
        ),
      );

  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// Detail for one supplier (`GET /suppliers/:id`, bare object). autoDispose:
/// each detail page owns its fetch, so leaving it frees the state.
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
/// newest-first by transaction_date). autoDispose: each ledger UI owns its
/// fetch, so leaving it frees the state.
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

/// The supplier's balance (`GET /suppliers/:id/balance`, enveloped
/// `{supplierId, supplierName, currentBalance}`) — the detail header's
/// Balance quick-stat source. autoDispose: owned by the detail page.
final supplierBalanceProvider = FutureProvider.autoDispose
    .family<SupplierBalance, int>((ref, supplierId) async {
      final result = await ref
          .watch(supplierRepositoryProvider)
          .balance(supplierId);
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });

/// The supplier's purchase orders (`GET /purchase-orders?supplier_id=<id>`,
/// bare array) — the POs tab + the payment modal's allocation source.
/// autoDispose: owned by the detail page.
final supplierPurchaseOrdersProvider = FutureProvider.autoDispose
    .family<List<PurchaseOrder>, int>((ref, supplierId) async {
      final result = await ref
          .watch(purchaseOrderRepositoryProvider)
          .list(supplierId: supplierId);
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });

/// PO summary for the supplier (`GET /purchase-orders/summary/supplier/<id>`,
/// bare `POSummary`) — the Overview tab's PO-status counts. autoDispose:
/// owned by the detail page.
final supplierPOSummaryProvider = FutureProvider.autoDispose
    .family<POSummary, int>((ref, supplierId) async {
      final result = await ref
          .watch(purchaseOrderRepositoryProvider)
          .summaryBySupplier(supplierId);
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });

/// The supplier's payments (`GET /payments?supplierId=<id>` — the web
/// Payments tab's query). autoDispose: owned by the detail page.
final supplierPaymentsProvider = FutureProvider.autoDispose
    .family<List<Payment>, int>((ref, supplierId) async {
      final result = await ref
          .watch(invoiceRepositoryProvider)
          .paymentsForSupplier(supplierId);
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });

/// Statement fetch arguments — the family key (supplier id + date range).
class SupplierStatementArgs {
  const SupplierStatementArgs({
    required this.supplierId,
    required this.fromDate,
    required this.toDate,
  });

  final int supplierId;
  final String fromDate;
  final String toDate;

  @override
  bool operator ==(Object other) =>
      other is SupplierStatementArgs &&
      other.supplierId == supplierId &&
      other.fromDate == fromDate &&
      other.toDate == toDate;

  @override
  int get hashCode => Object.hash(supplierId, fromDate, toDate);
}

/// Bumped by [invalidateSupplierQueries] so an open Statement tab refetches
/// after a payment mutation (the statement's own key — the date range — is
/// invisible to the mutating code).
final supplierStatementVersionProvider = StateProvider<int>((ref) => 0);

/// One supplier statement (`GET /suppliers/:id/statement?fromDate&toDate`).
/// autoDispose: owned by the Statement tab.
final supplierStatementProvider = FutureProvider.autoDispose
    .family<SupplierStatement, SupplierStatementArgs>((ref, args) async {
      ref.watch(supplierStatementVersionProvider);
      final result = await ref.watch(supplierRepositoryProvider).statement(
        args.supplierId,
        fromDate: args.fromDate,
        toDate: args.toDate,
      );
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });

/// Invalidates every supplier-scoped query after a mutation (record/edit/
/// delete payment), so every detail tab refetches.
void invalidateSupplierQueries(WidgetRef ref, int supplierId) {
  ref.invalidate(supplierDetailProvider(supplierId));
  ref.invalidate(supplierLedgerProvider(supplierId));
  ref.invalidate(supplierBalanceProvider(supplierId));
  ref.invalidate(supplierPurchaseOrdersProvider(supplierId));
  ref.invalidate(supplierPOSummaryProvider(supplierId));
  ref.invalidate(supplierPaymentsProvider(supplierId));
  ref.read(supplierStatementVersionProvider.notifier).state++;
}
