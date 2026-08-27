import 'json_helpers.dart';

/// Port of the server OwnerCapital row (`ownerEquityController` /
/// `OwnerCapital` model) — `GET /owner-equity/capital` list shape.
///
/// Deletes are soft on the server: rows carry `status` ('posted'|'voided')
/// and void attribution columns; lists exclude voided by default.
class OwnerCapitalEntry {
  const OwnerCapitalEntry({
    required this.id,
    required this.capitalNo,
    required this.capitalDate,
    required this.amount,
    this.paymentMethod,
    this.note,
    this.status = 'posted',
    this.createdAt,
    this.createdByName,
  });

  factory OwnerCapitalEntry.fromJson(Map<String, dynamic> json) =>
      OwnerCapitalEntry(
        id: asInt(json['id']) ?? 0,
        capitalNo: asString(json['capital_no']) ?? '',
        capitalDate: asString(json['capital_date']) ?? '',
        amount: asNum(json['amount']) ?? 0,
        paymentMethod: asString(json['payment_method']),
        note: asString(json['note']),
        status: asString(json['status']) ?? 'posted',
        createdAt: asString(json['created_at']),
        createdByName: asString(json['created_by_name']),
      );

  final int id;
  final String capitalNo;

  /// `YYYY-MM-DD`.
  final String capitalDate;
  final num amount;
  final String? paymentMethod;
  final String? note;
  final String status;
  final String? createdAt;
  final String? createdByName;
}

/// Header row of `GET /owner-equity/withdrawals` — user-entered intent
/// only. The actual batch consumption lives in the detail's movements.
class OwnerWithdrawal {
  const OwnerWithdrawal({
    required this.id,
    required this.withdrawalNo,
    required this.withdrawalDate,
    required this.kind,
    required this.amount,
    this.paymentMethod,
    this.note,
    this.status = 'posted',
    this.itemLineCount = 0,
    this.createdAt,
    this.createdByName,
  });

  factory OwnerWithdrawal.fromJson(Map<String, dynamic> json) =>
      OwnerWithdrawal(
        id: asInt(json['id']) ?? 0,
        withdrawalNo: asString(json['withdrawal_no']) ?? '',
        withdrawalDate: asString(json['withdrawal_date']) ?? '',
        kind: asString(json['kind']) ?? 'cash',
        amount: asNum(json['amount']) ?? 0,
        paymentMethod: asString(json['payment_method']),
        note: asString(json['note']),
        status: asString(json['status']) ?? 'posted',
        itemLineCount: asInt(json['item_line_count']) ?? 0,
        createdAt: asString(json['created_at']),
        createdByName: asString(json['created_by_name']),
      );

  final int id;
  final String withdrawalNo;

  /// `YYYY-MM-DD`.
  final String withdrawalDate;

  /// 'cash' | 'goods'.
  final String kind;

  /// Cash: user input. Goods: Σ batch cost, server-calculated.
  final num amount;
  final String? paymentMethod;
  final String? note;
  final String status;
  final int itemLineCount;
  final String? createdAt;
  final String? createdByName;
}

/// One user-entered line of a goods withdrawal (what the owner took).
class WithdrawalItem {
  const WithdrawalItem({
    required this.id,
    required this.itemId,
    required this.warehouseId,
    required this.quantity,
    this.itemName,
    this.itemCode,
    this.warehouseName,
  });

  factory WithdrawalItem.fromJson(Map<String, dynamic> json) => WithdrawalItem(
    id: asInt(json['id']) ?? 0,
    itemId: asInt(json['item_id']) ?? 0,
    warehouseId: asInt(json['warehouse_id']) ?? 0,
    quantity: asNum(json['quantity']) ?? 0,
    itemName: asString(json['item_name']),
    itemCode: asString(json['item_code']),
    warehouseName: asString(json['warehouse_name']),
  );

  final int id;
  final int itemId;
  final int warehouseId;
  final num quantity;
  final String? itemName;
  final String? itemCode;
  final String? warehouseName;
}

/// One stock-movement row linked to a withdrawal — the actual FIFO/FEFO
/// batch consumption (and its reversals). Immutable history.
class WithdrawalMovement {
  const WithdrawalMovement({
    required this.id,
    required this.movementNo,
    required this.movementType,
    required this.quantity,
    this.unitCost,
    this.batchId,
    this.batchNo,
    this.itemName,
    this.itemCode,
    this.warehouseName,
    this.remarks,
  });

