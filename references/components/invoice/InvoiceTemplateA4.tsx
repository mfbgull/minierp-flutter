import { forwardRef } from 'react';
import './InvoiceTemplateA4.css';

interface InvoiceItem {
  quantity?: number | null;
  unit_price?: number | null;
  rate?: number | null;
  tax_rate?: number | null;
  tax?: number | null;
  discount_type?: string | null;
  discount?: { type?: string | null; value?: number | null } | null;
  discount_value?: number | null;
  item_name?: string | null;
  description?: string | null;
  item_code?: string | null;
}

interface Invoice {
  invoice_no: string;
  status: string;
  invoice_date: string;
  due_date: string;
  payment_terms_days?: number | null;
  customer_name: string;
  customer_address?: string | null;
  customer_phone?: string | null;
  customer_email?: string | null;
  items?: InvoiceItem[] | null;
  notes?: string | null;
  terms?: string | null;
  total_amount: number;
  paid_amount?: number | null;
  balance_amount?: number | null;
  returned_amount?: number | null;
  discount_type?: string | null;
  discount_value?: number | null;
}

interface Company {
  name?: string | null;
  address?: string | null;
  phone?: string | null;
  email?: string | null;
  taxId?: string | null;
}

interface Payment {
  id: number;
  payment_date: string;
  payment_method: string;
  reference_no?: string | null;
  amount: number;
}

interface InvoiceTemplateA4Props {
  invoice: Invoice;
  company?: Company;
  payments?: Payment[];
}

const safeToString = (value: unknown): string => {
  if (value === null || value === undefined) return '0';
  return String(value);
};

const safeParseFloat = (value: unknown): number => {
  const str = safeToString(value);
  const result = parseFloat(str);
  return isNaN(result) ? 0 : result;
};

