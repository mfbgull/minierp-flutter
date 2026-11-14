// Purchase repository — typed against docs/API.md §Direct Purchases and
// the server `purchaseController` / `purchaseReturnController` shapes
// (PORTING.md §2).
//
// Envelope variants observed on the server:
// - `GET /purchases` → **enveloped + `pagination` block** (server-paged
//   since grid-pagination Phase 6; filters: start_date, end_date,
//   item_id, warehouse_id, supplier_name, search, page, limit, sortBy,
//   sortOrder)
// - `GET /purchases/:id` → **bare object** (same joined shape)
// - `GET /purchase-returns` → **enveloped + `pagination` block** —
//   `PurchaseReturnModel.getAll` (headers; filters: search, start_date,
//   end_date, type, status, warehouse_id)
// - `GET /purchase-returns/:id` → **bare object** (header + items)
// - `POST /purchase-returns` → **bare object** `PurchaseReturn` (header)
// - `POST /purchase-returns/:id/void` → **enveloped** `{success,
//   message, data: PurchaseReturn}`
//
// The old return endpoints (`POST /purchases/:id/return`,
// `POST /purchase-orders/:id/return-receipt`, `GET /purchases/returns`)
// were removed with the redesign (spec §7).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/endpoints.dart' show ApiEndpoints;
import '../models/invoice.dart' show InvoicePaymentRecord;
import '../models/purchase.dart' show Purchase;
import '../models/purchase_return.dart' show PurchaseReturn;
import 'api_result.dart';
import 'paged_request.dart' show PagedRequest, PagedResponse;
import 'repository_client.dart';

/// The open refund claim behind a credit note (PRET-002) — `claim` block
/// of the refundable endpoint. Null when the note carries no live claim.
class RefundClaimSummary {
  const RefundClaimSummary({
    required this.id,
    required this.claimNo,
    required this.status,
    required this.amount,
    required this.receivedAmount,
    required this.remaining,
  });

  factory RefundClaimSummary.fromJson(Map<String, dynamic> json) =>
      RefundClaimSummary(
        id: json['id'] as int,
        claimNo: json['claim_no'] as String,
        status: json['status'] as String,
        amount: json['amount'] as num? ?? 0,
        receivedAmount: json['received_amount'] as num? ?? 0,
        remaining: json['remaining'] as num? ?? 0,
      );

  final int id;
  final String claimNo;
  final String status;
  final num amount;
  final num receivedAmount;
  final num remaining;
}

/// One refund RECEIPT row (`GET /supplier-refunds`) — the cash payout that
/// settles a claim. [status] is POSTED or VOIDED; a voided receipt is kept
/// for audit but no longer settles anything.
class SupplierRefundReceipt {
  const SupplierRefundReceipt({
    required this.id,
    required this.refundNo,
    required this.refundDate,
    required this.supplierId,
    required this.supplierName,
    required this.amount,
    required this.paymentMethod,
    required this.status,
    this.creditNoteId,
    this.creditNo,
    this.referenceNo,
    this.voidedReason,
  });

  factory SupplierRefundReceipt.fromJson(Map<String, dynamic> json) =>
      SupplierRefundReceipt(
        id: json['id'] as int,
        refundNo: json['refund_no'] as String,
        refundDate: json['refund_date'] as String,
        supplierId: json['supplier_id'] as int,
        supplierName: json['supplier_name'] as String? ?? '',
        amount: json['amount'] as num? ?? 0,
        paymentMethod: json['payment_method'] as String? ?? '',
        status: json['status'] as String,
        creditNoteId: json['credit_note_id'] as int?,
        creditNo: json['credit_no'] as String?,
        referenceNo: json['reference_no'] as String?,
        voidedReason: json['voided_reason'] as String?,
      );

  final int id;
  final String refundNo;
  final String refundDate;
  final int supplierId;
  final String supplierName;
  final num amount;
  final String paymentMethod;
  final String status;
  final int? creditNoteId;
  final String? creditNo;
  final String? referenceNo;
  final String? voidedReason;

  /// Only a POSTED receipt can be voided.
  bool get isPosted => status == 'POSTED';
}

/// `GET /supplier-refunds/credit-notes/:id/refundable` response.
class CreditNoteRefundable {
  const CreditNoteRefundable({required this.refundable, this.claim});

