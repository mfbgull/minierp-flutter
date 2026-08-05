import { forwardRef } from 'react';
import './PaymentReceiptA4.css';

interface Allocation {
  invoice_id: number;
  invoice_no: string;
  amount: number;
}

interface Balance {
  previous_balance: number;
  payment_amount: number;
  current_balance: number;
}

interface PaymentData {
  id: number;
  payment_no: string;
  payment_date: string;
  amount: number;
  payment_method: string;
  reference_no: string;
  notes: string;
}

interface CustomerInfo {
  name: string;
  address: string;
  phone: string;
  email: string;
}

interface CompanyInfo {
  name: string;
  address: string;
  phone: string;
  email: string;
  tax_id: string;
}

interface PaymentReceiptA4Props {
  payment: PaymentData;
  customer: CustomerInfo;
  entityType?: 'customer' | 'supplier';
  balance: Balance;
  allocations: Allocation[];
  company?: CompanyInfo;
}

const formatDate = (dateString: string) => {
  if (!dateString) return '';
  try {
    return new Date(dateString).toLocaleDateString('en-US', {
      year: 'numeric', month: 'long', day: 'numeric',
    });
  } catch {
    return dateString;
  }
};

const fmt = (amount: number) =>
  new Intl.NumberFormat('en-US', {
    style: 'currency', currency: 'USD', minimumFractionDigits: 2,
  }).format(amount || 0);

const PaymentReceiptA4 = forwardRef<HTMLDivElement, PaymentReceiptA4Props>(
  ({ payment, customer, entityType = 'customer', balance, allocations, company }, ref) => {
    if (!payment) {
      return (
        <div className="receipt-a4">
          <div className="receipt-a4-error">No payment data provided</div>
        </div>
      );
    }

    const isSupplier = entityType === 'supplier';

    return (
      <div className="receipt-a4" ref={ref}>
        {/* Header */}
        <div className="r4-header">
          <div className="r4-header-left">
            <div className="r4-header-brand">
              <div className="r4-logo-placeholder">
                {(company?.name || 'M')[0]}
              </div>
              <div className="r4-company-info">
                <h1 className="r4-company-name">{company?.name || 'Mini ERP'}</h1>
                <p className="r4-company-detail">{company?.address}</p>
                <p className="r4-company-detail">{company?.phone}</p>
                <p className="r4-company-detail">{company?.email}</p>
                {company?.tax_id && <p className="r4-company-detail">Tax ID: {company.tax_id}</p>}
              </div>
            </div>
          </div>
          <div className="r4-header-right">
            <h2 className="r4-title">PAYMENT RECEIPT</h2>
            <div className="r4-receipt-no">{payment.payment_no}</div>
          </div>
        </div>

        {/* Customer + Details */}
        <div className="r4-info-section">
          <div className="r4-bill-to">
            <h3 className="r4-section-label">{isSupplier ? 'Paid To' : 'Received From'}</h3>
            <p className="r4-customer-name">{customer.name || 'N/A'}</p>
            {customer.address && <p className="r4-customer-detail">{customer.address}</p>}
            {customer.phone && <p className="r4-customer-detail">{customer.phone}</p>}
            {customer.email && <p className="r4-customer-detail">{customer.email}</p>}
          </div>
          <div className="r4-details">
            <div className="r4-detail-row">
              <span className="r4-detail-label">Receipt Date</span>
              <span className="r4-detail-value">{formatDate(payment.payment_date)}</span>
            </div>
            <div className="r4-detail-row">
              <span className="r4-detail-label">Payment Method</span>
              <span className="r4-detail-value">{payment.payment_method || 'N/A'}</span>
            </div>
            {payment.reference_no && (
              <div className="r4-detail-row">
                <span className="r4-detail-label">Reference No</span>
                <span className="r4-detail-value">{payment.reference_no}</span>
              </div>
            )}
            <div className="r4-detail-row">
              <span className="r4-detail-label">Receipt No</span>
              <span className="r4-detail-value">{payment.payment_no}</span>
            </div>
          </div>
        </div>

        {/* Balance Summary */}
        <div className="r4-balance-section">
          <h3 className="r4-section-label">Payment Summary</h3>
          <table className="r4-balance-table">
            <tbody>
              <tr>
                <td className="r4-balance-label">Previous Balance</td>
                <td className="r4-balance-amount">{fmt(balance.previous_balance)}</td>
              </tr>
              <tr className="r4-balance-payment-row">
                <td className="r4-balance-label">{isSupplier ? 'Payment Made' : 'Payment Received'}</td>
                <td className="r4-balance-amount r4-balance-credit">-{fmt(balance.payment_amount)}</td>
              </tr>
              <tr className="r4-balance-total-row">
                <td className="r4-balance-label">Current Balance</td>
                <td className="r4-balance-amount r4-balance-current">{fmt(balance.current_balance)}</td>
              </tr>
            </tbody>
          </table>
        </div>

        {/* Allocations Table */}
        {allocations.length > 0 && (
          <div className="r4-allocations-section">
            <h3 className="r4-section-label">{isSupplier ? 'Allocated Purchase Orders' : 'Allocated Invoices'}</h3>
            <table className="r4-allocations-table">
              <thead>
                <tr>
                  <th>Invoice No</th>
                  <th className="r4-text-right">Amount</th>
                </tr>
              </thead>
              <tbody>
                {allocations.map((alloc) => (
                  <tr key={alloc.invoice_id}>
                    <td>{alloc.invoice_no}</td>
                    <td className="r4-text-right">{fmt(alloc.amount)}</td>
                  </tr>
                ))}
              </tbody>
              <tfoot>
                <tr className="r4-allocation-total-row">
                  <td>Total Payment</td>
                  <td className="r4-text-right">{fmt(balance.payment_amount)}</td>
                </tr>
              </tfoot>
            </table>
          </div>
        )}

        {/* Notes */}
        {payment.notes && (
          <div className="r4-notes">
            <h4 className="r4-section-label">Notes</h4>
            <p>{payment.notes}</p>
          </div>
        )}

        {/* Footer */}
        <div className="r4-footer">
          <p className="r4-footer-thanks">{isSupplier ? 'Payment recorded.' : 'Thank you for your payment!'}</p>
          {company?.email && (
            <p className="r4-footer-contact">For questions, contact {company.email}</p>
          )}
        </div>
      </div>
    );
  }
);

PaymentReceiptA4.displayName = 'PaymentReceiptA4';
export default PaymentReceiptA4;
