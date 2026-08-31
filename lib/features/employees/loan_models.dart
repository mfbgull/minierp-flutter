// Employee Loan models — shaped after `server/src/models/EmployeeLoan.ts`.
// Field names match the API JSON keys verbatim.

import '../../data/models/json_helpers.dart';

/// One employee loan row — from `GET /employees/:id/loans`.
class EmployeeLoan {
  const EmployeeLoan({
    required this.id,
    required this.employeeId,
    required this.amount,
    required this.balance,
    this.purpose,
    this.paymentMethod = 'cash',
    required this.disbursementDate,
    this.dueDate,
    this.monthlyInstallment = 0,
    this.status = 'active',
    this.writtenOffAmount = 0,
    this.notes,
    this.journalEntryId,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
    this.repaidAmount = 0,
    this.repaymentCount = 0,
    this.isOverdue = false,
  });

  factory EmployeeLoan.fromJson(Map<String, dynamic> json) => EmployeeLoan(
        id: asInt(json['id']) ?? 0,
        employeeId: asInt(json['employee_id']) ?? 0,
        amount: asNum(json['amount']) ?? 0,
        balance: asNum(json['balance']) ?? 0,
        purpose: asString(json['purpose']),
        paymentMethod: asString(json['payment_method']) ?? 'cash',
        disbursementDate: asString(json['disbursement_date']) ?? '',
        dueDate: asString(json['due_date']),
        monthlyInstallment: asNum(json['monthly_installment']) ?? 0,
        status: asString(json['status']) ?? 'active',
        writtenOffAmount: asNum(json['written_off_amount']) ?? 0,
        notes: asString(json['notes']),
        journalEntryId: asInt(json['journal_entry_id']),
        createdBy: asInt(json['created_by']),
        createdAt: asString(json['created_at']),
        updatedAt: asString(json['updated_at']),
        repaidAmount: asNum(json['repaid_amount']) ?? 0,
        repaymentCount: asInt(json['repayment_count']) ?? 0,
        isOverdue: json['is_overdue'] == true,
      );

  final int id;
  final int employeeId;
  final num amount;
  final num balance;
  final String? purpose;
  final String paymentMethod;
  final String disbursementDate;
  final String? dueDate;
  final num monthlyInstallment;
  final String status;
  final num writtenOffAmount;
  final String? notes;
  final int? journalEntryId;
  final int? createdBy;
  final String? createdAt;
  final String? updatedAt;
  final num repaidAmount;
  final int repaymentCount;
  final bool isOverdue;

  /// Repayment progress (0.0 to 1.0).
  double get progress =>
      amount > 0 ? (1 - balance / amount).clamp(0, 1).toDouble() : 0;

  /// Display month from disbursement_date.
  String get displayMonth {
    final parts = disbursementDate.split('-');
    if (parts.length != 2) return disbursementDate;
    final month = int.tryParse(parts[1]) ?? 0;
    const months = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[month]} ${parts[0]}';
  }
}

/// Loan summary — from `GET /employees/:id/loans` response.
class LoanSummary {
  const LoanSummary({
    required this.totalLoans,
    required this.activeLoans,
    required this.totalOutstanding,
    required this.totalRepaid,
    required this.overdueLoans,
  });

  factory LoanSummary.fromJson(Map<String, dynamic> json) => LoanSummary(
        totalLoans: asInt(json['total_loans']) ?? 0,
        activeLoans: asInt(json['active_loans']) ?? 0,
        totalOutstanding: asNum(json['total_outstanding']) ?? 0,
        totalRepaid: asNum(json['total_repaid']) ?? 0,
        overdueLoans: asInt(json['overdue_loans']) ?? 0,
      );

  final int totalLoans;
  final int activeLoans;
  final num totalOutstanding;
  final num totalRepaid;
  final int overdueLoans;
}

/// Loans list response — from `GET /employees/:id/loans`.
class LoansListResponse {
  const LoansListResponse({
    required this.loans,
    required this.summary,
  });

  factory LoansListResponse.fromJson(Map<String, dynamic> json) =>
      LoansListResponse(
        loans: (json['loans'] as List<dynamic>? ?? [])
            .map((l) => EmployeeLoan.fromJson(l as Map<String, dynamic>))
            .toList(),
        summary: LoanSummary.fromJson(
            json['summary'] as Map<String, dynamic>? ?? {}),
      );

  final List<EmployeeLoan> loans;
  final LoanSummary summary;
}

/// One repayment row — from `GET /employees/:id/loans/:loanId`.
class LoanRepayment {
  const LoanRepayment({
    required this.id,
    required this.loanId,
    required this.employeeId,
    required this.amount,
    required this.paymentDate,
    this.paymentMethod = 'cash',
    this.referenceNo,
    this.notes,
    this.repaymentType = 'direct',
    this.journalEntryId,
    this.salaryPaymentId,
    this.createdBy,
    this.createdAt,
  });

  factory LoanRepayment.fromJson(Map<String, dynamic> json) => LoanRepayment(
        id: asInt(json['id']) ?? 0,
        loanId: asInt(json['loan_id']) ?? 0,
        employeeId: asInt(json['employee_id']) ?? 0,
        amount: asNum(json['amount']) ?? 0,
        paymentDate: asString(json['payment_date']) ?? '',
        paymentMethod: asString(json['payment_method']) ?? 'cash',
        referenceNo: asString(json['reference_no']),
        notes: asString(json['notes']),
        repaymentType: asString(json['repayment_type']) ?? 'direct',
        journalEntryId: asInt(json['journal_entry_id']),
        salaryPaymentId: asInt(json['salary_payment_id']),
        createdBy: asInt(json['created_by']),
        createdAt: asString(json['created_at']),
      );

  final int id;
  final int loanId;
  final int employeeId;
  final num amount;
  final String paymentDate;
  final String paymentMethod;
  final String? referenceNo;
  final String? notes;
  final String repaymentType;
  final int? journalEntryId;
  final int? salaryPaymentId;
  final int? createdBy;
  final String? createdAt;
}

/// Loan detail with repayments — from `GET /employees/:id/loans/:loanId`.
class LoanDetail {
  const LoanDetail({
    required this.id,
    required this.employeeId,
    required this.amount,
    required this.balance,
    this.purpose,
    this.paymentMethod = 'cash',
    required this.disbursementDate,
    this.dueDate,
    this.monthlyInstallment = 0,
    this.status = 'active',
    this.writtenOffAmount = 0,
    this.notes,
    this.journalEntryId,
    this.createdAt,
    this.updatedAt,
    required this.repayments,
  });

  factory LoanDetail.fromJson(Map<String, dynamic> json) => LoanDetail(
        id: asInt(json['id']) ?? 0,
        employeeId: asInt(json['employee_id']) ?? 0,
        amount: asNum(json['amount']) ?? 0,
        balance: asNum(json['balance']) ?? 0,
        purpose: asString(json['purpose']),
        paymentMethod: asString(json['payment_method']) ?? 'cash',
        disbursementDate: asString(json['disbursement_date']) ?? '',
        dueDate: asString(json['due_date']),
        monthlyInstallment: asNum(json['monthly_installment']) ?? 0,
        status: asString(json['status']) ?? 'active',
        writtenOffAmount: asNum(json['written_off_amount']) ?? 0,
        notes: asString(json['notes']),
        journalEntryId: asInt(json['journal_entry_id']),
        createdAt: asString(json['created_at']),
        updatedAt: asString(json['updated_at']),
        repayments: (json['repayments'] as List<dynamic>? ?? [])
            .map((r) => LoanRepayment.fromJson(r as Map<String, dynamic>))
            .toList(),
      );

  final int id;
  final int employeeId;
  final num amount;
  final num balance;
  final String? purpose;
  final String paymentMethod;
  final String disbursementDate;
  final String? dueDate;
  final num monthlyInstallment;
  final String status;
  final num writtenOffAmount;
  final String? notes;
  final int? journalEntryId;
  final String? createdAt;
  final String? updatedAt;
  final List<LoanRepayment> repayments;

