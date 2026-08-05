import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/purchase_order.dart'
    show PurchaseOrder, PurchaseOrderDetail;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/purchase_order_repository.dart'
    show purchaseOrderRepositoryProvider;

/// All purchase orders (`GET /purchase-orders`, **bare array** — the
/// endpoint has no search/page params, so the grid keeps sorting/filtering
/// client-side like the items screen). The screen invalidates it on
/// refresh.
final purchaseOrdersProvider = FutureProvider<List<PurchaseOrder>>((ref) async {
  final result = await ref.watch(purchaseOrderRepositoryProvider).list();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// Detail for one PO (`GET /purchase-orders/:id`, bare object with the
/// `items` array). autoDispose: each dialog instance owns its fetch, so
/// closing it frees the state.
final purchaseOrderDetailProvider = FutureProvider.autoDispose
    .family<PurchaseOrderDetail, int>((ref, poId) async {
      final result = await ref
          .watch(purchaseOrderRepositoryProvider)
          .detail(poId);
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });
