import 'package:flutter/material.dart';

/// Semantic status → M3 color mapping.
class StatusColors {
  const StatusColors(this._scheme);
  final ColorScheme _scheme;

  factory StatusColors.of(BuildContext context) =>
      StatusColors(Theme.of(context).colorScheme);

  Color get success => _scheme.primary;
  Color get neutral => _scheme.outline;
  Color get info => _scheme.tertiary;
  Color get warning => _scheme.tertiary;
  Color get error => _scheme.error;

  Color invoice(String s) => switch (s) {
    'Draft' => neutral, 'Sent' => info, 'Unpaid' => warning,
    'Partially Paid' => info, 'Paid' => success, 'Overdue' => error,
    'Cancelled' => neutral, 'Returned' => _scheme.secondary,
    'Partially Returned' => _scheme.secondary, _ => neutral,
  };

  Color so(String s) => switch (s) {
    'Draft' => neutral, 'Confirmed' => info, 'Delivered' => success,
    'Invoiced' => _scheme.tertiary, 'Completed' => success,
    'Cancelled' => neutral, _ => neutral,
  };

  Color po(String s) => switch (s) {
    'Draft' => neutral, 'Submitted' => info,
    'Partially Received' => warning, 'Completed' => success,
    'Cancelled' => neutral, _ => neutral,
  };

  Color quotation(String s) => switch (s) {
    'Draft' => neutral, 'Sent' => info, 'Accepted' => success,
    'Expired' => warning, 'Converted' => _scheme.tertiary,
    'Rejected' => neutral, _ => neutral,
  };

  Color purchaseReturnStatus(String s) => switch (s) {
    'POSTED' => success, 'VOIDED' => error, _ => neutral,
  };

  Color returnType(String t) => switch (t) {
    'PURCHASE_RETURN' => error, 'PO_RETURN' => warning, _ => neutral,
  };

  Color invoiceReturnType(String t) => switch (t) {
    'RETURN' => _scheme.tertiary, _ => neutral,
  };

  Color expense(String s) => switch (s) {
    'Draft' => neutral, 'Submitted' => info, 'Approved' => success,
    'Paid' => _scheme.tertiary, 'Cancelled' => error, _ => neutral,
  };

  Color stock(String s) => switch (s.toLowerCase()) {
    'in stock' => success, 'low stock' => warning,
    'out of stock' => error, _ => neutral,
  };

  Color activityLogLevel(String l) => switch (l.toUpperCase()) {
    'ERROR' => error, 'WARN' || 'WARNING' => warning,
    'DEBUG' => neutral, _ => _scheme.tertiary,
  };

  Color active(bool isActive) => isActive ? success : neutral;

  Color movementType(String t) => switch (t) {
    'PURCHASE' || 'PRODUCTION' => success,
    'SALE' || 'TRANSFER' => warning,
    'ADJUSTMENT' => _scheme.secondary, _ => neutral,
  };

  Color physicalCount(String s) => switch (s) {
    'Draft' => neutral, 'In Progress' => warning,
    'Completed' => success, 'Cancelled' => error, _ => neutral,
  };
}
