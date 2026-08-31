// Employees module models — shaped after `server/src/models/Employee.ts`
// and `types/client-types.ts` (PORTING.md §4). Field names match the API
// JSON keys verbatim; nullable fields arrive as JSON `null` for unfilled
// values.

import '../../data/models/json_helpers.dart';

/// One employee row — the shape both the list and detail endpoints return
/// (`GET /employees` / `GET /employees/:id`).
class Employee {
  const Employee({
    required this.id,
    required this.employeeCode,
    required this.firstName,
    required this.lastName,
    this.email,
    this.phone,
    this.mobile,
    this.cnicNo,
    this.address,
    this.city,
    this.state,
    this.postalCode,
    this.country,
    this.dateOfBirth,
    this.gender,
    this.department,
    this.designation,
    this.employmentType,
    this.dateOfJoining,
    this.dateOfLeaving,
    required this.salary,
    this.bankName,
    this.bankAccountNo,
    this.bankIban,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.profilePhoto,
    this.notes,
    required this.isActive,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  factory Employee.fromJson(Map<String, dynamic> json) => Employee(
    id: asInt(json['id']) ?? 0,
    employeeCode: asString(json['employee_code']) ?? '',
    firstName: asString(json['first_name']) ?? '',
    lastName: asString(json['last_name']) ?? '',
    email: asString(json['email']),
    phone: asString(json['phone']),
    mobile: asString(json['mobile']),
    cnicNo: asString(json['cnic_no']),
    address: asString(json['address']),
    city: asString(json['city']),
    state: asString(json['state']),
    postalCode: asString(json['postal_code']),
    country: asString(json['country']),
    dateOfBirth: asString(json['date_of_birth']),
    gender: asString(json['gender']),
    department: asString(json['department']),
    designation: asString(json['designation']),
    employmentType: asString(json['employment_type']),
    dateOfJoining: asString(json['date_of_joining']),
    dateOfLeaving: asString(json['date_of_leaving']),
    salary: asNum(json['salary']) ?? 0,
    bankName: asString(json['bank_name']),
    bankAccountNo: asString(json['bank_account_no']),
    bankIban: asString(json['bank_iban']),
    emergencyContactName: asString(json['emergency_contact_name']),
    emergencyContactPhone: asString(json['emergency_contact_phone']),
    profilePhoto: asString(json['profile_photo']),
    notes: asString(json['notes']),
    isActive: asBool(json['is_active'], fallback: true),
    createdBy: asInt(json['created_by']),
    createdAt: asString(json['created_at']),
    updatedAt: asString(json['updated_at']),
  );

  final int id;
  final String employeeCode;
  final String firstName;
  final String lastName;
  final String? email;
  final String? phone;
  final String? mobile;
  final String? cnicNo;
  final String? address;
  final String? city;
  final String? state;
  final String? postalCode;
  final String? country;

  /// `YYYY-MM-DD` (PORTING.md §2).
  final String? dateOfBirth;
  final String? gender;
  final String? department;
  final String? designation;
  final String? employmentType;
  final String? dateOfJoining;
  final String? dateOfLeaving;
  final num salary;
  final String? bankName;
  final String? bankAccountNo;
  final String? bankIban;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final String? profilePhoto;
  final String? notes;
  final bool isActive;
  final int? createdBy;
  final String? createdAt;
  final String? updatedAt;

  String get fullName => '$firstName $lastName'.trim();

  /// Create/update body — only non-null fields travel (the server's
  /// update path uses COALESCE so nulls keep the stored value).
  Map<String, dynamic> toJson() => {
    'first_name': firstName,
    'last_name': lastName,
    if (email != null) 'email': email,
    if (phone != null) 'phone': phone,
    if (mobile != null) 'mobile': mobile,
    if (cnicNo != null) 'cnic_no': cnicNo,
    if (address != null) 'address': address,
    if (city != null) 'city': city,
    if (state != null) 'state': state,
    if (postalCode != null) 'postal_code': postalCode,
    if (country != null) 'country': country,
    if (dateOfBirth != null) 'date_of_birth': dateOfBirth,
    if (gender != null) 'gender': gender,
    if (department != null) 'department': department,
    if (designation != null) 'designation': designation,
    if (employmentType != null) 'employment_type': employmentType,
    if (dateOfJoining != null) 'date_of_joining': dateOfJoining,
    if (dateOfLeaving != null) 'date_of_leaving': dateOfLeaving,
    'salary': salary,
    if (bankName != null) 'bank_name': bankName,
    if (bankAccountNo != null) 'bank_account_no': bankAccountNo,
    if (bankIban != null) 'bank_iban': bankIban,
    if (emergencyContactName != null)
      'emergency_contact_name': emergencyContactName,
    if (emergencyContactPhone != null)
      'emergency_contact_phone': emergencyContactPhone,
    if (notes != null) 'notes': notes,
    'is_active': isActive,
  };
}

/// One row of `GET /employees/:id/documents` — `employee_documents`
/// table rows.
class EmployeeDocument {
  const EmployeeDocument({
    required this.id,
    required this.employeeId,
    required this.documentName,
    this.documentType,
    this.documentNumber,
    this.issueDate,
    this.expiryDate,
    this.filePath,
    this.notes,
    this.createdAt,
    this.updatedAt,
  });

  factory EmployeeDocument.fromJson(Map<String, dynamic> json) =>
      EmployeeDocument(
        id: asInt(json['id']) ?? 0,
        employeeId: asInt(json['employee_id']) ?? 0,
        documentName: asString(json['document_name']) ?? '',
        documentType: asString(json['document_type']),
        documentNumber: asString(json['document_number']),
        issueDate: asString(json['issue_date']),
        expiryDate: asString(json['expiry_date']),
        filePath: asString(json['file_path']),
        notes: asString(json['notes']),
        createdAt: asString(json['created_at']),
        updatedAt: asString(json['updated_at']),
      );

  final int id;
  final int employeeId;
  final String documentName;
  final String? documentType;
  final String? documentNumber;
  final String? issueDate;
  final String? expiryDate;
  final String? filePath;
  final String? notes;
  final String? createdAt;
  final String? updatedAt;
}

/// Aggregated salary history row — one per pay_period (month).
/// From `GET /employees/:id/salary/history`.
class SalaryMonthSummary {
  const SalaryMonthSummary({
    required this.payPeriod,
    required this.employeeSalary,
    required this.totalPaid,
    required this.remaining,
    required this.status,
    required this.paymentCount,
    this.advanceCarryover = 0,
    this.advanceSourcePeriod,
    this.firstPaymentDate,
    this.lastPaymentDate,
  });

  factory SalaryMonthSummary.fromJson(Map<String, dynamic> json) =>
      SalaryMonthSummary(
        payPeriod: asString(json['pay_period']) ?? '',
        employeeSalary: asNum(json['employee_salary']) ?? 0,
        totalPaid: asNum(json['total_paid']) ?? 0,
        remaining: asNum(json['remaining']) ?? 0,
        status: asString(json['status']) ?? 'partial',
        paymentCount: asInt(json['payment_count']) ?? 0,
        advanceCarryover: asNum(json['advance_carryover']) ?? 0,
        advanceSourcePeriod: asString(json['advance_source_period']),
        firstPaymentDate: asString(json['first_payment_date']),
        lastPaymentDate: asString(json['last_payment_date']),
      );

  final String payPeriod;
  final num employeeSalary;
  final num totalPaid;
  final num remaining;
  final String status;
  final int paymentCount;
  final num advanceCarryover;
  final String? advanceSourcePeriod;
  final String? firstPaymentDate;
  final String? lastPaymentDate;

  /// Display label for the source month, e.g. "August 2026".
  String? get displaySourceMonth {
    if (advanceSourcePeriod == null) return null;
    final parts = advanceSourcePeriod!.split('-');
    if (parts.length != 2) return advanceSourcePeriod;
    final month = int.tryParse(parts[1]) ?? 0;
    const months = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[month]} ${parts[0]}';
  }

  /// Display label like "August 2026".
  String get displayMonth {
    final parts = payPeriod.split('-');
    if (parts.length != 2) return payPeriod;
    final month = int.tryParse(parts[1]) ?? 0;
    const months = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[month]} ${parts[0]}';
  }
}