  /// Repayment progress (0.0 to 1.0).
  double get progress =>
      amount > 0 ? (1 - balance / amount).clamp(0, 1).toDouble() : 0;
}

/// Repayment result — from `POST /employees/:id/loans/:loanId/repay`.
class RepayLoanResult {
  const RepayLoanResult({
    required this.id,
    required this.amount,
    required this.loanBalance,
    required this.loanStatus,
    this.journalEntryId,
  });

  factory RepayLoanResult.fromJson(Map<String, dynamic> json) =>
      RepayLoanResult(
        id: asInt(json['id']) ?? 0,
        amount: asNum(json['amount']) ?? 0,
        loanBalance: asNum(json['loan_balance']) ?? 0,
        loanStatus: asString(json['loan_status']) ?? 'active',
        journalEntryId: asInt(json['journal_entry_id']),
      );

  final int id;
  final num amount;
  final num loanBalance;
  final String loanStatus;
  final int? journalEntryId;
}

/// Write-off result — from `POST /employees/:id/loans/:loanId/write-off`.
class WriteOffLoanResult {
  const WriteOffLoanResult({
    required this.id,
    required this.status,
    required this.writtenOffAmount,
    required this.balance,
    this.journalEntryId,
  });

  factory WriteOffLoanResult.fromJson(Map<String, dynamic> json) =>
      WriteOffLoanResult(
        id: asInt(json['id']) ?? 0,
        status: asString(json['status']) ?? 'written_off',
        writtenOffAmount: asNum(json['written_off_amount']) ?? 0,
        balance: asNum(json['balance']) ?? 0,
        journalEntryId: asInt(json['journal_entry_id']),
      );

  final int id;
  final String status;
  final num writtenOffAmount;
  final num balance;
  final int? journalEntryId;
}

/// Active loans result — from `GET /dashboard/active-loans`.
class ActiveLoansResult {
  const ActiveLoansResult({
    required this.totalOutstanding,
    required this.totalLoans,
    required this.overdueCount,
    required this.loans,
  });

  factory ActiveLoansResult.fromJson(Map<String, dynamic> json) =>
      ActiveLoansResult(
        totalOutstanding: asNum(json['total_outstanding']) ?? 0,
        totalLoans: asInt(json['total_loans']) ?? 0,
        overdueCount: asInt(json['overdue_count']) ?? 0,
        loans: (json['loans'] as List<dynamic>? ?? [])
            .map((l) => ActiveLoanRow.fromJson(l as Map<String, dynamic>))
            .toList(),
      );

  final num totalOutstanding;
  final int totalLoans;
  final int overdueCount;
  final List<ActiveLoanRow> loans;
}

/// One active loan row for the dashboard panel.
class ActiveLoanRow {
  const ActiveLoanRow({
    required this.id,
    required this.employeeId,
    required this.employeeCode,
    required this.employeeName,
    required this.amount,
    required this.balance,
    this.purpose,
    required this.status,
    this.dueDate,
    required this.daysUntilDue,
  });

  factory ActiveLoanRow.fromJson(Map<String, dynamic> json) => ActiveLoanRow(
        id: asInt(json['id']) ?? 0,
        employeeId: asInt(json['employee_id']) ?? 0,
        employeeCode: asString(json['employee_code']) ?? '',
        employeeName: asString(json['employee_name']) ?? '',
        amount: asNum(json['amount']) ?? 0,
        balance: asNum(json['balance']) ?? 0,
        purpose: asString(json['purpose']),
        status: asString(json['status']) ?? 'active',
        dueDate: asString(json['due_date']),
        daysUntilDue: asInt(json['days_until_due']) ?? 0,
      );

  final int id;
  final int employeeId;
  final String employeeCode;
  final String employeeName;
  final num amount;
  final num balance;
  final String? purpose;
  final String status;
  final String? dueDate;
  final int daysUntilDue;

  /// Repayment progress (0.0 to 1.0).
  double get progress =>
      amount > 0 ? (1 - balance / amount).clamp(0, 1).toDouble() : 0;
}
