// Employee Loan repository — typed against `server/src/routes/employees.ts`
// loan endpoints.
//
// Endpoint shapes (verified against the spec):
// - `GET /employees/:id/loans` → `{success, data: {loans, summary}}`
// - `POST /employees/:id/loans` → `{success, data: EmployeeLoan}` (201)
// - `GET /employees/:id/loans/:loanId` → `{success, data: LoanDetail}`
// - `POST /employees/:id/loans/:loanId/repay` → `{success, data: RepayLoanResult}` (201)
// - `POST /employees/:id/loans/:loanId/write-off` → `{success, data: WriteOffLoanResult}`
// - `DELETE /employees/:id/loans/:loanId` → 200 `{success: true}`
// - `POST /employees/:id/loans/:loanId/repayments/:rid/void` → `{success, data}`

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart' show dioProvider;
import '../../core/api/endpoints.dart' show ApiEndpoints;
import '../../data/repositories/api_result.dart';
import '../../data/repositories/repository_client.dart';
import 'loan_models.dart';

class LoanRepository {
  LoanRepository(this._client);

  final RepositoryClient _client;

  /// `GET /employees/:id/loans` — list all loans with summary.
  Future<ApiResult<LoansListResponse>> getLoans(int employeeId) => _client.get(
        '${ApiEndpoints.employees}/$employeeId/loans',
        parse: (Object? json) => LoansListResponse.fromJson(
            json! as Map<String, dynamic>),
      );

  /// `POST /employees/:id/loans` — create a new loan.
  Future<ApiResult<EmployeeLoan>> createLoan(
    int employeeId,
    Map<String, dynamic> body,
  ) =>
      _client.post(
        '${ApiEndpoints.employees}/$employeeId/loans',
        body: body,
        parse: (Object? json) =>
            EmployeeLoan.fromJson(json! as Map<String, dynamic>),
      );

  /// `GET /employees/:id/loans/:loanId` — loan detail with repayments.
  Future<ApiResult<LoanDetail>> getLoanDetail(
    int employeeId,
    int loanId,
  ) =>
      _client.get(
        '${ApiEndpoints.employees}/$employeeId/loans/$loanId',
        parse: (Object? json) =>
            LoanDetail.fromJson(json! as Map<String, dynamic>),
      );

  /// `POST /employees/:id/loans/:loanId/repay` — record a repayment.
  Future<ApiResult<RepayLoanResult>> repayLoan(
    int employeeId,
    int loanId,
    Map<String, dynamic> body,
  ) =>
      _client.post(
        '${ApiEndpoints.employees}/$employeeId/loans/$loanId/repay',
        body: body,
        parse: (Object? json) =>
            RepayLoanResult.fromJson(json! as Map<String, dynamic>),
      );

  /// `POST /employees/:id/loans/:loanId/write-off` — write off the loan.
  Future<ApiResult<WriteOffLoanResult>> writeOffLoan(
    int employeeId,
    int loanId,
    Map<String, dynamic> body,
  ) =>
      _client.post(
        '${ApiEndpoints.employees}/$employeeId/loans/$loanId/write-off',
        body: body,
        parse: (Object? json) =>
            WriteOffLoanResult.fromJson(json! as Map<String, dynamic>),
      );

  /// `DELETE /employees/:id/loans/:loanId` — delete loan (no repayments).
  Future<ApiResult<void>> deleteLoan(int employeeId, int loanId) =>
      _client.deleteRaw(
        '${ApiEndpoints.employees}/$employeeId/loans/$loanId',
      );

  /// `POST /employees/:id/loans/:loanId/repayments/:rid/void` — void a repayment.
  Future<ApiResult<Map<String, dynamic>>> voidRepayment(
    int employeeId,
    int loanId,
    int repaymentId,
  ) =>
      _client.post(
        '${ApiEndpoints.employees}/$employeeId/loans/$loanId/repayments/$repaymentId/void',
        parse: (Object? json) => json! as Map<String, dynamic>,
      );

  /// `GET /dashboard/active-loans` — global active loans for dashboard.
  Future<ApiResult<ActiveLoansResult>> activeLoans() => _client.get(
        ApiEndpoints.dashboardActiveLoans,
        parse: (Object? json) =>
            ActiveLoansResult.fromJson(json! as Map<String, dynamic>),
      );
}

final loanRepositoryProvider = Provider<LoanRepository>(
  (ref) => LoanRepository(RepositoryClient(ref.watch(dioProvider))),
);