  factory WithdrawalMovement.fromJson(Map<String, dynamic> json) =>
      WithdrawalMovement(
        id: asInt(json['id']) ?? 0,
        movementNo: asString(json['movement_no']) ?? '',
        movementType: asString(json['movement_type']) ?? '',
        quantity: asNum(json['quantity']) ?? 0,
        unitCost: asNum(json['unit_cost']),
        batchId: asInt(json['batch_id']),
        batchNo: asString(json['batch_no']),
        itemName: asString(json['item_name']),
        itemCode: asString(json['item_code']),
        warehouseName: asString(json['warehouse_name']),
        remarks: asString(json['remarks']),
      );

  final int id;
  final String movementNo;
  final String movementType;
  final num quantity;
  final num? unitCost;
  final int? batchId;
  final String? batchNo;
  final String? itemName;
  final String? itemCode;
  final String? warehouseName;
  final String? remarks;

  /// Outbound rows are the consumption; inbound rows are reversals.
  bool get isOutbound => quantity < 0;
}

/// Detail response of `GET /owner-equity/withdrawals/:id` — header plus
/// its item lines and the full movement history.
class OwnerWithdrawalDetail {
  const OwnerWithdrawalDetail({
    required this.withdrawal,
    required this.items,
    required this.movements,
  });

  factory OwnerWithdrawalDetail.fromJson(Map<String, dynamic> json) =>
      OwnerWithdrawalDetail(
        withdrawal: OwnerWithdrawal.fromJson(json),
        items: [
          for (final item in (json['items'] as List<dynamic>? ?? const []))
            WithdrawalItem.fromJson(item! as Map<String, dynamic>),
        ],
        movements: [
          for (final m in (json['movements'] as List<dynamic>? ?? const []))
            WithdrawalMovement.fromJson(m! as Map<String, dynamic>),
        ],
      );

  final OwnerWithdrawal withdrawal;
  final List<WithdrawalItem> items;
  final List<WithdrawalMovement> movements;
}

/// Card totals from `GET /owner-equity/summary` (posted rows only).
class EquitySummary {
  const EquitySummary({
    required this.totalCapitalIn,
    required this.totalWithdrawnCash,
    required this.totalWithdrawnGoods,
    required this.netContributions,
  });

  factory EquitySummary.fromJson(Map<String, dynamic> json) => EquitySummary(
    totalCapitalIn: asNum(json['total_capital_in']) ?? 0,
    totalWithdrawnCash: asNum(json['total_withdrawn_cash']) ?? 0,
    totalWithdrawnGoods: asNum(json['total_withdrawn_goods']) ?? 0,
    netContributions: asNum(json['net_contributions']) ?? 0,
  );

  final num totalCapitalIn;
  final num totalWithdrawnCash;
  final num totalWithdrawnGoods;
  final num netContributions;
}

/// One consumed batch of a quote line — informational costing preview.
class QuoteBatch {
  const QuoteBatch({
    required this.batchId,
    required this.quantity,
    required this.unitCost,
  });

  factory QuoteBatch.fromJson(Map<String, dynamic> json) => QuoteBatch(
    batchId: asInt(json['batchId']),
    quantity: asNum(json['quantity']) ?? 0,
    unitCost: asNum(json['unitCost']) ?? 0,
  );

  final int? batchId;
  final num quantity;
  final num unitCost;
}

/// One quoted line of `POST /owner-equity/withdrawals/quote`.
class QuoteLine {
  const QuoteLine({
    required this.itemId,
    required this.warehouseId,
    required this.batches,
    required this.total,
  });

  factory QuoteLine.fromJson(Map<String, dynamic> json) => QuoteLine(
    itemId: asInt(json['item_id']) ?? 0,
    warehouseId: asInt(json['warehouse_id']) ?? 0,
    batches: [
      for (final b in (json['batches'] as List<dynamic>? ?? const []))
        QuoteBatch.fromJson(b! as Map<String, dynamic>),
    ],
    total: asNum(json['total']) ?? 0,
  );

  final int itemId;
  final int warehouseId;
  final List<QuoteBatch> batches;
  final num total;
}

class WithdrawalQuote {
  const WithdrawalQuote({required this.lines, required this.totalCost});

  factory WithdrawalQuote.fromJson(Map<String, dynamic> json) =>
      WithdrawalQuote(
        lines: [
          for (final l in (json['lines'] as List<dynamic>? ?? const []))
            QuoteLine.fromJson(l! as Map<String, dynamic>),
        ],
        totalCost: asNum(json['totalCost']) ?? 0,
      );

  final List<QuoteLine> lines;
  final num totalCost;
}
