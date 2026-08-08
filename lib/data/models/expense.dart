import 'json_helpers.dart';

/// Port of the server Expense row (expenseController / Expense model) —
/// the shape both the list and detail endpoints return (PORTING.md §4).
///
/// List rows add `created_by_name` (the creator's full name via a LEFT
/// JOIN); the detail response adds `updated_at`. Nullable fields arrive
/// as JSON `null` for unfilled expenses (payment_method, reference_no,
/// vendor_name, project).
class Expense {
  const Expense({
    required this.id,
    required this.expenseNo,
    required this.expenseCategory,
    this.description,
    required this.amount,
    required this.expenseDate,
    this.paymentMethod,
    this.referenceNo,
    this.vendorName,
    this.project,
    required this.status,
    this.createdAt,
    this.updatedAt,
    this.createdByName,
  });

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
    id: asInt(json['id']) ?? 0,
    expenseNo: asString(json['expense_no']) ?? '',
    expenseCategory: asString(json['expense_category']) ?? '',
    description: asString(json['description']),
    amount: asNum(json['amount']) ?? 0,
    expenseDate: asString(json['expense_date']) ?? '',
    paymentMethod: asString(json['payment_method']),
    referenceNo: asString(json['reference_no']),
    vendorName: asString(json['vendor_name']),
    project: asString(json['project']),
    status: asString(json['status']) ?? 'Approved',
    createdAt: asString(json['created_at']),
    updatedAt: asString(json['updated_at']),
    createdByName: asString(json['created_by_name']),
  );

  final int id;
  final String expenseNo;

  /// Matches `expense_categories.category_name` (not an id).
  final String expenseCategory;
  final String? description;
  final num amount;

  /// `YYYY-MM-DD` (PORTING.md §2).
  final String expenseDate;
  final String? paymentMethod;
  final String? referenceNo;
  final String? vendorName;
  final String? project;

  /// Draft | Submitted | Approved | Paid | Cancelled.
  final String status;
  final String? createdAt;
  final String? updatedAt;
  final String? createdByName;

  Map<String, dynamic> toJson() => {
    'id': id,
    'expense_no': expenseNo,
    'expense_category': expenseCategory,
    if (description != null) 'description': description,
    'amount': amount,
    'expense_date': expenseDate,
    if (paymentMethod != null) 'payment_method': paymentMethod,
    if (referenceNo != null) 'reference_no': referenceNo,
    if (vendorName != null) 'vendor_name': vendorName,
    if (project != null) 'project': project,
    'status': status,
    if (createdAt != null) 'created_at': createdAt,
    if (updatedAt != null) 'updated_at': updatedAt,
    if (createdByName != null) 'created_by_name': createdByName,
  };
}

/// One row of `GET /expenses/categories` — the predefined categories
/// (seeded with 15 defaults; expenses reference them by `category_name`).
class ExpenseCategory {
  const ExpenseCategory({
    required this.id,
    required this.categoryName,
    this.description,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  factory ExpenseCategory.fromJson(Map<String, dynamic> json) =>
      ExpenseCategory(
        id: asInt(json['id']) ?? 0,
        categoryName: asString(json['category_name']) ?? '',
        description: asString(json['description']),
        isActive: asBool(json['is_active'], fallback: true),
        createdAt: asString(json['created_at']),
        updatedAt: asString(json['updated_at']),
      );

  final int id;
  final String categoryName;
  final String? description;
  final bool isActive;
  final String? createdAt;
  final String? updatedAt;
}

/// One `{value, label}` option from the expenses reference endpoints
/// (`GET /expenses/status-options`, `/payment-method-options`) — value is
/// what the API stores, label is what the UI shows.
class ExpenseOption {
  const ExpenseOption({required this.value, required this.label});

  factory ExpenseOption.fromJson(Map<String, dynamic> json) => ExpenseOption(
    value: asString(json['value']) ?? '',
    label: asString(json['label']) ?? '',
  );

  final String value;
  final String label;
}
