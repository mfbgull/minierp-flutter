// Employees repository — typed against `server/src/routes/employees.ts`
// (PORTING.md §5): a server-paginated list (`GET /employees` returns a
// `pagination: {page, limit, total, totalPages}` block — a different shape
// from /customers), CRUD, the generated-code helper, salary payments and
// documents.
//
// Endpoint shapes (verified against the live server):
// - `GET /employees?search&department&status&sortBy&sortOrder&page&limit`
//   → `{success, data: [Employee], pagination: {page, limit, total,
//   totalPages}}`
// - `GET /employees/next-code` → `{success, data: {code}}`
// - `GET /employees/:id` → `{success, data: Employee}`
// - `POST /employees` → `{success, data: Employee}` (201)
// - `PUT /employees/:id` → `{success, data: Employee}`
// - `DELETE /employees/:id` → 204 (no body)
// - `POST /employees/:id/salary/pay` → `{success, data: {id,
//   journal_entry_id}}` (201)
// - `GET /employees/:id/salary/history` → `{success, data: [SalaryPayment]}`
// - `GET /employees/:id/documents` → `{success, data: [EmployeeDocument]}`
// - `DELETE /employees/:id/documents/:docId` → 204

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart' show dioProvider;
import '../../core/api/endpoints.dart' show ApiEndpoints;
import '../../data/repositories/api_result.dart';
import '../../data/repositories/paged_request.dart' show PagedResponse;
import '../../data/repositories/repository_client.dart';
import 'employee_models.dart';

/// Employees list filters — mirrors the `getEmployees` controller params.
class EmployeeFilters {
  const EmployeeFilters({
    this.search,
    this.department,
    this.status,
    this.sortBy,
    this.sortOrder,
    this.page = 1,
    this.limit = 10,
  });

  final String? search;

  /// Exact `department` match.
  final String? department;

  /// `active` (default) or `inactive` — the controller treats any other
  /// value as the active list.
  final String? status;

  /// Server sort column from the model's whitelist (employee_code,
  /// first_name, last_name, department, designation, created_at).
  final String? sortBy;

  /// `ASC` or `DESC`.
  final String? sortOrder;

  final int page;
  final int limit;

  Map<String, dynamic> toQuery() => {
    'page': page,
    'limit': limit,
    if (search != null && search!.isNotEmpty) 'search': search,
    if (department != null && department!.isNotEmpty)
      'department': department,
    if (status != null && status!.isNotEmpty) 'status': status,
    if (sortBy != null && sortBy!.isNotEmpty) 'sortBy': sortBy,
    if (sortOrder != null) 'sortOrder': sortOrder,
  };
}

class EmployeeRepository {
  EmployeeRepository(this._client);

  final RepositoryClient _client;

  /// `GET /employees` — the response is `{success, data, pagination:
  /// {page, limit, total, totalPages}}` (a different shape from the
  /// /customers block), so the raw body is parsed here and mapped onto a
  /// [PagedResponse] for the shared server pagination bar.
  Future<ApiResult<PagedResponse<Employee>>> list(EmployeeFilters filters) =>
      _client.getRaw<PagedResponse<Employee>>(
        ApiEndpoints.employees,
        queryParameters: filters.toQuery(),
        parse: (Object? json) {
          final body = json as Map<String, dynamic>;
          if (body['success'] != true) {
            throw ApiResponseException(
              (body['error'] as String?) ?? 'Request failed',
              null,
            );
          }
          final data = body['data'];
          if (data is! List) {
            throw ApiResponseException('Expected a list response', null);
          }
          final pagination = body['pagination'];
          if (pagination is! Map<String, dynamic>) {
            throw ApiResponseException('Missing pagination block', null);
          }
          final total = (pagination['total'] as num?)?.toInt() ?? 0;
          final page = (pagination['page'] as num?)?.toInt() ?? 1;
          final limit = (pagination['limit'] as num?)?.toInt() ?? 1;
          final totalPages =
              (pagination['totalPages'] as num?)?.toInt() ??
              (total <= 0 ? 1 : (total + limit - 1) ~/ limit);
          return PagedResponse(
            items: [
              for (final row in data)
                Employee.fromJson(row! as Map<String, dynamic>),
            ],
            totalItems: total,
            currentPage: page,
            totalPages: totalPages,
            hasNext: page < totalPages,
            hasPrev: page > 1,
          );
        },
      );

  /// `GET /employees/:id` — the full employee detail.
  Future<ApiResult<Employee>> get(int id) => _client.get(
    '${ApiEndpoints.employees}/$id',
    parse: (Object? json) => Employee.fromJson(json! as Map<String, dynamic>),
  );

  /// `GET /employees/next-code` — the server-generated `EMP-XXX` code for
  /// the create form (falls back to `EMP-001` server-side).
  Future<ApiResult<String>> nextCode() => _client.get(
    '${ApiEndpoints.employees}/next-code',
    parse: (Object? json) =>
        (json as Map<String, dynamic>)['code'] as String? ?? 'EMP-001',
  );

  /// `POST /employees` — body keys per the controller's createEmployee
  /// DTO; the employee_code is server-generated (fetch [nextCode] first).
  Future<ApiResult<Employee>> create(Map<String, dynamic> body) =>
      _client.post(
        ApiEndpoints.employees,
        body: body,
        parse: (Object? json) =>
            Employee.fromJson(json! as Map<String, dynamic>),
      );

