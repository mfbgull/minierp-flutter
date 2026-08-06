// StatementData — the shared model for the account statement endpoints
// (`GET /customers/:id/statement` and `GET /suppliers/:id/statement`).
// Both return the identical enveloped shape — `{success, data: {<entity>:
// {id, name}, period: {fromDate, toDate}, openingBalance, closingBalance,
// transactions}}` — differing only in the entity key (`customer` vs
// `supplier`), so one model parses both.
//
// Note the statement transactions are ordered oldest-first (ASC) and
// carry no `id` (the ledger rows do); `LedgerEntry.fromJson` tolerates
// the missing id.

import 'json_helpers.dart';
import 'ledger_entry.dart' show LedgerEntry;

class StatementData {
  const StatementData({
    required this.entityId,
    required this.entityName,
    this.fromDate,
    this.toDate,
    required this.openingBalance,
    required this.closingBalance,
    required this.transactions,
  });

  /// Parses the `data` block of either statement response.
  factory StatementData.fromJson(Map<String, dynamic> json) {
    final supplier = json['supplier'];
    final customer = json['customer'];
    final entity = supplier ?? customer;
    final period = json['period'];
    return StatementData(
      entityId: asInt((entity as Map<String, dynamic>?)?['id']) ?? 0,
      entityName: asString(entity?['name']) ?? '',
      fromDate: asString((period as Map<String, dynamic>?)?['fromDate']),
      toDate: asString(period?['toDate']),
      openingBalance: asNum(json['openingBalance']) ?? 0,
      closingBalance: asNum(json['closingBalance']) ?? 0,
      transactions: _parseTransactions(json['transactions']),
    );
  }

  static List<LedgerEntry> _parseTransactions(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final row in raw)
        if (row is Map<String, dynamic>) LedgerEntry.fromJson(row),
    ];
  }

  final int entityId;
  final String entityName;
  final String? fromDate;
  final String? toDate;
  final num openingBalance;
  final num closingBalance;
  final List<LedgerEntry> transactions;
}