  factory CreditNoteRefundable.fromJson(Map<String, dynamic> json) =>
      CreditNoteRefundable(
        refundable: json['refundable'] as num? ?? 0,
        claim: json['claim'] == null
            ? null
            : RefundClaimSummary.fromJson(json['claim'] as Map<String, dynamic>),
      );

  final num refundable;
  final RefundClaimSummary? claim;
}

/// One row of the refund-claim list (`GET /supplier-refunds/claims`).
/// [remaining] is the uncollected balance: amount minus received minus
/// written off.
class RefundClaim {
  const RefundClaim({
    required this.id,
    required this.claimNo,
    required this.supplierId,
    required this.supplierName,
    required this.claimDate,
    required this.amount,
    required this.receivedAmount,
    required this.writtenOffAmount,
    required this.remaining,
    required this.status,
    this.returnNo,
    this.creditNo,
    this.reason,
  });

  factory RefundClaim.fromJson(Map<String, dynamic> json) {
    final amount = json['amount'] as num? ?? 0;
    final received = json['received_amount'] as num? ?? 0;
    final writtenOff = json['written_off_amount'] as num? ?? 0;
    return RefundClaim(
      id: json['id'] as int,
      claimNo: json['claim_no'] as String,
      supplierId: json['supplier_id'] as int,
      supplierName: json['supplier_name'] as String? ?? '',
      claimDate: json['claim_date'] as String,
      amount: amount,
      receivedAmount: received,
      writtenOffAmount: writtenOff,
      remaining: amount - received - writtenOff,
      status: json['status'] as String,
      returnNo: json['return_no'] as String?,
      creditNo: json['credit_no'] as String?,
      reason: json['reason'] as String?,
    );
  }

  final int id;
  final String claimNo;
  final int supplierId;
  final String supplierName;
  final String claimDate;
  final num amount;
  final num receivedAmount;
  final num writtenOffAmount;
  final num remaining;
  final String status;
  final String? returnNo;
  final String? creditNo;
  final String? reason;

  /// A claim is open while it still expects money. RECEIVED and CANCELLED
  /// are terminal; PARTIAL still expects the remainder.
  bool get isOpen => status == 'EXPECTED' || status == 'PARTIAL';
}

/// `GET /supplier-refunds/claims/due` response — a receivable memo, never a
/// cash figure.
class RefundsDue {
  const RefundsDue({required this.rows, required this.totalDue});

  factory RefundsDue.fromJson(Map<String, dynamic> json) => RefundsDue(
    rows: [
      for (final row in (json['data'] as List<dynamic>? ?? const []))
        RefundClaim.fromJson(row as Map<String, dynamic>),
    ],
    totalDue: json['total_due'] as num? ?? 0,
  );

  final List<RefundClaim> rows;
  final num totalDue;
}

class PurchaseRepository {
  PurchaseRepository(this._api);

  final RepositoryClient _api;

  /// One page of direct purchases (`GET /purchases`) — server-paginated
  /// like the other converted lists. `supplier_name` rides in `extra`.
  Future<ApiResult<PagedResponse<Purchase>>> listPaged(PagedRequest request) =>
      _api.getPaged(
        ApiEndpoints.purchases,
        queryParameters: request.toQuery(),
        parseItem: (Object? json) =>
            Purchase.fromJson(json as Map<String, dynamic>),
      );

  /// Payments allocated to this purchase (`GET /purchases/:id/payments`
  /// — enveloped list; each row is the payment header plus the
  /// per-purchase allocation amount, newest first). Same row shape as
  /// the invoice payments endpoint, so it parses into
  /// [InvoicePaymentRecord].
  Future<ApiResult<List<InvoicePaymentRecord>>> payments(int purchaseId) =>
      _api.getList(
        '${ApiEndpoints.purchases}/$purchaseId/payments',
        parseItem: (Object? json) =>
            InvoicePaymentRecord.fromJson(json as Map<String, dynamic>),
      );

  /// Purchase detail — bare object (same joined shape as the list rows).
  Future<ApiResult<Purchase>> detail(int id) => _api.getRaw(
    '${ApiEndpoints.purchases}/$id',
    parse: (Object? json) => Purchase.fromJson(json as Map<String, dynamic>),
  );

