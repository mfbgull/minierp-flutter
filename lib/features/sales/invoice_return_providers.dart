import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/sales_return.dart' show SalesReturn;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/invoice_repository.dart'
    show invoiceRepositoryProvider;

/// Invoice-return history (`GET /invoices/returns`, **bare array** — the
/// endpoint has no search/page params, so the grid keeps sorting/filtering
/// client-side like the items screen). The screen invalidates it on
/// refresh; the process-return dialog invalidates it after a successful
/// POST so a new return appears immediately.
final invoiceReturnsProvider = FutureProvider<List<SalesReturn>>((ref) async {
  final result = await ref.watch(invoiceRepositoryProvider).returns();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});
