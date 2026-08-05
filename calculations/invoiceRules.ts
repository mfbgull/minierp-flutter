/**
 * Invoice business rules — extracted from UI components.
 * No UI imports, no React — pure business logic.
 */

/**
 * Check if a payment total is valid (greater than 0).
 */
export function isValidPaymentAmount(totalPaymentAmount: number): boolean {
  return !!totalPaymentAmount && totalPaymentAmount > 0;
}

/**
 * Check if payment exceeds the invoice balance.
 */
export function doesPaymentExceedBalance(
  totalPaymentAmount: number,
  remainingBalance: number,
): boolean {
  return totalPaymentAmount > remainingBalance;
}

/**
 * Prepare payment submission data from form state.
 */
export function preparePaymentData(
  paymentMethods: Array<{ method: string; amount: number; reference_no: string }>,
  customer_id: number | string,
  paymentDate: string,
  invoiceNo: string,
  invoiceId: string | undefined,
  paymentNotes: string,
): Array<Record<string, unknown>> {
  return paymentMethods
    .filter((method) => method.amount && parseFloat(String(method.amount)) > 0)
    .map((method) => ({
      customer_id,
      payment_date: paymentDate,
      amount: parseFloat(String(method.amount)),
      payment_method: method.method,
      reference_no: method.reference_no || null,
      description: `Payment for ${invoiceNo}`,
      notes: paymentNotes,
      invoice_allocations: [
        {
          invoice_id: parseInt(invoiceId || '0', 10),
          amount: parseFloat(String(method.amount)),
        },
      ],
    }));
}

/**
 * Validate invoice before submission.
 */
export function validateInvoiceSubmission(
  customerId: number | string | undefined,
  filledItemsCount: number,
): string | null {
  if (!customerId) return 'Please select a customer';
  if (filledItemsCount === 0) return 'Please add at least one item';
  return null;
}

/**
 * Filter out empty invoice items.
 */
export function filterFilledItems<T extends { item_id?: number | string; description?: string }>(
  items: T[],
): T[] {
  return items.filter((item) => item.item_id || item.description);
}

/**
 * Check if an invoice can be deleted.
 * (Used by CustomerDetailPage components)
 */
export function canDeleteInvoice(invoice: { status: string; paid_amount?: number; returned_amount?: number }): boolean {
  const paidAmount = invoice.paid_amount || 0;
  const returnedAmount = invoice.returned_amount || 0;
  return ['Draft', 'Unpaid'].includes(invoice.status) && paidAmount === 0 && returnedAmount === 0;
}

/**
 * Check if an invoice can show a delete action in the menu.
 * (Used by CustomerDetailPage components)
 */
export function canShowDeleteAction(invoice: { status: string; paid_amount?: number; returned_amount?: number }): boolean {
  return (
    (invoice.paid_amount || 0) === 0 &&
    (invoice.returned_amount || 0) === 0 &&
    ['Draft', 'Unpaid'].includes(invoice.status)
  );
}

/**
 * Check if an invoice can be cancelled.
 * (Used by CustomerDetailPage components)
 */
export function canCancelInvoice(invoice: { status: string }): boolean {
  return invoice.status !== 'Cancelled';
}

/**
 * Get the CSS status badge class for an invoice status.
 * (Used by CustomerDetailPage components)
 */
export function getInvoiceStatusBadgeClass(status: string): string {
  const s = (status || '').toLowerCase().replace(' ', '-');
  switch (s) {
    case 'paid':
      return 'status-badge paid';
    case 'unpaid':
      return 'status-badge unpaid';
    case 'partially-paid':
      return 'status-badge partially-paid';
    case 'overdue':
      return 'status-badge overdue';
    default:
      return 'status-badge';
  }
}
