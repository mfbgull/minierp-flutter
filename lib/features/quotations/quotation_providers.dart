import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../preferences/preference_providers.dart' show initialRange;

import '../../data/models/quotation.dart' show Quotation, QuotationDetail;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/quotation_repository.dart'
    show quotationRepositoryProvider;

/// Client-side status filter for the quotations grid (raw status
/// value). null → all statuses.
final quotationsStatusProvider = StateProvider<String?>((ref) => null);

/// Client-side search term (quotation no / customer name) — the
/// quotations endpoint has no `search` param, so filtering happens in
/// the screen.
final quotationsSearchProvider = StateProvider<String>((ref) => '');

/// Client-side date-range filters (ISO strings, applied to
/// `quotation_date`). The endpoint has no date params.
final quotationsFromDateProvider = StateProvider<DateTime?>((ref) => initialRange(ref).from);
final quotationsToDateProvider = StateProvider<DateTime?>((ref) => initialRange(ref).to);

/// All quotations (`GET /quotations`, **bare array** — the endpoint has
/// no search/page params, so the grid keeps sorting/filtering
/// client-side like the items screen). The screen invalidates it on
/// refresh.
final quotationsProvider = FutureProvider<List<Quotation>>((ref) async {
  final result = await ref.watch(quotationRepositoryProvider).list();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// Detail for one quotation (`GET /quotations/:id`, bare object with the
/// `items` array). autoDispose: each dialog instance owns its fetch, so
/// closing it frees the state.
final quotationDetailProvider = FutureProvider.autoDispose
    .family<QuotationDetail, int>((ref, quotationId) async {
      final result = await ref
          .watch(quotationRepositoryProvider)
          .detail(quotationId);
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });
