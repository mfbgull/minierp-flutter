import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../preferences/preference_providers.dart' show initialRange;

import '../../data/models/invoice.dart' show Invoice;
import '../../data/models/sales_return.dart' show SalesReturn;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/invoice_repository.dart'
    show invoiceRepositoryProvider;

/// Client-side search term (return no / item / customer) — the
/// returns endpoint has no `search` param, so filtering happens in the
/// screen.
final invoiceReturnsSearchProvider = StateProvider<String>((ref) => '');

/// Client-side warehouse filter for the returns grid (warehouse name,
/// derived from the loaded rows). null → all warehouses.
final invoiceReturnsWarehouseProvider = StateProvider<String?>((ref) => null);

/// Client-side date-range filters (ISO strings, applied to
/// `return_date`). The endpoint has no date params.
final invoiceReturnsFromDateProvider = StateProvider<DateTime?>((ref) => initialRange(ref).from);
final invoiceReturnsToDateProvider = StateProvider<DateTime?>((ref) => initialRange(ref).to);

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

/// All invoices for the Process Return picker (unfiltered — returns are
/// created against an invoice, so the picker lists every invoice the
/// user can return against).
final invoiceReturnPickerProvider = FutureProvider<List<Invoice>>((ref) async {
  final result = await ref.watch(invoiceRepositoryProvider).invoices();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});