  Future<ApiResult<Employee>> update(int id, Map<String, dynamic> body) =>
      _client.put(
        '${ApiEndpoints.employees}/$id',
        body: body,
        parse: (Object? json) =>
            Employee.fromJson(json! as Map<String, dynamic>),
      );

  /// `DELETE /employees/:id` — 204, no body.
  Future<ApiResult<void>> delete(int id) => _client.deleteRaw(
    '${ApiEndpoints.employees}/$id',
  );

  /// `POST /employees/:id/salary/pay` — body keys per paySalary; returns
  /// the created salary_payment id (and the GL journal id when posted).
  Future<ApiResult<Map<String, dynamic>>> paySalary(
    int id,
    Map<String, dynamic> body,
  ) => _client.post(
    '${ApiEndpoints.employees}/$id/salary/pay',
    body: body,
    parse: (Object? json) => json! as Map<String, dynamic>,
  );

  /// `GET /employees/:id/salary/history` — aggregated by month.
  Future<ApiResult<List<SalaryMonthSummary>>> salaryHistory(int id) =>
      _client.getList(
        '${ApiEndpoints.employees}/$id/salary/history',
        parseItem: (Object? json) =>
            SalaryMonthSummary.fromJson(json! as Map<String, dynamic>),
      );

  /// `GET /employees/:id/salary/month/:payPeriod` — individual payments for a month.
  Future<ApiResult<SalaryMonthDetail>> salaryMonthDetail(
    int id,
    String payPeriod,
  ) => _client.get(
    '${ApiEndpoints.employees}/$id/salary/month/$payPeriod',
    parse: (Object? json) =>
        SalaryMonthDetail.fromJson(json! as Map<String, dynamic>),
  );

  /// `DELETE /employees/:id/salary/:paymentId` — voids GL entry + deletes record.
  Future<ApiResult<void>> deleteSalaryPayment(int id, int paymentId) =>
      _client.deleteRaw(
        '${ApiEndpoints.employees}/$id/salary/$paymentId',
      );

  /// `GET /employees/:id/documents` — newest-first by created_at.
  Future<ApiResult<List<EmployeeDocument>>> documents(int id) =>
      _client.getList(
        '${ApiEndpoints.employees}/$id/documents',
        parseItem: (Object? json) =>
            EmployeeDocument.fromJson(json! as Map<String, dynamic>),
      );

  /// `POST /employees/:id/documents` — multipart upload (the route is
  /// `uploadEmployeeDoc.single('file')`). Sends the metadata fields plus
  /// the selected file as the `file` part (from [fileBytes], or from
  /// [filePath] when only a path is available); when both are omitted
  /// the request is metadata-only (the server falls back to
  /// `file_path`/null).
  Future<ApiResult<int>> addDocument(
    int id, {
    required String documentName,
    String? documentType,
    String? documentNumber,
    String? issueDate,
    String? expiryDate,
    String? notes,
    Uint8List? fileBytes,
    String? filePath,
    String? fileName,
  }) {
    final formData = FormData.fromMap({
      'document_name': documentName,
      if (documentType != null && documentType.isNotEmpty)
        'document_type': documentType,
      if (documentNumber != null && documentNumber.isNotEmpty)
        'document_number': documentNumber,
      if (issueDate != null && issueDate.isNotEmpty) 'issue_date': issueDate,
      if (expiryDate != null && expiryDate.isNotEmpty)
        'expiry_date': expiryDate,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      if (fileName != null && fileBytes != null)
        'file': MultipartFile.fromBytes(
          fileBytes,
          filename: fileName,
          contentType: DioMediaType.parse(
            _mediaTypeFor(fileName),
          ),
        )
      else if (fileName != null && filePath != null)
        'file': MultipartFile.fromFile(
          filePath,
          filename: fileName,
          contentType: DioMediaType.parse(
            _mediaTypeFor(fileName),
          ),
        ),
    });
    return _client.postMultipart(
      '${ApiEndpoints.employees}/$id/documents',
      formData: formData,
      parse: (Object? json) {
        final raw = (json as Map<String, dynamic>)['id'];
        return raw is num ? raw.toInt() : 0;
      },
    );
  }

  /// `DELETE /employees/:id/documents/:docId` — 204, no body.
  Future<ApiResult<void>> removeDocument(int id, int docId) =>
      _client.deleteRaw('${ApiEndpoints.employees}/$id/documents/$docId');
}

/// Maps a picked file's extension to the MIME type the server's upload
/// filter accepts (the client mirrors the server's allowed list so the
/// picker rejects unsupported files up front). Defaults to
/// `application/octet-stream` for unknown extensions.
String _mediaTypeFor(String fileName) {
  final ext = fileName.split('.').last.toLowerCase();
  return switch (ext) {
    'pdf' => 'application/pdf',
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'gif' => 'image/gif',
    'doc' => 'application/msword',
    'docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls' => 'application/vnd.ms-excel',
    'xlsx' =>
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'txt' => 'text/plain',
    _ => 'application/octet-stream',
  };
}

final employeeRepositoryProvider = Provider<EmployeeRepository>(
  (ref) => EmployeeRepository(RepositoryClient(ref.watch(dioProvider))),
);
