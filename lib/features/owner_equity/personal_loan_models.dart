// Owner Personal Loan models — purely record-keeping, no GL impact.
// Field names match the API JSON keys verbatim.

import '../../data/models/json_helpers.dart';

/// One owner personal loan row — from `GET /owner-equity/personal-loans`.
class PersonalLoan {
  const PersonalLoan({
    required this.id,
    required this.loanNo,
    required this.borrowerName,
    this.borrowerId,
    this.borrowerType,
    required this.amount,
    required this.balance,
    this.currency = 'PKR',
    required this.loanDate,
    this.dueDate,
    this.purpose,
    this.status = 'pending',
    this.notes,
    this.repaymentCount = 0,
    this.repaidAmount = 0,
    this.createdByName,
    this.createdAt,
    this.updatedAt,
  });

  factory PersonalLoan.fromJson(Map<String, dynamic> json) => PersonalLoan(
        id: asInt(json['id']) ?? 0,
        loanNo: asString(json['loan_no']) ?? '',
        borrowerName: asString(json['borrower_name']) ?? '',
        borrowerId: asInt(json['borrower_id']),
        borrowerType: asString(json['borrower_type']),
        amount: asNum(json['amount']) ?? 0,
        balance: asNum(json['balance']) ?? 0,
        currency: asString(json['currency']) ?? 'PKR',
        loanDate: asString(json['loan_date']) ?? '',
        dueDate: asString(json['due_date']),
        purpose: asString(json['purpose']),
        status: asString(json['status']) ?? 'pending',
        notes: asString(json['notes']),
        repaymentCount: asInt(json['repayment_count']) ?? 0,
        repaidAmount: asNum(json['repaid_amount']) ?? 0,
        createdByName: asString(json['created_by_name']),
        createdAt: asString(json['created_at']),
        updatedAt: asString(json['updated_at']),
      );

  final int id;
  final String loanNo;
  final String borrowerName;
  final int? borrowerId;
  final String? borrowerType;
  final num amount;
  final num balance;
  final String currency;
  final String loanDate;
  final String? dueDate;
  final String? purpose;
  final String status;
  final String? notes;
  final int repaymentCount;
  final num repaidAmount;
  final String? createdByName;
  final String? createdAt;
  final String? updatedAt;

  /// Repayment progress (0.0 to 1.0).
  double get progress =>
      amount > 0 ? (1 - balance / amount).clamp(0, 1).toDouble() : 0;

  /// Whether the loan has active repayments.
  bool get hasRepayments => repaymentCount > 0;
}

/// Loan summary — from `GET /owner-equity/personal-loans/summary`.
class PersonalLoanSummary {
  const PersonalLoanSummary({
    required this.totalLent,
    required this.totalRepaid,
    required this.totalPending,
    required this.activeCount,
    required this.settledCount,
    required this.writtenOffCount,
    this.currencyBreakdown = const [],
  });

  factory PersonalLoanSummary.fromJson(Map<String, dynamic> json) =>
      PersonalLoanSummary(
        totalLent: asNum(json['total_lent']) ?? 0,
        totalRepaid: asNum(json['total_repaid']) ?? 0,
        totalPending: asNum(json['total_pending']) ?? 0,
        activeCount: asInt(json['active_count']) ?? 0,
        settledCount: asInt(json['settled_count']) ?? 0,
        writtenOffCount: asInt(json['written_off_count']) ?? 0,
        currencyBreakdown: (json['currency_breakdown'] as List<dynamic>? ?? [])
            .map((c) => CurrencyBreakdown.fromJson(c as Map<String, dynamic>))
            .toList(),
      );

  final num totalLent;
  final num totalRepaid;
  final num totalPending;
  final int activeCount;
  final int settledCount;
  final int writtenOffCount;
  final List<CurrencyBreakdown> currencyBreakdown;
}

/// Per-currency breakdown in summary.
class CurrencyBreakdown {
  const CurrencyBreakdown({
    required this.currency,
    required this.totalLent,
    required this.totalPending,
  });

  factory CurrencyBreakdown.fromJson(Map<String, dynamic> json) =>
      CurrencyBreakdown(
        currency: asString(json['currency']) ?? 'PKR',
        totalLent: asNum(json['total_lent']) ?? 0,
        totalPending: asNum(json['total_pending']) ?? 0,
      );

  final String currency;
  final num totalLent;
  final num totalPending;
}

/// One repayment row — from `GET /owner-equity/personal-loans/:id`.
class PersonalLoanRepayment {
  const PersonalLoanRepayment({
    required this.id,
    required this.loanId,
    required this.amount,
    required this.paymentDate,
    this.notes,
    this.createdByName,
    this.createdAt,
  });

  factory PersonalLoanRepayment.fromJson(Map<String, dynamic> json) =>
      PersonalLoanRepayment(
        id: asInt(json['id']) ?? 0,
        loanId: asInt(json['loan_id']) ?? 0,
        amount: asNum(json['amount']) ?? 0,
        paymentDate: asString(json['payment_date']) ?? '',
        notes: asString(json['notes']),
        createdByName: asString(json['created_by_name']),
        createdAt: asString(json['created_at']),
      );

  final int id;
  final int loanId;
  final num amount;
  final String paymentDate;
  final String? notes;
  final String? createdByName;
  final String? createdAt;
}

/// Loan detail with repayments — from `GET /owner-equity/personal-loans/:id`.
class PersonalLoanDetail {
  const PersonalLoanDetail({
    required this.loan,
    required this.repayments,
  });

  factory PersonalLoanDetail.fromJson(Map<String, dynamic> json) =>
      PersonalLoanDetail(
        loan: PersonalLoan.fromJson(json),
        repayments: (json['repayments'] as List<dynamic>? ?? [])
            .map((r) =>
                PersonalLoanRepayment.fromJson(r as Map<String, dynamic>))
            .toList(),
      );

  final PersonalLoan loan;
  final List<PersonalLoanRepayment> repayments;
}

/// Borrower row — from `GET /owner-equity/borrowers`.
class PersonalLoanBorrower {
  const PersonalLoanBorrower({
    required this.id,
    required this.name,
    this.phone,
    this.linkedType,
    this.linkedId,
    this.isActive = true,
    this.loanCount = 0,
    this.totalLent = 0,
    this.totalPending = 0,
    this.createdAt,
  });

  factory PersonalLoanBorrower.fromJson(Map<String, dynamic> json) =>
      PersonalLoanBorrower(
        id: asInt(json['id']) ?? 0,
        name: asString(json['name']) ?? '',
        phone: asString(json['phone']),
        linkedType: asString(json['linked_type']),
        linkedId: asInt(json['linked_id']),
        isActive: json['is_active'] != 0,
        loanCount: asInt(json['loan_count']) ?? 0,
        totalLent: asNum(json['total_lent']) ?? 0,
        totalPending: asNum(json['total_pending']) ?? 0,
        createdAt: asString(json['created_at']),
      );

  final int id;
  final String name;
  final String? phone;
  final String? linkedType;
  final int? linkedId;
  final bool isActive;
  final int loanCount;
  final num totalLent;
  final num totalPending;
  final String? createdAt;

  /// Display badge based on linked type.
  String? get badge => switch (linkedType) {
        'customer' => 'Customer',
        'supplier' => 'Supplier',
        _ => null,
      };
}

/// Repayment result — from `POST /owner-equity/personal-loans/:id/repayments`.
class PersonalLoanRepayResult {
  const PersonalLoanRepayResult({
    required this.id,
    required this.amount,
    required this.loanBalance,
    required this.loanStatus,
  });

  factory PersonalLoanRepayResult.fromJson(Map<String, dynamic> json) =>
      PersonalLoanRepayResult(
        id: asInt(json['id']) ?? 0,
        amount: asNum(json['amount']) ?? 0,
        loanBalance: asNum(json['loan_balance']) ?? 0,
        loanStatus: asString(json['loan_status']) ?? 'pending',
      );

  final int id;
  final num amount;
  final num loanBalance;
  final String loanStatus;
}
