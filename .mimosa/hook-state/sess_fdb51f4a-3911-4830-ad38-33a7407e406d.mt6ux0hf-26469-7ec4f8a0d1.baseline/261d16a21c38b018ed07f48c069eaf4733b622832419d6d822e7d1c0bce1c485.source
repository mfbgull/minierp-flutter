import { forwardRef } from 'react';
import './PurchaseOrderTemplateA4.css';

interface POItem {
  item_name?: string | null;
  item_code?: string | null;
  description?: string | null;
  quantity?: number | null;
  unit_price?: number | null;
  amount?: number | null;
  received_quantity?: number | null;
  unit_of_measure?: string | null;
}

interface PurchaseOrder {
  po_no: string;
  status: string;
  po_date: string;
  expected_delivery_date?: string | null;
  supplier_name: string;
  supplier_address?: string | null;
  supplier_phone?: string | null;
  supplier_email?: string | null;
  warehouse_name?: string | null;
  items?: POItem[] | null;
  notes?: string | null;
  total_amount: number;
}

interface Company {
  name?: string | null;
  address?: string | null;
  phone?: string | null;
  email?: string | null;
}

interface PurchaseOrderTemplateA4Props {
  purchaseOrder: PurchaseOrder;
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

const PurchaseOrderTemplateA4 = forwardRef<HTMLDivElement, PurchaseOrderTemplateA4Props>(({ purchaseOrder, company }, ref) => {
  if (!purchaseOrder) {
    return <div className="po-a4"><div className="po-a4-error">No purchase order data provided</div></div>;
  }

  const formatDate = (dateString: string) => {
    if (!dateString) return '';
    try { return new Date(dateString).toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' }); }
    catch { return dateString || ''; }
  };

  const formatCurrency = (amount: number) => {
    return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', minimumFractionDigits: 2 }).format(amount || 0);
  };

  const getStatusClass = (status: string) => {
    const map: Record<string, string> = {
      'Draft': 'po-status-draft',
      'Submitted': 'po-status-submitted',
      'Partially Received': 'po-status-partial',
      'Completed': 'po-status-completed',
      'Cancelled': 'po-status-cancelled'
    };
    return map[status] || 'po-status-draft';
  };

  try {
    return (
      <div className="po-a4" ref={ref}>
        {/* ── Header ── */}
        <div className="po-a4-header">
          <div className="po-a4-header-left">
            <div className="po-a4-header-brand">
              <div className="po-a4-logo">{(company?.name || 'M')[0]}</div>
              <div className="po-a4-company-info">
                <h1 className="po-a4-company-name">{company?.name || 'Mini ERP'}</h1>
                <p className="po-a4-company-detail">{company?.address}</p>
                <p className="po-a4-company-detail">{company?.phone}</p>
                <p className="po-a4-company-detail">{company?.email}</p>
              </div>
            </div>
          </div>
          <div className="po-a4-header-right">
            <h2 className="po-a4-title">PURCHASE ORDER</h2>
            <div className="po-a4-no">{purchaseOrder.po_no || 'N/A'}</div>
            <div className={`po-a4-status ${getStatusClass(purchaseOrder.status || 'Draft')}`}>
              {purchaseOrder.status || 'Draft'}
            </div>
          </div>
        </div>

        {/* ── Supplier + Details ── */}
        <div className="po-a4-info-section">
          <div className="po-a4-supplier">
            <h3 className="po-a4-section-label">Supplier</h3>
            <p className="po-a4-supplier-name">{purchaseOrder.supplier_name || 'N/A'}</p>
            {purchaseOrder.supplier_address && <p className="po-a4-supplier-detail">{purchaseOrder.supplier_address}</p>}
            {purchaseOrder.supplier_phone && <p className="po-a4-supplier-detail">{purchaseOrder.supplier_phone}</p>}
            {purchaseOrder.supplier_email && <p className="po-a4-supplier-detail">{purchaseOrder.supplier_email}</p>}
          </div>
          <div className="po-a4-details">
            <div className="po-a4-detail-row">
              <span className="po-a4-detail-label">PO Date</span>
              <span className="po-a4-detail-value">{formatDate(purchaseOrder.po_date || '')}</span>
            </div>
            {purchaseOrder.expected_delivery_date && (
              <div className="po-a4-detail-row">
                <span className="po-a4-detail-label">Expected Delivery</span>
                <span className="po-a4-detail-value">{formatDate(purchaseOrder.expected_delivery_date)}</span>
              </div>
            )}
            {purchaseOrder.warehouse_name && (
              <div className="po-a4-detail-row">
                <span className="po-a4-detail-label">Warehouse</span>
                <span className="po-a4-detail-value">{purchaseOrder.warehouse_name}</span>
              </div>
            )}
          </div>
        </div>

        {/* ── Items Table ── */}
        <div className="po-a4-items-section">
          <table className="po-a4-items-table">
            <thead>
              <tr>
                <th className="po-col-item">Item</th>
                <th className="po-col-qty">Qty</th>
                <th className="po-col-uom">UOM</th>
                <th className="po-col-rate">Unit Price</th>
                <th className="po-col-amount">Total</th>
              </tr>
            </thead>
            <tbody>
              {Array.isArray(purchaseOrder.items) && purchaseOrder.items.length > 0 ? (
                purchaseOrder.items.map((item, index) => {
                  if (!item) return null;
                  const qty = safeParseFloat(item.quantity);
                  const rate = safeParseFloat(item.unit_price);
                  const amount = safeParseFloat(item.amount ?? qty * rate);
                  return (
                    <tr key={index}>
                      <td className="po-col-item">
                        <div className="po-item-name">{item.item_name || item.description || 'N/A'}</div>
                        {item.item_code && <div className="po-item-code">{item.item_code}</div>}
                      </td>
                      <td className="po-col-qty">{qty}</td>
                      <td className="po-col-uom">{item.unit_of_measure || 'Nos'}</td>
                      <td className="po-col-rate">{formatCurrency(rate)}</td>
                      <td className="po-col-amount">{formatCurrency(amount)}</td>
                    </tr>
                  );
                })
              ) : (
                <tr><td colSpan={5} className="po-no-items">No items found</td></tr>
              )}
            </tbody>
          </table>
        </div>

        {/* ── Summary ── */}
        <div className="po-a4-summary-section">
          <div className="po-a4-summary-left">
            {purchaseOrder.notes && (
              <div className="po-a4-notes">
                <h4 className="po-a4-summary-label">Notes</h4>
                <p>{purchaseOrder.notes}</p>
              </div>
            )}
          </div>
          <div className="po-a4-summary-right">
            <div className="po-a4-totals">
              <div className="po-a4-total-row po-a4-total-row-grand">
                <span>Total Amount</span>
                <span>{formatCurrency(safeParseFloat(purchaseOrder.total_amount || 0))}</span>
              </div>
            </div>
          </div>
        </div>

        {/* ── Footer ── */}
        <div className="po-a4-footer">
          <p className="po-a4-footer-thanks">Thank you for your prompt service!</p>
          <p className="po-a4-footer-terms">
            For questions, contact {company?.email || 'support@minierp.com'}.
          </p>
        </div>
      </div>
    );
  } catch (error) {
    console.error('Error in PurchaseOrderTemplateA4:', error);
    return <div className="po-a4"><div className="po-a4-error"><h3>Error rendering PO</h3></div></div>;
  }
});

PurchaseOrderTemplateA4.displayName = 'PurchaseOrderTemplateA4';
export default PurchaseOrderTemplateA4;