  /// Record a direct purchase (`POST /purchases`). The server writes the
  /// purchase row, posts the stock movement, and returns the new
  /// purchase (bare object). [purchaseDate] is ISO `yyyy-MM-dd`;
  /// [supplierId] links the purchase to a supplier (the server resolves
  /// the name and posts the AP ledger entry).
  /// [idempotencyKey] makes a retry after a lost response replay the original
  /// purchase instead of duplicating its rows, batches and GL (audit-3 task
  /// 08). Derive it from the same body with `IdempotencyKeyCache`.
  Future<ApiResult<Purchase>> create({
    required int itemId,
    required int warehouseId,
    required num quantity,
    required num unitCost,
    num inputTaxAmount = 0,
    required String purchaseDate,
    int? supplierId,
    String? invoiceNo,
    String? remarks,
    String? expiryDate,
    String? idempotencyKey,
  }) => _api.post(
    ApiEndpoints.purchases,
    body: {
      'item_id': itemId,
      'warehouse_id': warehouseId,
      'quantity': quantity,
      'unit_cost': unitCost,
      'input_tax_amount': inputTaxAmount,
      'purchase_date': purchaseDate,
      'supplier_id': ?supplierId,
      if (invoiceNo != null && invoiceNo.trim().isNotEmpty)
        'invoice_no': invoiceNo.trim(),
      if (remarks != null && remarks.trim().isNotEmpty)
        'remarks': remarks.trim(),
      'expiry_date': ?expiryDate,
    },
    headers: idempotencyKey == null
        ? null
        : <String, dynamic>{'Idempotency-Key': idempotencyKey},
    parse: (Object? json) => Purchase.fromJson(json as Map<String, dynamic>),
  );

  /// Record ONE purchase containing MULTIPLE items (`POST /purchases`
  /// with an `items` array). The server creates one `purchases` row per
  /// line — each with its own doc no, batch, movement, ledger and GL
  /// entries — atomically in one transaction, and returns the created
  /// rows as a **bare array** (order matches [items]). Header fields
  /// apply to every line.
  ///
  /// [idempotencyKey] makes a retry after a lost response replay rather than
  /// duplicating every line's purchase, batch, movement and GL entry.
  Future<ApiResult<List<Purchase>>> createMulti({
    required int warehouseId,
    required String purchaseDate,
    int? supplierId,
    String? invoiceNo,
    String? remarks,
    required List<
      ({
        int itemId,
        num quantity,
        num unitCost,
        num inputTaxAmount,
        String? expiryDate,
      })
    >
    items,
    String? idempotencyKey,
  }) => _api.postRaw<List<Purchase>>(
    ApiEndpoints.purchases,
    body: {
      'warehouse_id': warehouseId,
      'purchase_date': purchaseDate,
      'supplier_id': ?supplierId,
      if (invoiceNo != null && invoiceNo.trim().isNotEmpty)
        'invoice_no': invoiceNo.trim(),
      if (remarks != null && remarks.trim().isNotEmpty)
        'remarks': remarks.trim(),
      'items': [
        for (final line in items)
          {
            'item_id': line.itemId,
            'quantity': line.quantity,
            'unit_cost': line.unitCost,
            'input_tax_amount': line.inputTaxAmount,
            'expiry_date': ?line.expiryDate,
          },
      ],
    },
    headers: idempotencyKey == null
        ? null
        : <String, dynamic>{'Idempotency-Key': idempotencyKey},
    parse: (Object? json) => [
      for (final row in json! as List<dynamic>)
        Purchase.fromJson(row as Map<String, dynamic>),
    ],
  );

  /// One page of purchase-return headers (`GET /purchase-returns`) —
  /// server-paginated like the other converted lists. Search and the
  /// optional date/status/type/warehouse filters ride in `request.extra`.
  Future<ApiResult<PagedResponse<PurchaseReturn>>> returnsPaged(
    PagedRequest request,
  ) => _api.getPaged(
    ApiEndpoints.purchaseReturns,
    queryParameters: request.toQuery(),
    parseItem: (Object? json) =>
        PurchaseReturn.fromJson(json as Map<String, dynamic>),
  );

  /// Create a return (`POST /purchase-returns`) — enveloped
  /// `{success, message, data: PurchaseReturn}`. [sourceType] is
  /// `PURCHASE` (sourceId = purchases.id) or `PURCHASE_ORDER` (sourceId =
  /// purchase_orders.id); each line's `sourceItemId` is `purchases.id`
  /// (direct purchase) or `purchase_order_items.id` (PO receipt) and its
  /// quantity must be positive and ≤ the line's remaining returnable qty.
  Future<ApiResult<PurchaseReturn>> createReturn({
    required String returnDate,
    required String sourceType,
    required int sourceId,
    required int warehouseId,
    String? reason,
    String? disposition,
    required List<({int sourceItemId, num quantity})> items,
    required String idempotencyKey,
  }) {
    final body = <String, dynamic>{
      'return_date': returnDate,
      'source_type': sourceType,
      'source_id': sourceId,
      'warehouse_id': warehouseId,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      'disposition': ?disposition,
      'items': [
        for (final line in items)
          {'source_item_id': line.sourceItemId, 'quantity': line.quantity},
      ],
    };
    return _api.post(
      ApiEndpoints.purchaseReturns,
      body: body,
      headers: {'Idempotency-Key': idempotencyKey},
      parse: (Object? json) =>
          PurchaseReturn.fromJson(json as Map<String, dynamic>),
    );
  }

  /// Return detail — bare object (header + embedded `items`).
  Future<ApiResult<PurchaseReturn>> returnDetail(int id) => _api.getRaw(
    '${ApiEndpoints.purchaseReturns}/$id',
    parse: (Object? json) =>
        PurchaseReturn.fromJson(json as Map<String, dynamic>),
  );

  /// Void a return — full reversal (stock + GL + credit note) —
  /// enveloped `{success, message, data: PurchaseReturn}`. The server
  /// rejects (400) when the return is not POSTED or already VOIDED.
  Future<ApiResult<PurchaseReturn>> voidReturn(
    int id, {
    required String reason,
  }) => _api.post(
    '${ApiEndpoints.purchaseReturns}/$id/void',
    body: {'reason': reason.trim()},
    parse: (Object? json) =>
        PurchaseReturn.fromJson(json as Map<String, dynamic>),
  );

  /// Refundable balance of a credit note (`GET
  /// /supplier-refunds/credit-notes/:id/refundable`) — what's left of the
  /// note after already-issued refunds, plus the open refund claim
  /// (PRET-002) when the note has one.
  Future<ApiResult<CreditNoteRefundable>> creditNoteRefundable(
    int creditNoteId,
  ) => _api.getRaw(
    '${ApiEndpoints.supplierRefunds}/credit-notes/$creditNoteId/refundable',
    parse: (Object? json) =>
        CreditNoteRefundable.fromJson(json! as Map<String, dynamic>),
  );

  /// Issue a supplier refund (cash receipt against a credit note's claim,
  /// `POST /supplier-refunds`) — enveloped `{success, message, data}`.
  /// Requires an Idempotency-Key header.
  Future<ApiResult<Map<String, dynamic>>> createRefund({
    required String refundDate,
    required num amount,
    int? creditNoteId,
    int? claimId,
    String? paymentMethod,
    String? referenceNo,
    bool treatExcessAsAdvance = false,
    required String idempotencyKey,
  }) => _api.postEnvelope<Map<String, dynamic>>(
    ApiEndpoints.supplierRefunds,
    headers: {'Idempotency-Key': idempotencyKey},
    body: {
      'refund_date': refundDate,
      'credit_note_id': ?creditNoteId,
      'claim_id': ?claimId,
      'amount': amount,
      'payment_method': ?paymentMethod,
      'reference_no': ?referenceNo,
      'treat_excess_as_advance': treatExcessAsAdvance ? true : null,
    },
    parse: (json) => json,
  );

  /// Void a direct purchase (PUR-03) — enveloped `{success, message}` with
  /// no data. The server rejects (400) when stock was already sold/returned
  /// or payments are recorded against the purchase.
  Future<ApiResult<void>> voidPurchase(int id, {required String reason}) =>
      _api.postEnvelope<void>(
        '${ApiEndpoints.purchases}/$id/void',
        body: {'reason': reason.trim()},
        parse: (_) {},
      );

  /// One page of refund claims (`GET /supplier-refunds/claims`). [status]
  /// filters to a single lifecycle state; omit it for all claims.
  Future<ApiResult<PagedResponse<RefundClaim>>> claimsPaged(
    PagedRequest request, {
    String? status,
    int? supplierId,
  }) => _api.getPaged(
    '${ApiEndpoints.supplierRefunds}/claims',
    queryParameters: {
      ...request.toQuery(),
      'status': ?status,
      'supplier_id': ?supplierId,
    },
    parseItem: (Object? json) => RefundClaim.fromJson(json as Map<String, dynamic>),
  );

