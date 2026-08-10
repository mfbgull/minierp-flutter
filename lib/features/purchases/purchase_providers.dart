import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/purchase.dart' show Purchase;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/purchase_repository.dart'
    show purchaseRepositoryProvider;

/// Direct purchases (`GET /purchases`, **bare array** — no search/page
/// params, so the grid keeps sorting/filtering client-side like the
/// items screen). The screen invalidates it on refresh, and the
/// return-processing dialog invalidates it after a successful return.
final purchasesProvider = FutureProvider<List<Purchase>>((ref) async {
  final result = await ref.watch(purchaseRepositoryProvider).list();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// Client-side search term for the purchases grid (no search param on
/// the endpoint — the screen filters the loaded rows).
final purchasesSearchProvider = StateProvider<String>((ref) => '');

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