const InvoiceTemplateA4 = forwardRef<HTMLDivElement, InvoiceTemplateA4Props>(({ invoice, company, payments = [] }, ref) => {
  if (!invoice) {
    return (
      <div className="invoice-a4">
        <div className="invoice-a4-error">No invoice data provided</div>
      </div>
    );
  }

  const formatDate = (dateString: string) => {
    if (!dateString) return '';
    try {
      return new Date(dateString).toLocaleDateString('en-US', {
        year: 'numeric',
        month: 'long',
        day: 'numeric'
      });
    } catch {
      return dateString || '';
    }
  };

  const formatCurrency = (amount: number) => {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD',
      minimumFractionDigits: 2
    }).format(amount || 0);
  };

  const calculateItemTotal = (item: InvoiceItem) => {
    if (!item) return 0;
    try {
      if (item.quantity == null) return 0;
      const quantity = safeParseFloat(item.quantity);
      const rate = safeParseFloat(item.unit_price ?? item.rate ?? 0);
      const taxRate = safeParseFloat(item.tax_rate ?? item.tax ?? 0);
      const discountType = item.discount_type ?? item.discount?.type ?? 'flat';
      const discountValue = safeParseFloat(item.discount_value ?? item.discount?.value ?? 0);

      let subtotal = quantity * rate;
      if (discountType === 'percentage') {
        subtotal -= subtotal * (discountValue / 100);
      } else {
        subtotal -= discountValue;
      }
      subtotal += subtotal * (taxRate / 100);
      return Math.max(0, subtotal);
    } catch {
      return 0;
    }
  };

  const getSubtotal = () => {
    try {
      if (!invoice.items || !Array.isArray(invoice.items)) return 0;
      return invoice.items.reduce((sum, item) => {
        if (!item) return sum;
        const quantity = safeParseFloat(item.quantity ?? 0);
        const rate = safeParseFloat(item.unit_price ?? item.rate ?? 0);
        const itemSubtotal = quantity * rate;
        if (isNaN(itemSubtotal) || !isFinite(itemSubtotal)) return sum;
        return sum + itemSubtotal;
      }, 0);
    } catch {
      return 0;
    }
  };

  const getTotalDiscount = () => {
    try {
      let discount = 0;
      if (invoice.items && Array.isArray(invoice.items)) {
        for (const item of invoice.items) {
          if (!item) continue;
          const quantity = safeParseFloat(item.quantity ?? 0);
          const rate = safeParseFloat(item.unit_price ?? item.rate ?? 0);
          const discountType = item.discount_type ?? item.discount?.type ?? 'flat';
          const discountValue = safeParseFloat(item.discount_value ?? item.discount?.value ?? 0);
          const subtotal = quantity * rate;
          if (discountType === 'percentage') {
            const itemDiscount = subtotal * (discountValue / 100);
            if (isFinite(itemDiscount)) discount += itemDiscount;
          } else {
            if (isFinite(discountValue)) discount += discountValue;
          }
        }
      }
      if (invoice.discount_type && invoice.discount_value != null) {
        const subtotal = getSubtotal();
        const discountValue = safeParseFloat(invoice.discount_value);
        if (invoice.discount_type === 'percentage') {
          const additionalDiscount = subtotal * (discountValue / 100);
          if (isFinite(additionalDiscount)) discount += additionalDiscount;
        } else {
          if (isFinite(discountValue)) discount += discountValue;
        }
      }
      return Math.max(0, discount);
    } catch {
      return 0;
    }
  };

  const getTotalTax = () => {
    try {
      if (!invoice.items || !Array.isArray(invoice.items)) return 0;
      return invoice.items.reduce((sum, item) => {
        if (!item) return sum;
        const quantity = safeParseFloat(item.quantity ?? 0);
        const rate = safeParseFloat(item.unit_price ?? item.rate ?? 0);
        const taxRate = safeParseFloat(item.tax_rate ?? item.tax ?? 0);
        const discountType = item.discount_type ?? item.discount?.type ?? 'flat';
        const discountValue = safeParseFloat(item.discount_value ?? item.discount?.value ?? 0);
        let subtotal = quantity * rate;
        if (discountType === 'percentage') subtotal -= subtotal * (discountValue / 100);
        else subtotal -= discountValue;
        const taxAmount = subtotal * (taxRate / 100);
        if (isNaN(taxAmount) || !isFinite(taxAmount)) return sum;
        return sum + taxAmount;
      }, 0);
    } catch {
      return 0;
    }
  };

  const getStatusClass = (status: string) => {
    const statusMap: Record<string, string> = {
      'Paid': 'a4-status-paid',
      'Partially Paid': 'a4-status-partial',
      'Unpaid': 'a4-status-unpaid',
      'Overdue': 'a4-status-overdue',
      'Draft': 'a4-status-draft',
      'Cancelled': 'a4-status-cancelled'
    };
    return statusMap[status] || 'a4-status-unpaid';
  };

  // Determine if discount/tax columns should be shown
  const hasDiscount = Array.isArray(invoice.items) && invoice.items.some(item => {
    if (!item) return false;
    return safeParseFloat(item.discount_value ?? item.discount?.value ?? 0) > 0;
  }) || (safeParseFloat(invoice.discount_value ?? 0) > 0);

  const hasTax = Array.isArray(invoice.items) && invoice.items.some(item => {
    if (!item) return false;
    return safeParseFloat(item.tax_rate ?? item.tax ?? 0) > 0;
  });

  const tableColCount = 3 + (hasDiscount ? 1 : 0) + (hasTax ? 1 : 0) + 1; // Item + Qty + Rate + ?Discount + ?Tax + Amount

  try {
    return (
      <div className="invoice-a4" ref={ref}>
        {/* ── Compact Header ── */}
        <div className="a4-header">
          <div className="a4-header-left">
            <div className="a4-header-brand">
              <div className="a4-logo-placeholder">
                {(company?.name || 'M')[0]}
              </div>
              <div className="a4-company-info">
                <h1 className="a4-company-name">{company?.name || 'Mini ERP'}</h1>
                <p className="a4-company-detail">{company?.address}</p>
                <p className="a4-company-detail">{company?.phone}</p>
                <p className="a4-company-detail">{company?.email}</p>
                {company?.taxId && <p className="a4-company-detail">Tax ID: {company.taxId}</p>}
              </div>
            </div>
          </div>
          <div className="a4-header-right">
            <h2 className="a4-title">INVOICE</h2>
            <div className="a4-invoice-no">{invoice.invoice_no || 'N/A'}</div>
            <div className={`a4-status ${getStatusClass(invoice.status || 'Unpaid')}`}>
              {invoice.status || 'Unpaid'}
            </div>
          </div>
        </div>

        {/* ── Bill To + Details ── */}
        <div className="a4-info-section">
          <div className="a4-bill-to">
            <h3 className="a4-section-label">Bill To</h3>
            <p className="a4-customer-name">{invoice.customer_name || 'N/A'}</p>
            {invoice.customer_address && <p className="a4-customer-detail">{invoice.customer_address}</p>}
            {invoice.customer_phone && <p className="a4-customer-detail">{invoice.customer_phone}</p>}
            {invoice.customer_email && <p className="a4-customer-detail">{invoice.customer_email}</p>}
          </div>
          <div className="a4-details">
            <div className="a4-detail-row">
              <span className="a4-detail-label">Invoice Date</span>
              <span className="a4-detail-value">{formatDate(invoice.invoice_date || '')}</span>
            </div>
            <div className="a4-detail-row">
              <span className="a4-detail-label">Due Date</span>
              <span className="a4-detail-value">{formatDate(invoice.due_date || '')}</span>
            </div>
            <div className="a4-detail-row">
              <span className="a4-detail-label">Payment Terms</span>
              <span className="a4-detail-value">Net {invoice.payment_terms_days || 14} Days</span>
            </div>
          </div>
        </div>

        {/* ── Items Table ── */}
        <div className="a4-items-section">
          <table className="a4-items-table">
            <thead>
              <tr>
                <th className="a4-col-item">Item</th>
                <th className="a4-col-qty">Qty</th>
                <th className="a4-col-rate">Rate</th>
                {hasDiscount && <th className="a4-col-discount">Discount</th>}
                {hasTax && <th className="a4-col-tax">Tax</th>}
                <th className="a4-col-amount">Amount</th>
              </tr>
            </thead>
            <tbody>
              {Array.isArray(invoice.items) && invoice.items.length > 0 ? (
                invoice.items.map((item, index) => {
                  if (!item) return null;
                  const quantity = safeParseFloat(item.quantity);
                  const rate = safeParseFloat(item.unit_price ?? item.rate);
                  const discountType = item.discount_type ?? item.discount?.type ?? 'flat';
                  const discountValue = safeParseFloat(item.discount_value ?? item.discount?.value);
                  const taxRate = safeParseFloat(item.tax_rate ?? item.tax);

                  return (
                    <tr key={index}>
                      <td className="a4-col-item">
                        <div className="a4-item-name">{item.item_name || item.description || 'N/A'}</div>
                        {item.item_code && <div className="a4-item-code">{item.item_code}</div>}
                      </td>
                      <td className="a4-col-qty">{quantity}</td>
                      <td className="a4-col-rate">{formatCurrency(rate)}</td>
                      {hasDiscount && (
                        <td className="a4-col-discount">
                          {discountValue > 0
                            ? (discountType === 'percentage' ? `${discountValue}%` : formatCurrency(discountValue))
                            : '-'
                          }
                        </td>
                      )}
                      {hasTax && (
                        <td className="a4-col-tax">{taxRate > 0 ? `${taxRate}%` : '-'}</td>
                      )}
                      <td className="a4-col-amount">{formatCurrency(calculateItemTotal(item))}</td>
                    </tr>
                  );
                })
              ) : (
                <tr>
                  <td colSpan={tableColCount} className="a4-no-items">No items found</td>
                </tr>
              )}
            </tbody>
          </table>
        </div>

        {/* ── Summary + Payment History ── */}
        <div className="a4-summary-section">
          <div className="a4-summary-left">
            {invoice.notes && (
              <div className="a4-notes">
                <h4 className="a4-summary-label">Notes</h4>
                <p>{invoice.notes}</p>
              </div>
            )}
            {payments.length > 0 && (
              <div className="a4-payment-history">
                <h4 className="a4-summary-label">Payment History</h4>
                <table className="a4-payments-table">
                  <thead>
                    <tr>
                      <th>Date</th>
                      <th>Method</th>
                      <th>Reference</th>
                      <th className="a4-text-right">Amount</th>
                    </tr>
                  </thead>
                  <tbody>
                    {payments.map(payment => (
                      <tr key={payment.id}>
                        <td>{formatDate(payment.payment_date)}</td>
                        <td>{payment.payment_method}</td>
                        <td>{payment.reference_no || '-'}</td>
                        <td className="a4-text-right">{formatCurrency(payment.amount)}</td>
                      </tr>
                    ))}
                  </tbody>
                  <tfoot>
                    <tr className="a4-payment-total-row">
                      <td colSpan={3}>Total Paid</td>
                      <td className="a4-text-right">
                        {formatCurrency(payments.reduce((sum, p) => sum + Number(p.amount || 0), 0))}
                      </td>
                    </tr>
                  </tfoot>
                </table>
              </div>
            )}
          </div>
          <div className="a4-summary-right">
            <div className="a4-totals">
              <div className="a4-total-row">
                <span>Subtotal</span>
                <span>{formatCurrency(getSubtotal())}</span>
              </div>
              {getTotalDiscount() > 0 && (
                <div className="a4-total-row a4-total-row-discount">
                  <span>Discount</span>
                  <span>-{formatCurrency(getTotalDiscount())}</span>
                </div>
              )}
              {getTotalTax() > 0 && (
                <div className="a4-total-row">
                  <span>Tax</span>
                  <span>{formatCurrency(getTotalTax())}</span>
                </div>
              )}
              <div className="a4-total-row a4-total-row-grand">
                <span>Total</span>
                <span>{formatCurrency(safeParseFloat(invoice.total_amount || 0))}</span>
              </div>
              {invoice.paid_amount && safeParseFloat(invoice.paid_amount) > 0 && (
                <>
                  <div className="a4-total-row a4-total-row-paid">
                    <span>Paid</span>
                    <span>{formatCurrency(safeParseFloat(invoice.paid_amount))}</span>
                  </div>
                  {safeParseFloat(invoice.returned_amount) > 0 && (
                    <div className="a4-total-row a4-total-row-returned">
                      <span>Returned</span>
                      <span>{formatCurrency(safeParseFloat(invoice.returned_amount))}</span>
                    </div>
                  )}
                  <div className="a4-total-row a4-total-row-balance">
                    <span>Balance Due</span>
                    <span>{formatCurrency(safeParseFloat(invoice.balance_amount || 0))}</span>
                  </div>
                </>
              )}
            </div>
          </div>
        </div>

        {/* ── Footer ── */}
        <div className="a4-footer">
          <p className="a4-footer-thanks">Thank you for your business!</p>
          <p className="a4-footer-terms">
            Payment due within {invoice.payment_terms_days || 14} days.
            For questions, contact {company?.email || 'support@minierp.com'}.
          </p>
        </div>
      </div>
    );
  } catch (error) {
    console.error('Error in InvoiceTemplateA4 rendering:', error);
    return (
      <div className="invoice-a4">
        <div className="a4-error">
          <h3>Error rendering invoice</h3>
          <p>An error occurred while rendering the invoice template.</p>
        </div>
      </div>
    );
  }
});

InvoiceTemplateA4.displayName = 'InvoiceTemplateA4';

export default InvoiceTemplateA4;