  /// The outstanding refund claims (`GET /supplier-refunds/claims/due`).
  Future<ApiResult<RefundsDue>> refundsDue() => _api.getRaw(
    '${ApiEndpoints.supplierRefunds}/claims/due',
    parse: (Object? json) => RefundsDue.fromJson(json! as Map<String, dynamic>),
  );

  /// The receipts allocated to one claim (`GET /supplier-refunds?claim_id=`).
  /// The server resolves the link through refund_receipt_allocations, so a
  /// receipt that settles no claim of this id is not returned.
  Future<ApiResult<PagedResponse<SupplierRefundReceipt>>> refundReceipts(
    PagedRequest request, {
    required int claimId,
  }) => _api.getPaged(
    ApiEndpoints.supplierRefunds,
    queryParameters: {...request.toQuery(), 'claim_id': claimId},
    parseItem: (Object? json) =>
        SupplierRefundReceipt.fromJson(json as Map<String, dynamic>),
  );

  /// Record a standalone refund claim — a supplier owes money with no
  /// purchase return behind it (`POST /supplier-refunds/claims`). Requires
  /// an Idempotency-Key header.
  Future<ApiResult<Map<String, dynamic>>> createClaim({
    required int supplierId,
    required String claimDate,
    required num amount,
    String? reason,
    required String idempotencyKey,
  }) => _api.postEnvelope<Map<String, dynamic>>(
    '${ApiEndpoints.supplierRefunds}/claims',
    headers: {'Idempotency-Key': idempotencyKey},
    body: {
      'supplier_id': supplierId,
      'claim_date': claimDate,
      'amount': amount,
      'reason': ?reason,
    },
    parse: (json) => json,
  );

  /// Cancel a claim that holds no receipts (`POST
  /// /supplier-refunds/claims/:id/cancel`).
  Future<ApiResult<void>> cancelClaim(int id, {String? reason}) =>
      _api.postEnvelope<void>(
        '${ApiEndpoints.supplierRefunds}/claims/$id/cancel',
        body: {'reason': ?reason},
        parse: (_) {},
      );

  /// Write off an uncollected claim balance (Dr 7300 / Cr AP). A reason is
  /// mandatory; above Rs 1,000 the server requires the admin role.
  Future<ApiResult<void>> writeOffClaim(
    int id, {
    required String reason,
    num? amount,
    String? writeOffDate,
  }) => _api.postEnvelope<void>(
    '${ApiEndpoints.supplierRefunds}/claims/$id/write-off',
    body: {
      'reason': reason.trim(),
      'amount': ?amount,
      'write_off_date': ?writeOffDate,
    },
    parse: (_) {},
  );

  /// Void a refund receipt (`POST /supplier-refunds/:id/void`). A void that
  /// would overdraw cash is refused with 409 and a `cashBlockers` list.
  Future<ApiResult<void>> voidRefund(int id, {required String reason}) =>
      _api.postEnvelope<void>(
        '${ApiEndpoints.supplierRefunds}/$id/void',
        body: {'reason': reason.trim()},
        parse: (_) {},
      );
}

final purchaseRepositoryProvider = Provider<PurchaseRepository>(
  (ref) => PurchaseRepository(ref.watch(repositoryClientProvider)),
);

/// One page of refund claims. [status] null → every claim, which the list
/// screen turns into "open only" by passing `EXPECTED`/`PARTIAL`.
final refundClaimsProvider = FutureProvider.autoDispose
    .family<
      PagedResponse<RefundClaim>,
      ({String? status, int page, int limit})
    >((ref, args) async {
      final result = await ref
          .watch(purchaseRepositoryProvider)
          .claimsPaged(
            PagedRequest(
              page: args.page,
              limit: args.limit,
            ),
            status: args.status,
          );
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });

/// The outstanding refunds-due memo (`GET /supplier-refunds/claims/due`).
/// A receivable figure — deliberately separate from any cash total.
final refundsDueProvider = FutureProvider.autoDispose<RefundsDue>((ref) async {
  final result = await ref.watch(purchaseRepositoryProvider).refundsDue();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});
