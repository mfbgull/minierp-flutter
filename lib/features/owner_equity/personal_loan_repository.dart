// Owner Personal Loan repository — typed against the server
// ownerPersonalLoansController shapes.
//
// Endpoint shapes (verified against the spec):
// - `GET /owner-equity/personal-loans?page&limit&search&status&from_date&to_date`
// - `POST /owner-equity/personal-loans`
// - `GET /owner-equity/personal-loans/:id`
// - `PUT /owner-equity/personal-loans/:id`
// - `DELETE /owner-equity/personal-loans/:id`
// - `POST /owner-equity/personal-loans/:id/repayments`
// - `DELETE /owner-equity/personal-loans/:id/repayments/:repId`
// - `GET /owner-equity/personal-loans/summary`
// - `GET /owner-equity/borrowers?search&status`
// - `POST /owner-equity/borrowers`
// - `PUT /owner-equity/borrowers/:id`
// - `PUT /owner-equity/borrowers/:id/deactivate`
// - `PUT /owner-equity/borrowers/:id/reactivate`
// - `PUT /owner-equity/borrowers/:id/unlink`
// - `POST /owner-equity/borrowers/:id/merge`

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/endpoints.dart' show ApiEndpoints;
import 'personal_loan_models.dart';
import '../../data/repositories/api_result.dart';
import '../../data/repositories/paged_request.dart' show PagedRequest, PagedResponse;
import '../../data/repositories/repository_client.dart';

class PersonalLoanRepository {
  PersonalLoanRepository(this._client);

  final RepositoryClient _client;

  // ── Loans ──────────────────────────────────────────────────

  Future<ApiResult<PagedResponse<PersonalLoan>>> listLoans(
    PagedRequest request,
  ) =>
      _client.getPaged(
        ApiEndpoints.ownerPersonalLoans,
        queryParameters: request.toQuery(),
        parseItem: (Object? json) =>
            PersonalLoan.fromJson(json! as Map<String, dynamic>),
      );

  Future<ApiResult<PersonalLoan>> createLoan(Map<String, dynamic> body) =>
      _client.post(
        ApiEndpoints.ownerPersonalLoans,
        body: body,
        parse: (Object? json) =>
            PersonalLoan.fromJson(json! as Map<String, dynamic>),
      );

  Future<ApiResult<PersonalLoanDetail>> getLoanDetail(int id) => _client.get(
        '${ApiEndpoints.ownerPersonalLoans}/$id',
        parse: (Object? json) =>
            PersonalLoanDetail.fromJson(json! as Map<String, dynamic>),
      );

  Future<ApiResult<PersonalLoan>> updateLoan(
          int id, Map<String, dynamic> body) =>
      _client.put(
        '${ApiEndpoints.ownerPersonalLoans}/$id',
        body: body,
        parse: (Object? json) =>
            PersonalLoan.fromJson(json! as Map<String, dynamic>),
      );

  Future<ApiResult<void>> deleteLoan(int id) => _client.delete(
        '${ApiEndpoints.ownerPersonalLoans}/$id',
      );

  Future<ApiResult<PersonalLoanRepayResult>> addRepayment(
          int loanId, Map<String, dynamic> body) =>
      _client.post(
        '${ApiEndpoints.ownerPersonalLoans}/$loanId/repayments',
        body: body,
        parse: (Object? json) =>
            PersonalLoanRepayResult.fromJson(json! as Map<String, dynamic>),
      );

  Future<ApiResult<void>> deleteRepayment(int loanId, int repId) =>
      _client.delete(
        '${ApiEndpoints.ownerPersonalLoans}/$loanId/repayments/$repId',
      );

  Future<ApiResult<PersonalLoanSummary>> summary() => _client.get(
        ApiEndpoints.ownerPersonalLoansSummary,
        parse: (Object? json) =>
            PersonalLoanSummary.fromJson(json! as Map<String, dynamic>),
      );

  // ── Borrowers ──────────────────────────────────────────────

  Future<ApiResult<List<PersonalLoanBorrower>>> listBorrowers({
    String? search,
    String? status,
  }) =>
      _client.getList(
        ApiEndpoints.ownerBorrowers,
        queryParameters: {
          if (search?.isNotEmpty == true) 'search': search,
          'status': ?status,
        },
        parseItem: (Object? json) =>
            PersonalLoanBorrower.fromJson(json! as Map<String, dynamic>),
      );

  Future<ApiResult<PersonalLoanBorrower>> createBorrower(
          Map<String, dynamic> body) =>
      _client.post(
        ApiEndpoints.ownerBorrowers,
        body: body,
        parse: (Object? json) =>
            PersonalLoanBorrower.fromJson(json! as Map<String, dynamic>),
      );

  Future<ApiResult<PersonalLoanBorrower>> updateBorrower(
          int id, Map<String, dynamic> body) =>
      _client.put(
        '${ApiEndpoints.ownerBorrowers}/$id',
        body: body,
        parse: (Object? json) =>
            PersonalLoanBorrower.fromJson(json! as Map<String, dynamic>),
      );

  Future<ApiResult<void>> deactivateBorrower(int id) async {
    final result = await _client.put(
      '${ApiEndpoints.ownerBorrowers}/$id/deactivate',
      parse: (Object? json) => json,
    );
    return result.map<void>((_) {});
  }

  Future<ApiResult<void>> reactivateBorrower(int id) async {
    final result = await _client.put(
      '${ApiEndpoints.ownerBorrowers}/$id/reactivate',
      parse: (Object? json) => json,
    );
    return result.map<void>((_) {});
  }

  Future<ApiResult<PersonalLoanBorrower>> unlinkBorrower(int id) =>
      _client.put(
        '${ApiEndpoints.ownerBorrowers}/$id/unlink',
        parse: (Object? json) =>
            PersonalLoanBorrower.fromJson(json! as Map<String, dynamic>),
      );

  Future<ApiResult<Map<String, dynamic>>> mergeBorrowers(
          int sourceId, int targetId) =>
      _client.post(
        '${ApiEndpoints.ownerBorrowers}/$sourceId/merge',
        body: {'target_borrower_id': targetId},
        parse: (Object? json) => json! as Map<String, dynamic>,
      );
}

final personalLoanRepositoryProvider = Provider<PersonalLoanRepository>(
  (ref) => PersonalLoanRepository(ref.watch(repositoryClientProvider)),
);
