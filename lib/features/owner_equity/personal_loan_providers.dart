// Owner Personal Loan providers — Riverpod state for loan CRUD,
// borrower management, and summary cards.
// Purely record-keeping — no GL impact.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../preferences/preference_providers.dart' show initialRange;

import '../../core/utils/date_utils.dart' show isoDate;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import 'personal_loan_models.dart';
import 'personal_loan_repository.dart';
import '../../data/repositories/paged_request.dart' show PagedRequest, PagedResponse;

// ── Loan list tab state ─────────────────────────────────────

final personalLoansSearchProvider = StateProvider<String>((ref) => '');
final personalLoansStatusProvider = StateProvider<String?>((ref) => null);
final personalLoansFromDateProvider =
    StateProvider<DateTime?>((ref) => initialRange(ref).from);
final personalLoansToDateProvider =
    StateProvider<DateTime?>((ref) => initialRange(ref).to);
final personalLoansPageProvider = StateProvider<int>((ref) => 1);
final personalLoansLimitProvider = StateProvider<int>((ref) => 10);
final personalLoansSortProvider =
    StateProvider<PersonalLoansSort?>((ref) => null);

/// Paginated loan list — `GET /owner-equity/personal-loans`.
final personalLoansProvider =
    FutureProvider<PagedResponse<PersonalLoan>>((ref) async {
  final search = ref.watch(personalLoansSearchProvider);
  final status = ref.watch(personalLoansStatusProvider);
  final from = ref.watch(personalLoansFromDateProvider);
  final to = ref.watch(personalLoansToDateProvider);
  final page = ref.watch(personalLoansPageProvider);
  final limit = ref.watch(personalLoansLimitProvider);
  final sort = ref.watch(personalLoansSortProvider);
  final repo = ref.watch(personalLoanRepositoryProvider);

  final result = await repo.listLoans(
    PagedRequest(
      page: page,
      limit: limit,
      search: search.isEmpty ? null : search,
      sortBy: sort?.column,
      sortOrder: sort?.order ?? 'DESC',
      extra: {
        'status': status,
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

/// Full filtered list (10k) for CSV export.
final allPersonalLoansProvider = FutureProvider<List<PersonalLoan>>(
  (ref) async {
    final search = ref.watch(personalLoansSearchProvider);
    final status = ref.watch(personalLoansStatusProvider);
    final from = ref.watch(personalLoansFromDateProvider);
    final to = ref.watch(personalLoansToDateProvider);
    final repo = ref.watch(personalLoanRepositoryProvider);

    final result = await repo.listLoans(
      PagedRequest(limit: 10000, extra: {
        'search': search.isEmpty ? null : search,
        'status': status,
        'from_date': from != null ? isoDate(from) : null,
        'to_date': to != null ? isoDate(to) : null,
      }),
    );
    return switch (result) {
      ApiSuccess(:final data) => data.items,
      ApiFailure(:final error) => throw error,
    };
  },
);

/// Summary cards — `GET /owner-equity/personal-loans/summary`.
final personalLoanSummaryProvider =
    FutureProvider<PersonalLoanSummary>((ref) async {
  final result = await ref.watch(personalLoanRepositoryProvider).summary();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

// ── Borrower list state ─────────────────────────────────────

final borrowersSearchProvider = StateProvider<String>((ref) => '');
final borrowersStatusProvider = StateProvider<String?>((ref) => null);

/// Borrower list — `GET /owner-equity/borrowers`.
final borrowersProvider =
    FutureProvider<List<PersonalLoanBorrower>>((ref) async {
  final search = ref.watch(borrowersSearchProvider);
  final status = ref.watch(borrowersStatusProvider);
  final repo = ref.watch(personalLoanRepositoryProvider);

  final result = await repo.listBorrowers(
    search: search.isEmpty ? null : search,
    status: status,
  );
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// Sort column/order for the loan grid.
class PersonalLoansSort {
  const PersonalLoansSort(this.column, this.order);
  final String column;
  final String order;
}
