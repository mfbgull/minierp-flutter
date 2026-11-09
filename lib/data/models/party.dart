import 'json_helpers.dart';

class PartyRole {
  PartyRole.fromJson(Map<String, dynamic> json)
    : id = asInt(json['id']) ?? 0,
      code = asString(json['code']) ?? '',
      name = asString(json['name']) ?? '',
      isActive = asBool(json['is_active'], fallback: true);
  final int id;
  final String code;
  final String name;
  final bool isActive;
}

class PartyPosition {
  PartyPosition.fromJson(Map<String, dynamic> json)
    : id = asInt(json['id']) ?? 0,
      displayName = asString(json['display_name']) ?? '',
      customer = json['customer'] == null ? null : PartyRole.fromJson(json['customer'] as Map<String, dynamic>),
      supplier = json['supplier'] == null ? null : PartyRole.fromJson(json['supplier'] as Map<String, dynamic>),
      customerBalance = asNum(json['customer_balance']) ?? 0,
      supplierBalance = asNum(json['supplier_balance']) ?? 0,
      netBalance = asNum(json['net_balance']) ?? 0,
      customerCredit = asNum(json['customer_credit']) ?? 0,
      supplierAdvance = asNum(json['supplier_advance']) ?? 0,
      maximumAdjustment = asNum(json['maximum_adjustment']) ?? 0;
  final int id;
  final String displayName;
  final PartyRole? customer;
  final PartyRole? supplier;
  final num customerBalance;
  final num supplierBalance;
  final num netBalance;
  final num customerCredit;
  final num supplierAdvance;
  final num maximumAdjustment;
  bool get hasBothRoles => customer != null && supplier != null;
}

class PartyAdjustmentTarget {
  PartyAdjustmentTarget.fromJson(Map<String, dynamic> json, {bool invoice = false})
    : id = asInt(json['id']) ?? 0,
      kind = invoice ? 'invoice' : asString(json['kind']) ?? '',
      reference = asString(json['reference']) ?? '',
      date = asString(json['date']) ?? '',
      balance = asNum(json['balance_amount']) ?? 0;
  final int id;
  final String kind;
  final String reference;
  final String date;
  final num balance;
  String get key => '${kind}_$id';
}

class PartyAdjustmentTargets {
  PartyAdjustmentTargets.fromJson(Map<String, dynamic> json)
    : receivables = (json['receivables'] as List<dynamic>).map((e) => PartyAdjustmentTarget.fromJson(e as Map<String, dynamic>, invoice: true)).toList(),
      payables = (json['payables'] as List<dynamic>).map((e) => PartyAdjustmentTarget.fromJson(e as Map<String, dynamic>)).toList();
  final List<PartyAdjustmentTarget> receivables;
  final List<PartyAdjustmentTarget> payables;
}

class PartyAdjustment {
  PartyAdjustment.fromJson(Map<String, dynamic> json)
    : id = asInt(json['id']) ?? 0,
      partyId = asInt(json['party_id']) ?? 0,
      number = asString(json['adjustment_no']) ?? '',
      date = asString(json['adjustment_date']) ?? '',
      amount = asNum(json['amount']) ?? 0,
      status = asString(json['status']) ?? '',
      notes = asString(json['notes']),
      reversalReason = asString(json['reversal_reason']),
      reversalDate = asString(json['reversal_date']),
      receivables = (json['receivables'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>(),
      payables = (json['payables'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
  final int id;
  final int partyId;
  final String number;
  final String date;
  final num amount;
  final String status;
  final String? notes;
  final String? reversalReason;
  final String? reversalDate;
  final List<Map<String, dynamic>> receivables;
  final List<Map<String, dynamic>> payables;
}