/// Individual payment within a month — from `GET /employees/:id/salary/month/:payPeriod`.
class SalaryPayment {
  const SalaryPayment({
    required this.id,
    required this.employeeId,
    required this.amount,
    required this.paymentDate,
    this.paymentMethod,
    this.referenceNo,
    this.notes,
    this.journalEntryId,
    this.paidBy,
    this.paymentType = 'full',
    this.createdAt,
  });

  factory SalaryPayment.fromJson(Map<String, dynamic> json) => SalaryPayment(
    id: asInt(json['id']) ?? 0,
    employeeId: asInt(json['employee_id']) ?? 0,
    amount: asNum(json['amount']) ?? 0,
    paymentDate: asString(json['payment_date']) ?? '',
    paymentMethod: asString(json['payment_method']),
    referenceNo: asString(json['reference_no']),
    notes: asString(json['notes']),
    journalEntryId: asInt(json['journal_entry_id']),
    paidBy: asInt(json['paid_by']),
    paymentType: asString(json['payment_type']) ?? 'full',
    createdAt: asString(json['created_at']),
  );

  final int id;
  final int employeeId;
  final num amount;
  final String paymentDate;
  final String? paymentMethod;
  final String? referenceNo;
  final String? notes;
  final int? journalEntryId;
  final int? paidBy;
  final String paymentType;
  final String? createdAt;
}

/// Month detail response — from `GET /employees/:id/salary/month/:payPeriod`.
class SalaryMonthDetail {
  const SalaryMonthDetail({
    required this.payPeriod,
    required this.employeeSalary,
    required this.totalPaid,
    required this.remaining,
    required this.advanceCarryover,
    required this.payments,
  });

  factory SalaryMonthDetail.fromJson(Map<String, dynamic> json) =>
      SalaryMonthDetail(
        payPeriod: asString(json['pay_period']) ?? '',
        employeeSalary: asNum(json['employee_salary']) ?? 0,
        totalPaid: asNum(json['total_paid']) ?? 0,
        remaining: asNum(json['remaining']) ?? 0,
        advanceCarryover: asNum(json['advance_carryover']) ?? 0,
        payments: (json['payments'] as List<dynamic>? ?? [])
            .map((p) => SalaryPayment.fromJson(p as Map<String, dynamic>))
            .toList(),
      );

  final String payPeriod;
  final num employeeSalary;
  final num totalPaid;
  final num remaining;
  final num advanceCarryover;
  final List<SalaryPayment> payments;
}
