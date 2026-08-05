// Invoice business rules — pure logic, no UI imports (PORTING.md §7).
// 1:1 port of `calculations/invoiceRules.ts`.
//
// Omitted: `getInvoiceStatusBadgeClass` (returns CSS class strings for the
// web client; the Flutter equivalent is the `StatusBadge` widget).

import '../../../data/models/invoice.dart' show Invoice, PaymentMethod;

/// Check if a payment total is valid (greater than 0).
bool isValidPaymentAmount(num totalPaymentAmount) {
  return totalPaymentAmount > 0;
}

/// Check if payment exceeds the invoice balance.
bool doesPaymentExceedBalance(num totalPaymentAmount, num remainingBalance) {
  return totalPaymentAmount > remainingBalance;
}

/// Prepare payment submission data from form state. Each positive
/// payment method becomes one POST /payments body with an
/// `invoice_allocations` entry for the invoice.
List<Map<String, dynamic>> preparePaymentData(
  List<PaymentMethod> paymentMethods, {
  required String customerId,
  required String paymentDate,
  required String invoiceNo,
  String? invoiceId,
  required String paymentNotes,
}) {
  return [
    for (final method in paymentMethods)
      if (method.amount > 0)
        {
          'customer_id': customerId,
          'payment_date': paymentDate,
          'amount': method.amount,
          'payment_method': method.method,
          'reference_no': method.referenceNo?.isNotEmpty == true
              ? method.referenceNo
              : null,
          'description': 'Payment for $invoiceNo',
          'notes': paymentNotes,
          'invoice_allocations': [
            {
              'invoice_id': int.tryParse(invoiceId ?? '0') ?? 0,
              'amount': method.amount,
            },
          ],
        },
  ];
}

/// Validate invoice before submission.
String? validateInvoiceSubmission(String? customerId, int filledItemsCount) {
  if (customerId == null || customerId.isEmpty) {
    return 'Please select a customer';
  }
  if (filledItemsCount == 0) return 'Please add at least one item';
  return null;
}

/// Check if an invoice can be deleted (Draft/Unpaid with no money moved).
/// Operates on the server `Invoice` shape (which carries `returned_amount`).
bool canDeleteInvoice(Invoice invoice) {
  return (invoice.status == 'Draft' || invoice.status == 'Unpaid') &&
      invoice.paidAmount == 0 &&
      invoice.returnedAmount == 0;
}

/// Check if an invoice can show a delete action in the menu.
bool canShowDeleteAction(Invoice invoice) {
  return invoice.paidAmount == 0 &&
      invoice.returnedAmount == 0 &&
      (invoice.status == 'Draft' || invoice.status == 'Unpaid');
}

/// Check if an invoice can be cancelled.
bool canCancelInvoice(Invoice invoice) {
  return invoice.status != 'Cancelled';
}
