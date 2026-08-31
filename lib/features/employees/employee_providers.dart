// Employees providers — a server-paginated list (`GET /employees` returns
// a `{page, limit, total, totalPages}` block, so this is the second
// server-paginated screen after customers), plus per-dialog detail
// fetches. Search / department / status filters re-run the list future;
// the screen invalidates it on refresh and after create/edit/delete/pay.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/paged_request.dart' show PagedResponse;
import 'employee_models.dart';
import 'employee_repository.dart'
    show EmployeeFilters, employeeRepositoryProvider;

/// Debounced search term for the employees grid (code/name/email/phone/
/// cnic on the server). Empty value omits the param.
final employeesSearchProvider = StateProvider<String>((ref) => '');

/// Active department filter — null means "all departments". The options
/// come from the loaded rows (there is no reference endpoint).
final employeesDepartmentProvider = StateProvider<String?>((ref) => null);

/// Active status filter — `active` / `inactive`; null means the server
/// default (active list).
final employeesStatusProvider = StateProvider<String?>((ref) => null);

/// Current page (1-based) for the server-side pagination.
final employeesPageProvider = StateProvider<int>((ref) => 1);

/// Rows per page; changing it resets to page 1 (the screen does that).
final employeesLimitProvider = StateProvider<int>((ref) => 10);

/// One page of employees. Re-runs when any filter or paging state changes;
/// the screen invalidates it on refresh and after mutations.
final employeesProvider = FutureProvider<PagedResponse<Employee>>((ref) async {
  final search = ref.watch(employeesSearchProvider);
  final department = ref.watch(employeesDepartmentProvider);
  final status = ref.watch(employeesStatusProvider);
  final page = ref.watch(employeesPageProvider);
  final limit = ref.watch(employeesLimitProvider);

  final result = await ref
      .watch(employeeRepositoryProvider)
      .list(
        EmployeeFilters(
          search: search.isEmpty ? null : search,
          department: department,
          status: status,
          page: page,
          limit: limit,
        ),
      );
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// Distinct departments from the *loaded* page (there is no departments
/// reference endpoint) — the dropdown only filters by what exists.
final employeesDepartmentsProvider = Provider<List<String>>((ref) {
  final rows =
      ref.watch(employeesProvider).valueOrNull?.items ?? const <Employee>[];
  final seen = <String>{};
  return [
    for (final e in rows)
      if (e.department != null && e.department!.isNotEmpty)
        if (seen.add(e.department!)) e.department!,
  ]..sort();
});

/// Server-generated employee code for the create form
/// (`GET /employees/next-code`).
final employeeNextCodeProvider = FutureProvider.autoDispose<String>((ref) async {
  final result = await ref.watch(employeeRepositoryProvider).nextCode();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure() => 'EMP-001',
  };
});

/// Detail for one employee (`GET /employees/:id`, enveloped object).
/// autoDispose: each dialog instance owns its fetch.
final employeeDetailProvider = FutureProvider.autoDispose
    .family<Employee, int>((ref, employeeId) async {
      final result = await ref
          .watch(employeeRepositoryProvider)
          .get(employeeId);
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });

/// Salary history for one employee (`GET /employees/:id/salary/history`).
final employeeSalaryHistoryProvider = FutureProvider.autoDispose
    .family<List<SalaryMonthSummary>, int>((ref, employeeId) async {
      final result = await ref
          .watch(employeeRepositoryProvider)
          .salaryHistory(employeeId);
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });



/// Documents for one employee (`GET /employees/:id/documents`).
final employeeDocumentsProvider = FutureProvider.autoDispose
    .family<List<EmployeeDocument>, int>((ref, employeeId) async {
      final result = await ref
          .watch(employeeRepositoryProvider)
          .documents(employeeId);
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });

