// Customer business logic calculations (PORTING.md §7).
// 1:1 port of `calculations/customerCalculations.ts` — all business rules
// extracted from UI components into pure functions.

import 'dart:math' as math;

import 'package:intl/intl.dart';

import '../../../core/utils/formatters.dart' show Formatters;
import '../../../data/models/customer.dart' show Customer;
import '../../../data/models/invoice.dart' show Invoice;
import '../../../data/models/ledger_entry.dart' show LedgerEntry;
import '../../../data/models/payment.dart' show Payment;

/// `({debit, credit, balance})` result of `calculateLedgerTotals`.
typedef LedgerTotals = ({num debit, num credit, num balance});

/// Computed customer metrics (`CustomerMetrics` in types/client-types.ts).
class CustomerMetrics {
  const CustomerMetrics({
    required this.currentBalance,
    required this.totalDebit,
    required this.totalCredit,
    required this.totalInvoiced,
    required this.totalPaid,
    required this.totalOutstanding,
    required this.creditUtilization,
    required this.overdueInvoicesCount,
    required this.paidInvoicesCount,
    required this.unpaidInvoicesCount,
    required this.overdueInvoicesItemsCount,
    required this.avgDaysToPay,
  });

  final num currentBalance;
  final num totalDebit;
  final num totalCredit;
  final num totalInvoiced;
  final num totalPaid;
  final num totalOutstanding;
  final num creditUtilization;
  final int overdueInvoicesCount;
  final int paidInvoicesCount;
  final int unpaidInvoicesCount;
  final int overdueInvoicesItemsCount;
  final num avgDaysToPay;
}

/// Calculate the running balance from ledger entries.
/// Balance = Total Debit - Total Credit (Debit increases AR, Credit decreases AR).
///
/// RETURN and REFUND entries are excluded from the totals. Additionally,
/// entries related to fully returned invoices (INVOICE entries and their
/// original PAYMENT entries) are excluded from the debit/credit totals so
/// the summary shows only active, non-returned business activity. The
/// balance is always computed from ALL entries for true AR.
LedgerTotals calculateLedgerTotals(
  List<LedgerEntry> ledger, {
  Set<String>? returnedInvoiceNos,
}) {
  if (ledger.isEmpty) return (debit: 0, credit: 0, balance: 0);

  // Exclude RETURN/REFUND entries, plus entries tied to fully returned invoices
  final mainEntries = ledger.where((e) {
    if (e.transactionType == 'RETURN' || e.transactionType == 'REFUND') {
      return false;
    }
    final returned = returnedInvoiceNos;
    if (returned != null && returned.isNotEmpty) {
      // Exclude INVOICE entries for returned invoices
      if (e.transactionType == 'INVOICE' && returned.contains(e.referenceNo)) {
        return false;
      }
      // Exclude PAYMENT entries linked to returned invoices. A payment can
      // be allocated across several invoices; the server returns the
      // comma-joined list in `linked_invoice_no`, so check every member.
      final linked = e.linkedInvoiceNo;
      if (linked != null && linked.isNotEmpty) {
        final linkedNos = linked.split(',').map((s) => s.trim());
        if (linkedNos.any(returned.contains)) return false;
      }
    }
    return true;
  }).toList();

  final totalDebit = mainEntries.fold<num>(0, (sum, item) => sum + item.debit);
  final totalCredit = mainEntries.fold<num>(
    0,
    (sum, item) => sum + item.credit,
  );

  // Balance from ALL entries (including returns & returned invoices)
  // so true AR is reflected regardless of sort order.
  final allDebit = ledger.fold<num>(0, (sum, item) => sum + item.debit);
  final allCredit = ledger.fold<num>(0, (sum, item) => sum + item.credit);

  return (
    debit: totalDebit,
    credit: totalCredit,
    balance: allDebit - allCredit,
  );
}

/// Current balance from debit/credit totals.
num calculateCurrentBalance(num totalDebit, num totalCredit) {
  return totalDebit - totalCredit;
}

/// Total invoiced amount from invoices, net of returns.
/// A fully returned invoice contributes nothing; a partially returned one
/// contributes `total - returned + return_fee` (the return fee remains
/// chargeable, mirroring the server's invoice-balance formula).
num calculateTotalInvoiced(List<Invoice> invoices) {
  return invoices.fold<num>(0, (sum, inv) {
    final net =
        inv.totalAmount - inv.returnedAmount + (inv.returnFee ?? 0);
    return sum + (net > 0 ? net : 0);
  });
}

/// Total paid amount from invoices.
num calculateTotalPaid(List<Invoice> invoices) {
  return invoices.fold<num>(0, (sum, inv) => sum + inv.paidAmount);
}

/// Total outstanding balance from invoices.
num calculateTotalOutstanding(List<Invoice> invoices) {
  return invoices.fold<num>(0, (sum, inv) => sum + inv.balanceAmount);
}

