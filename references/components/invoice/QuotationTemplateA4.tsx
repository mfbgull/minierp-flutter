import { forwardRef } from 'react';
import './QuotationTemplateA4.css';

interface QuotationItem {
  item_name?: string | null;
  description?: string | null;
  item_code?: string | null;
  quantity?: number | null;
  unit_price?: number | null;
  rate?: number | null;
  tax_rate?: number | null;
  discount_type?: string | null;
  discount_value?: number | null;
  amount?: number | null;
}

interface Quotation {
  quotation_no: string;
  status: string;
  quotation_date: string;
  expiry_date?: string | null;
  customer_name: string;
  customer_address?: string | null;
  customer_phone?: string | null;
  customer_email?: string | null;
  items?: QuotationItem[] | null;
  notes?: string | null;
  terms?: string | null;
  total_amount: number;
  subtotal?: number | null;
  tax_amount?: number | null;
}

interface Company {
  name?: string | null;
  address?: string | null;
  phone?: string | null;
  email?: string | null;
  taxId?: string | null;
}

interface QuotationTemplateA4Props {
  quotation: Quotation;
  company?: Company;
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

const QuotationTemplateA4 = forwardRef<HTMLDivElement, QuotationTemplateA4Props>(({ quotation, company }, ref) => {
  if (!quotation) {
    return (
      <div className="quotation-a4">
        <div className="q-a4-error">No quotation data provided</div>
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

  const getStatusClass = (status: string) => {
    const statusMap: Record<string, string> = {
      'Draft': 'q-status-draft',
      'Sent': 'q-status-sent',
      'Accepted': 'q-status-accepted',
      'Rejected': 'q-status-rejected',
      'Converted': 'q-status-converted',
      'Expired': 'q-status-expired'
    };
    return statusMap[status] || 'q-status-draft';
  };

  // Calculate values from items if not provided
  const calculateSubtotal = () => {
    if (quotation.subtotal != null) return safeParseFloat(quotation.subtotal);
    if (!quotation.items || !Array.isArray(quotation.items)) return 0;
    return quotation.items.reduce((sum, item) => {
      if (!item) return sum;
      const qty = safeParseFloat(item.quantity ?? 0);
      const rate = safeParseFloat(item.unit_price ?? item.rate ?? 0);
      return sum + qty * rate;
    }, 0);
  };

  const calculateItemTotal = (item: QuotationItem) => {
    if (!item) return 0;
    const qty = safeParseFloat(item.quantity ?? 0);
    const rate = safeParseFloat(item.unit_price ?? item.rate ?? 0);
    const discountType = item.discount_type ?? 'flat';
    const discountValue = safeParseFloat(item.discount_value ?? 0);
    const taxRate = safeParseFloat(item.tax_rate ?? 0);
    let subtotal = qty * rate;
    if (discountType === 'percentage') subtotal -= subtotal * (discountValue / 100);
    else subtotal -= discountValue;
    subtotal += subtotal * (taxRate / 100);
    return Math.max(0, subtotal);
  };

  // Check if any items have discount or tax
  const hasDiscount = Array.isArray(quotation.items) && quotation.items.some(item => {
    if (!item) return false;
    return safeParseFloat(item.discount_value ?? 0) > 0;
  });
  const hasTax = Array.isArray(quotation.items) && quotation.items.some(item => {
    if (!item) return false;
    return safeParseFloat(item.tax_rate ?? 0) > 0;
  });

  const totalDiscount = () => {
    if (!quotation.items || !Array.isArray(quotation.items)) return 0;
    return quotation.items.reduce((sum, item) => {
      if (!item) return sum;
      const qty = safeParseFloat(item.quantity ?? 0);
      const rate = safeParseFloat(item.unit_price ?? item.rate ?? 0);
      const discountType = item.discount_type ?? 'flat';
      const discountValue = safeParseFloat(item.discount_value ?? 0);
      const subtotal = qty * rate;
      if (discountType === 'percentage') return sum + subtotal * (discountValue / 100);
      return sum + discountValue;
    }, 0);
  };

  const totalTax = () => {
    if (!quotation.items || !Array.isArray(quotation.items)) return 0;
    return quotation.items.reduce((sum, item) => {
      if (!item) return sum;
      const qty = safeParseFloat(item.quantity ?? 0);
      const rate = safeParseFloat(item.unit_price ?? item.rate ?? 0);
      const discountType = item.discount_type ?? 'flat';
      const discountValue = safeParseFloat(item.discount_value ?? 0);
      const taxRate = safeParseFloat(item.tax_rate ?? 0);
      let subtotal = qty * rate;
      if (discountType === 'percentage') subtotal -= subtotal * (discountValue / 100);
      else subtotal -= discountValue;
      return sum + subtotal * (taxRate / 100);
    }, 0);
  };

  const tableColCount = 3 + (hasDiscount ? 1 : 0) + (hasTax ? 1 : 0) + 1;

  try {
    return (
      <div className="quotation-a4" ref={ref}>
        {/* ── Compact Header ── */}
        <div className="q-a4-header">
          <div className="q-a4-header-left">
            <div className="q-a4-header-brand">
              <div className="q-a4-logo">{(company?.name || 'M')[0]}</div>
              <div className="q-a4-company-info">
                <h1 className="q-a4-company-name">{company?.name || 'Mini ERP'}</h1>
                <p className="q-a4-company-detail">{company?.address}</p>
                <p className="q-a4-company-detail">{company?.phone}</p>
                <p className="q-a4-company-detail">{company?.email}</p>
                {company?.taxId && <p className="q-a4-company-detail">Tax ID: {company.taxId}</p>}
              </div>
            </div>
          </div>
          <div className="q-a4-header-right">
            <h2 className="q-a4-title">QUOTATION</h2>
            <div className="q-a4-no">{quotation.quotation_no || 'N/A'}</div>
            <div className={`q-a4-status ${getStatusClass(quotation.status || 'Draft')}`}>
              {quotation.status || 'Draft'}
            </div>
          </div>
        </div>

        {/* ── Bill To + Details ── */}
        <div className="q-a4-info-section">
          <div className="q-a4-bill-to">
            <h3 className="q-a4-section-label">Quote To</h3>
            <p className="q-a4-customer-name">{quotation.customer_name || 'N/A'}</p>
            {quotation.customer_address && <p className="q-a4-customer-detail">{quotation.customer_address}</p>}
            {quotation.customer_phone && <p className="q-a4-customer-detail">{quotation.customer_phone}</p>}
            {quotation.customer_email && <p className="q-a4-customer-detail">{quotation.customer_email}</p>}
          </div>
          <div className="q-a4-details">
            <div className="q-a4-detail-row">
              <span className="q-a4-detail-label">Date</span>
              <span className="q-a4-detail-value">{formatDate(quotation.quotation_date || '')}</span>
            </div>
            <div className="q-a4-detail-row">
              <span className="q-a4-detail-label">Valid Until</span>
              <span className="q-a4-detail-value">{formatDate(quotation.expiry_date || '')}</span>
            </div>
          </div>
        </div>

        {/* ── Items Table ── */}
        <div className="q-a4-items-section">
          <table className="q-a4-items-table">
            <thead>
              <tr>
                <th className="q-col-item">Item</th>
                <th className="q-col-qty">Qty</th>
                <th className="q-col-rate">Rate</th>
                {hasDiscount && <th className="q-col-discount">Discount</th>}
                {hasTax && <th className="q-col-tax">Tax</th>}
                <th className="q-col-amount">Amount</th>
              </tr>
            </thead>
            <tbody>
              {Array.isArray(quotation.items) && quotation.items.length > 0 ? (
                quotation.items.map((item, index) => {
                  if (!item) return null;
                  const qty = safeParseFloat(item.quantity);
                  const rate = safeParseFloat(item.unit_price ?? item.rate);
                  const discountType = item.discount_type ?? 'flat';
                  const discountValue = safeParseFloat(item.discount_value);
                  const taxRate = safeParseFloat(item.tax_rate);

                  return (
                    <tr key={index}>
                      <td className="q-col-item">
                        <div className="q-item-name">{item.item_name || item.description || 'N/A'}</div>
                        {item.item_code && <div className="q-item-code">{item.item_code}</div>}
                      </td>
                      <td className="q-col-qty">{qty}</td>
                      <td className="q-col-rate">{formatCurrency(rate)}</td>
                      {hasDiscount && (
                        <td className="q-col-discount">
                          {discountValue > 0
                            ? (discountType === 'percentage' ? `${discountValue}%` : formatCurrency(discountValue))
                            : '-'}
                        </td>
                      )}
                      {hasTax && (
                        <td className="q-col-tax">{taxRate > 0 ? `${taxRate}%` : '-'}</td>
                      )}
                      <td className="q-col-amount">{formatCurrency(calculateItemTotal(item))}</td>
                    </tr>
                  );
                })
              ) : (
                <tr>
                  <td colSpan={tableColCount} className="q-no-items">No items found</td>
                </tr>
              )}
            </tbody>
          </table>
        </div>

        {/* ── Summary ── */}
        <div className="q-a4-summary-section">
          <div className="q-a4-summary-left">
            {quotation.notes && (
              <div className="q-a4-notes">
                <h4 className="q-a4-summary-label">Notes</h4>
                <p>{quotation.notes}</p>
              </div>
            )}
            {quotation.terms && (
              <div className="q-a4-terms">
                <h4 className="q-a4-summary-label">Terms & Conditions</h4>
                <p>{quotation.terms}</p>
              </div>
            )}
          </div>
          <div className="q-a4-summary-right">
            <div className="q-a4-totals">
              <div className="q-a4-total-row">
                <span>Subtotal</span>
                <span>{formatCurrency(calculateSubtotal())}</span>
              </div>
              {totalDiscount() > 0 && (
                <div className="q-a4-total-row q-a4-total-row-discount">
                  <span>Discount</span>
                  <span>-{formatCurrency(totalDiscount())}</span>
                </div>
              )}
              {totalTax() > 0 && (
                <div className="q-a4-total-row">
                  <span>Tax</span>
                  <span>{formatCurrency(totalTax())}</span>
                </div>
              )}
              <div className="q-a4-total-row q-a4-total-row-grand">
                <span>Total</span>
                <span>{formatCurrency(safeParseFloat(quotation.total_amount || 0))}</span>
              </div>
            </div>
          </div>
        </div>

        {/* ── Footer ── */}
        <div className="q-a4-footer">
          <p className="q-a4-footer-thanks">Thank you for considering our proposal!</p>
          <p className="q-a4-footer-terms">
            This quotation is valid until {formatDate(quotation.expiry_date || '')}.
            For questions, contact {company?.email || 'support@minierp.com'}.
          </p>
        </div>
      </div>
    );
  } catch (error) {
    console.error('Error in QuotationTemplateA4:', error);
    return (
      <div className="quotation-a4">
        <div className="q-a4-error">
          <h3>Error rendering quotation</h3>
          <p>An error occurred while rendering the quotation template.</p>
        </div>
      </div>
    );
  }
});

QuotationTemplateA4.displayName = 'QuotationTemplateA4';
export default QuotationTemplateA4;
