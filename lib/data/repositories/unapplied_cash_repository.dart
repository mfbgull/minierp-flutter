import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cache/cached_repository.dart';
import '../../core/api/endpoints.dart';
import '../models/payment.dart';
import '../models/invoice.dart';
import '../models/unapplied_cash.dart';
import 'api_result.dart';
import 'repository_client.dart';

class UnappliedCashRepository {
  UnappliedCashRepository(this.api);

  final RepositoryClient api;
  String get server => api.baseUrl;

  Future<ApiResult<CashReceipt>> reversibleReceipt(
    int customerId,
    int paymentId,
  ) async {
    final current = await payment(paymentId);
    if (current case ApiFailure(:final error)) return ApiFailure(error);
    final document = current.requireData;
    if (document.id != paymentId ||
        document.customerId != customerId ||
        document.paymentKind != 'UNAPPLIED_RECEIPT') {
      return const ApiFailure(
        ApiError(message: '', code: 'CASH_RECEIPT_NOT_REVERSIBLE'),
      );
    }
    if (document.voidedAt != null) {
      return const ApiFailure(ApiError(message: '', code: 'ALREADY_VOIDED'));
    }
    var page = 1;
    while (true) {
      final result = await summary(customerId, page: page, limit: 100);
      if (result case ApiFailure(:final error)) return ApiFailure(error);
      final receipts = result.requireData.receipts;
      for (final receipt in receipts.items) {
        if (receipt.paymentId == paymentId) {
          if (receipt.canReverse &&
              receipt.appliedMinor == 0 &&
              receipt.refundedMinor == 0 &&
              receipt.remainingMinor == receipt.originalMinor) {
            return ApiSuccess(receipt);
          }
          return const ApiFailure(
            ApiError(message: '', code: 'CASH_RECEIPT_NOT_REVERSIBLE'),
          );
        }
      }
      if (page >= receipts.totalPages || receipts.items.isEmpty) {
        return const ApiFailure(
          ApiError(message: '', code: 'CASH_RECEIPT_NOT_REVERSIBLE'),
        );
      }
      page++;
    }
  }

  Future<ApiResult<List<Invoice>>> eligibleInvoices(
    int customerId,
    String date,
  ) async {
    final invoices = <int, Invoice>{};
    var page = 1;
    while (true) {
      final result = await api.getOnline<CashPage<Invoice>>(
        '/invoices',
        includeEnvelope: true,
        queryParameters: {
          'customer_id': customerId,
          'page': page,
          'limit': 200,
          'sortBy': 'invoice_date',
          'sortOrder': 'ASC',
        },
        parse: (value) =>
            CashPage(value, (row) => Invoice.fromJson(cashObject(row))),
      );
      if (result case ApiFailure(:final error)) return ApiFailure(error);
      final data = result.requireData;
      if (data.page != page || (data.items.isEmpty && page < data.totalPages)) {
        return const ApiFailure(
          ApiError(
            message: 'Incomplete invoice list',
            code: 'CASH_INVOICE_READ_FAILED',
          ),
        );
      }
      for (final invoice in data.items) {
        if (invoice.customerId == customerId &&
            invoice.balanceAmount > 0 &&
            !['Cancelled', 'Deleted', 'Paid'].contains(invoice.status) &&
            invoice.invoiceDate.compareTo(date) <= 0) {
          invoices[invoice.id] = invoice;
        }
      }
      if (page >= data.totalPages) break;
      page++;
    }
    final sorted = invoices.values.toList()
      ..sort((left, right) {
        final byDate = left.invoiceDate.compareTo(right.invoiceDate);
        return byDate != 0 ? byDate : left.id.compareTo(right.id);
      });
    return ApiSuccess(List.unmodifiable(sorted));
  }

  Future<ApiResult<CashCapabilities>> capabilities() => api.getOnline(
    '${ApiEndpoints.unappliedCash}/capabilities',
    parse: CashCapabilities.new,
  );

  Future<ApiResult<CashSummary>> summary(
    int customerId, {
    String? date,
    int page = 1,
    int limit = 20,
  }) => api.getOnline(
    '/customers/$customerId/unapplied-cash',
    includeEnvelope: true,
    queryParameters: {'page': page, 'limit': limit, 'operation_date': ?date},
    parse: CashSummary.new,
  );

  Future<ApiResult<CashPage<CashActivity>>> activity(
    int customerId, {
    int page = 1,
    int limit = 20,
    String? fromDate,
    String? toDate,
  }) => api.getOnline(
    '/customers/$customerId/unapplied-cash/activity',
    includeEnvelope: true,
    queryParameters: {
      'page': page,
      'limit': limit,
      'fromDate': ?fromDate,
      'toDate': ?toDate,
    },
    parse: (value) => CashPage(value, CashActivity.new),
  );

  Future<ApiResult<Payment>> payment(int paymentId) => api.getOnline(
    '/payments/$paymentId',
    parse: (value) => Payment.fromJson(cashObject(value)),
  );

  Future<ApiResult<CashResult>> execute(CashRequest request, String key) async {
    if (key.length < 8 || key.length > 200 || key.trim() != key) {
      return const ApiFailure(
        ApiError(message: 'Invalid retry key', code: 'INVALID_IDEMPOTENCY_KEY'),
      );
    }
    final result = await api.post(
      request.path,
      body: request.body,
      headers: {'Idempotency-Key': key},
      parse: CashResult.new,
    );
    if (result is ApiSuccess<CashResult>) {
      await api.invalidatePaths([
        '/customers',
        '/payments',
        '/invoices',
        '/dashboard',
        '/reports',
        ApiEndpoints.unappliedCash,
      ]);
    }
    return result;
  }
}

final unappliedCashRepositoryProvider = Provider<UnappliedCashRepository>(
  (ref) => UnappliedCashRepository(ref.watch(cachedRepositoryClientProvider)),
);