/// Credit utilization percentage.
num calculateCreditUtilization(num balance, num? creditLimit) {
  if (creditLimit != null && creditLimit > 0) {
    return (balance / creditLimit) * 100;
  }
  return 0;
}

/// Overdue invoices (status === 'Overdue' and balance > 0).
List<Invoice> calculateOverdueInvoices(List<Invoice> invoices) {
  return invoices
      .where((inv) => inv.status == 'Overdue' && (inv.balanceAmount) > 0)
      .toList();
}

/// Count paid invoices.
int countPaidInvoices(List<Invoice> invoices) {
  return invoices.where((inv) => inv.status == 'Paid').length;
}

/// Count unpaid/pending invoices.
int countUnpaidInvoices(List<Invoice> invoices) {
  return invoices
      .where((inv) => inv.status == 'Unpaid' || inv.status == 'Partially Paid')
      .length;
}

/// Average days to pay for paid invoices (rounded).
num calculateAverageDaysToPay(List<Invoice> invoices) {
  final paidInvoicesWithPayments = invoices
      .where((inv) => inv.status == 'Paid' && (inv.paidAmount) > 0)
      .toList();

  if (paidInvoicesWithPayments.isEmpty) return 0;

  final totalDays = paidInvoicesWithPayments.fold<num>(0, (sum, inv) {
    final invoiceDate = DateTime.parse(inv.invoiceDate);
    final paidDate = DateTime.parse(inv.updatedAt ?? inv.invoiceDate);
    final diffDays =
        paidDate.difference(invoiceDate).inMilliseconds / (1000 * 60 * 60 * 24);
    return sum + math.max(0, diffDays);
  });

  return (totalDays / paidInvoicesWithPayments.length).round();
}

/// Sort invoices by date descending and return the top N.
List<Invoice> getRecentInvoices(List<Invoice> invoices, {int count = 5}) {
  final sorted = [...invoices];
  sorted.sort(
    (a, b) =>
        DateTime.parse(b.invoiceDate).compareTo(DateTime.parse(a.invoiceDate)),
  );
  return sorted.take(count).toList();
}

/// Sort payments by date descending and return the top N.
List<Payment> getRecentPayments(List<Payment> payments, {int count = 5}) {
  final sorted = [...payments];
  sorted.sort(
    (a, b) =>
        DateTime.parse(b.paymentDate).compareTo(DateTime.parse(a.paymentDate)),
  );
  return sorted.take(count).toList();
}

/// Compute all customer metrics in one pass.
CustomerMetrics computeCustomerMetrics(
  List<Invoice> invoices,
  List<LedgerEntry> ledger,
  Customer? customer,
) {
  final returnedInvoiceNos = invoices
      .where((inv) => inv.status == 'Returned')
      .map((inv) => inv.invoiceNo)
      .toSet();
  final totals = calculateLedgerTotals(
    ledger,
    returnedInvoiceNos: returnedInvoiceNos,
  );
  final totalInvoiced = calculateTotalInvoiced(invoices);
  final totalPaid = calculateTotalPaid(invoices);
  final overdue = calculateOverdueInvoices(invoices);

  return CustomerMetrics(
    currentBalance: totals.balance,
    totalDebit: totals.debit,
    totalCredit: totals.credit,
    totalInvoiced: totalInvoiced,
    totalPaid: totalPaid,
    totalOutstanding: calculateTotalOutstanding(invoices),
    creditUtilization: calculateCreditUtilization(
      totals.balance,
      customer?.creditLimit,
    ),
    overdueInvoicesCount: overdue.length,
    paidInvoicesCount: countPaidInvoices(invoices),
    unpaidInvoicesCount: countUnpaidInvoices(invoices),
    overdueInvoicesItemsCount: overdue.length,
    avgDaysToPay: calculateAverageDaysToPay(invoices),
  );
}

/* ── Legacy display helpers (customer Overview/Invoices/Payments tabs) ── */

/// Format a value as USD currency (legacy `$`-prefixed string used by the
/// customer Overview/Invoices/Payments tabs). For app-wide currency-aware
/// formatting use `core/utils/formatters.dart` (`Formatters.currency`) —
/// the settings-driven symbol is applied by the UI layer.
String formatAsCurrency(Object? value) {
  final parsed = value is num
      ? value
      : double.tryParse(value?.toString() ?? '');
  if (parsed == null) return r'$0.00';
  return NumberFormat.currency(locale: 'en_US', symbol: r'$').format(parsed);
}

/// Format a number with simple 2-decimal formatting (legacy ledger totals).
String formatAsFixed(num value) {
  return value.toStringAsFixed(2);
}

/// Format a date string to a locale date string.
String formatDateString(String? dateStr) {
  if (dateStr == null || dateStr.isEmpty) return '';
  if (DateTime.tryParse(dateStr) == null) return '';
  return Formatters.date(dateStr);
}
