import './ThermalPaymentReceipt.css';

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
  payment_no: string;
  payment_date: string;
  amount: number;
  payment_method: string;
  reference_no: string;
}

interface CustomerInfo {
  name: string;
}

interface CompanyInfo {
  name?: string;
  phone?: string;
  email?: string;
}

interface ThermalPaymentReceiptProps {
  payment: PaymentData;
  customer: CustomerInfo;
  entityType?: 'customer' | 'supplier';
  balance: Balance;
  allocations: Allocation[];
  company?: CompanyInfo;
}

function formatDateShort(dateString: string): string {
  if (!dateString) return '';
  try {
    return new Date(dateString).toLocaleDateString('en-US', {
      year: 'numeric', month: 'short', day: 'numeric',
    });
  } catch {
    return dateString;
  }
}

const fmt = (amount: number): string =>
  new Intl.NumberFormat('en-US', {
    style: 'currency', currency: 'USD', minimumFractionDigits: 2,
  }).format(amount || 0);

export default function ThermalPaymentReceipt({
  payment, customer, balance, allocations, company, entityType = 'customer',
}: ThermalPaymentReceiptProps) {
  const isSupplier = entityType === 'supplier';
  if (!payment) {
    return (
      <div className="tpr-receipt">
        <div className="tpr-error">No payment data provided</div>
      </div>
    );
  }

  return (
    <div className="tpr-receipt">
      {/* Header */}
      <div className="tpr-header">
        <div className="tpr-business-name">{company?.name || 'Mini ERP'}</div>
        <div className="tpr-divider">{'─'.repeat(32)}</div>
        <div className="tpr-line">PAYMENT RECEIPT</div>
        <div className="tpr-line">Receipt: {payment.payment_no}</div>
        <div className="tpr-line">Date: {formatDateShort(payment.payment_date)}</div>
      </div>

      {/* Customer */}
      <div className="tpr-customer">
        <div className="tpr-divider">{'─'.repeat(32)}</div>
        <div className="tpr-line">{customer.name}</div>
      </div>

      {/* Balance Trail */}
      <div className="tpr-balance">
        <div className="tpr-divider">{'─'.repeat(32)}</div>
        <div className="tpr-balance-row">
          <span className="tpr-b-label">Prev Balance</span>
          <span className="tpr-b-value">{fmt(balance.previous_balance)}</span>
        </div>
        <div className="tpr-balance-row tpr-b-payment">
          <span className="tpr-b-label">Payment</span>
          <span className="tpr-b-value">-{fmt(balance.payment_amount)}</span>
        </div>
        <div className="tpr-balance-row tpr-b-new">
          <span className="tpr-b-label">New Balance</span>
          <span className="tpr-b-value">{fmt(balance.current_balance)}</span>
        </div>
      </div>

      {/* Payment Details */}
      <div className="tpr-details">
        <div className="tpr-divider">{'─'.repeat(32)}</div>
        <div className="tpr-line">Method: {payment.payment_method}</div>
        {payment.reference_no && <div className="tpr-line">Ref: {payment.reference_no}</div>}
      </div>

      {/* Allocations */}
      {allocations.length > 0 && (
        <div className="tpr-allocations">
          <div className="tpr-divider">{'─'.repeat(32)}</div>
          <div className="tpr-table-header">
            <span className="tpr-th-inv">{isSupplier ? 'PO' : 'INVOICE'}</span>
            <span className="tpr-th-amt">AMOUNT</span>
          </div>
          {allocations.map((a) => (
            <div className="tpr-alloc-row" key={a.invoice_id}>
              <span className="tpr-alloc-inv">{a.invoice_no}</span>
              <span className="tpr-alloc-amt">{fmt(a.amount)}</span>
            </div>
          ))}
          <div className="tpr-divider">{'─'.repeat(32)}</div>
          <div className="tpr-total-row">
            <span className="tpr-total-label">Total</span>
            <span className="tpr-total-value">{fmt(balance.payment_amount)}</span>
          </div>
        </div>
      )}

      {/* Footer */}
      <div className="tpr-footer">
        <div className="tpr-divider">{'═'.repeat(32)}</div>
        <div className="tpr-footer-thanks">{isSupplier ? 'Payment recorded.' : 'Thank you for your payment!'}</div>
        <div className="tpr-footer-contact">
          {company?.phone && <div>{company.phone}</div>}
          {company?.email && <div>{company.email}</div>}
        </div>
      </div>
    </div>
  );
}
