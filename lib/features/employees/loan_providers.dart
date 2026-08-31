// Employee Loan providers — Riverpod state for loan CRUD, dashboard panel,
// and the salary-pay dialog's active-loan banner.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import 'loan_models.dart';
import 'loan_repository.dart';

// ═══════════════════════════════════════════════════════════════
//  Employee-scoped providers (per-employee detail dialog)
// ═══════════════════════════════════════════════════════════════

/// Loans list for one employee (`GET /employees/:id/loans`).
/// autoDispose: each dialog instance owns its fetch.
final employeeLoansProvider = FutureProvider.autoDispose
    .family<LoansListResponse, int>((ref, employeeId) async {
  final result = await ref.watch(loanRepositoryProvider).getLoans(employeeId);
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// Active loans for one employee (used by salary pay dialog).
/// Derived from employeeLoansProvider — filters to active/overdue.
final employeeActiveLoansProvider = Provider.autoDispose
    .family<List<EmployeeLoan>, int>((ref, employeeId) {
  final loansResponse = ref.watch(employeeLoansProvider(employeeId));
  return loansResponse.when(
    data: (data) => data.loans
        .where((l) => l.status == 'active' || l.status == 'overdue')
        .toList(),
    loading: () => [],
    error: (_, _) => [],
  );
});

/// Loan detail with repayments (`GET /employees/:id/loans/:loanId`).
/// autoDispose: each dialog instance owns its fetch.
final loanDetailProvider = FutureProvider.autoDispose
    .family<LoanDetail, ({int employeeId, int loanId})>(
        (ref, params) async {
  final result = await ref
      .watch(loanRepositoryProvider)
      .getLoanDetail(params.employeeId, params.loanId);
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

// ═══════════════════════════════════════════════════════════════
//  Dashboard providers (global)
// ═══════════════════════════════════════════════════════════════

/// Active loans panel data (`GET /dashboard/active-loans`).
final dashboardActiveLoansProvider2 =
    FutureProvider<ActiveLoansResult>((ref) async {
  final result = await ref.watch(loanRepositoryProvider).activeLoans();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});
