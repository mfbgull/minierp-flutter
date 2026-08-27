import 'json_helpers.dart';

/// A single row of the unified payment / cash-movement hub. It is a
/// read-only projection over five source tables (payments, expenses,
/// salary_payments, owner_capital, owner_withdrawals) produced by
/// `GET /payments/unified`. Creation always happens in each source's own
/// flow, so this model never carries write payloads.
///
/// Financial semantics (enforced server-side):
///  - [amount] is ALWAYS a positive absolute value; the direction of the
///    movement is conveyed only by [direction].
///  - [direction] is `in` | `out` | `unknown` (legacy invalid rows).
///  - [method] is normalized to a small allowed set (cash | bank | card |
///    mobile_wallet | credit | other | unknown).
class UnifiedPayment {
  const UnifiedPayment({
    required this.source,
    required this.sourceId,
    required this.refNo,
    required this.date,
    required this.amount,
    required this.method,
    required this.type,
    required this.direction,
    required this.party,
    this.partyId,
    this.partyType,
    required this.status,
    this.description,
  });

  factory UnifiedPayment.fromJson(Map<String, dynamic> json) => UnifiedPayment(
    source: asString(json['source']) ?? '',
    sourceId: asInt(json['source_id']) ?? 0,
    refNo: asString(json['ref_no']) ?? '',
    date: asString(json['date']) ?? '',
    amount: asNum(json['amount']) ?? 0,
    method: asString(json['method']) ?? 'unknown',
    type: asString(json['type']) ?? 'unknown',
    direction: asString(json['direction']) ?? 'unknown',
    party: asString(json['party']) ?? '',
    partyId: asInt(json['party_id']),
    partyType: asString(json['party_type']),
    status: asString(json['status']) ?? '',
    description: asString(json['description']),
  );

  final String source; // payment | expense | salary | owner_capital | owner_withdrawal
  final int sourceId; // source-local database id
  final String refNo;
  final String date;
  final num amount;
  final String method;
  final String type; // customer | supplier | expense | salary | owner_capital | owner_withdrawal | unknown
  final String direction; // in | out | unknown
  final String party;
  final int? partyId; // customer/supplier id (payment) or employee id (salary)
  final String? partyType; // customer | supplier | employee | unknown | null
  final String status;
  final String? description;

  /// UI-only identity. A payment row and a salary row can share a numeric
  /// `sourceId`, so the grid key combines both. Never sent to the API.
  String get uniqueId => '$source:$sourceId';
}
