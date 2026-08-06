import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/purchase_return.dart' show PurchaseReturn;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/purchase_repository.dart'
    show purchaseRepositoryProvider;

/// Purchase-return history (`GET /purchases/returns`, **bare array** — the
/// endpoint has no search/page params, so the grid keeps sorting/filtering
/// client-side like the items screen). The screen invalidates it on
/// refresh.
final purchaseReturnsProvider = FutureProvider<List<PurchaseReturn>>((
  ref,
) async {
  final result = await ref.watch(purchaseRepositoryProvider).returns();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});
