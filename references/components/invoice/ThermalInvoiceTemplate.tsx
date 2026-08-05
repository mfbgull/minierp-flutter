import { useState, useEffect } from 'react';

import QRCode from 'qrcode';
import './ThermalInvoiceTemplate.css';

interface InvoiceItem {
  quantity?: number | null;
  unit_price?: number | null;
  rate?: number | null;
  item_name?: string | null;
  description?: string | null;
  item_code?: string | null;
}

interface Invoice {
  invoice_no: string;
  invoice_date: string;
  customer_name: string;
  customer_address?: string | null;
  customer_phone?: string | null;
  customer_email?: string | null;
  items?: InvoiceItem[] | null;
  total_amount: number;
  paid_amount?: number | null;
  balance_amount?: number | null;
  returned_amount?: number | null;
  payment_terms_days?: number | null;
}

interface Company {
  name?: string | null;
  phone?: string | null;
  email?: string | null;
}

interface ThermalInvoiceTemplateProps {
  invoice: Invoice;
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

function formatDateShort(dateString: string): string {
  if (!dateString) return '';
  try {
    return new Date(dateString).toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'short',
      day: 'numeric'
    });
  } catch {
    return dateString || '';
  }
}

function formatCurrency(amount: number): string {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    minimumFractionDigits: 2
  }).format(amount || 0);
}

export default function ThermalInvoiceTemplate({ invoice, company }: ThermalInvoiceTemplateProps) {
  const [qrSvg, setQrSvg] = useState('');

  useEffect(() => {
    if (!invoice) return;
    const qrData = `INV:${invoice.invoice_no}|TOTAL:${formatCurrency(invoice.total_amount || 0)}|`;
    QRCode.toString(qrData, {
      type: 'svg',
      margin: 1,
      width: 120,
      color: { dark: '#000', light: '#fff' }
    }).then(setQrSvg).catch(() => setQrSvg(''));
  }, [invoice]);

  if (!invoice) {
    return (
      <div className="thermal-receipt">
        <div className="thermal-error">No invoice data provided</div>
      </div>
    );
  }

  const getSubtotal = () => {
    try {
      if (!invoice.items || !Array.isArray(invoice.items)) return 0;
      return invoice.items.reduce((sum, item) => {
        if (!item) return sum;
        const qty = safeParseFloat(item.quantity ?? 0);
        const rate = safeParseFloat(item.unit_price ?? item.rate ?? 0);
        return sum + qty * rate;
      }, 0);
    } catch {
      return 0;
    }
  };

  const items = Array.isArray(invoice.items) ? invoice.items.filter(Boolean) : [];

  // ── Render ──
  return (
    <div className="thermal-receipt">
      {/* Header */}
      <div className="thermal-header">
        <div className="thermal-business-name">{company?.name || 'Mini ERP'}</div>
        <div className="thermal-divider">{'─'.repeat(32)}</div>
        <div className="thermal-line">Invoice: {invoice.invoice_no || 'N/A'}</div>
        <div className="thermal-line">Date: {formatDateShort(invoice.invoice_date || '')}</div>
      </div>

      {/* Customer */}
      <div className="thermal-customer">
        <div className="thermal-divider">{'─'.repeat(32)}</div>
        <div className="thermal-line">{invoice.customer_name || 'N/A'}</div>
        {invoice.customer_phone && <div className="thermal-line">{invoice.customer_phone}</div>}
      </div>

      {/* Items Table */}
      <div className="thermal-items">
        <div className="thermal-divider">{'─'.repeat(32)}</div>
        <div className="thermal-table-header">
          <span className="th-item">ITEM</span>
          <span className="th-qty">QTY</span>
          <span className="th-amount">AMOUNT</span>
        </div>
        <div className="thermal-divider">{'─'.repeat(32)}</div>

        {items.length > 0 ? (
          items.map((item, i) => {
            const qty = safeParseFloat(item.quantity);
            const rate = safeParseFloat(item.unit_price ?? item.rate ?? 0);
            const amount = qty * rate;
            const name = item.item_name || item.description || 'Item';
            return (
              <div className="thermal-item-row" key={i}>
                <span className="ti-name">{name}</span>
                <span className="ti-qty">{qty}</span>
                <span className="ti-amount">{formatCurrency(amount)}</span>
              </div>
            );
          })
        ) : (
          <div className="thermal-item-row">
            <span className="ti-name" style={{ textAlign: 'center', width: '100%' }}>No items</span>
          </div>
        )}
      </div>

      {/* Totals */}
      <div className="thermal-totals">
        <div className="thermal-divider">{'─'.repeat(32)}</div>
        <div className="thermal-total-row">
          <span className="tt-label">Subtotal</span>
          <span className="tt-value">{formatCurrency(getSubtotal())}</span>
        </div>
        <div className="thermal-total-row thermal-total-grand">
          <span className="tt-label">Total</span>
          <span className="tt-value">{formatCurrency(safeParseFloat(invoice.total_amount || 0))}</span>
        </div>
        {invoice.paid_amount && safeParseFloat(invoice.paid_amount) > 0 && (
          <>
            <div className="thermal-total-row thermal-total-paid">
              <span className="tt-label">Paid</span>
              <span className="tt-value">{formatCurrency(safeParseFloat(invoice.paid_amount))}</span>
            </div>
            {safeParseFloat(invoice.returned_amount) > 0 && (
              <div className="thermal-total-row thermal-total-returned">
                <span className="tt-label">Returned</span>
                <span className="tt-value">{formatCurrency(safeParseFloat(invoice.returned_amount))}</span>
              </div>
            )}
            <div className="thermal-total-row thermal-total-balance">
              <span className="tt-label">Balance Due</span>
              <span className="tt-value">{formatCurrency(safeParseFloat(invoice.balance_amount || 0))}</span>
            </div>
          </>
        )}
      </div>

      {/* QR Code */}
      <div className="thermal-qr-section">
        <div className="thermal-divider">{'─'.repeat(32)}</div>
        {qrSvg ? (
          <div className="thermal-qr-container">
            <div className="thermal-qr-code" dangerouslySetInnerHTML={{ __html: qrSvg }} />
            <div className="thermal-qr-label">{invoice.invoice_no}</div>
          </div>
        ) : (
          <div className="thermal-qr-container">
            <div className="thermal-qr-placeholder">[QR]</div>
            <div className="thermal-qr-label">{invoice.invoice_no}</div>
          </div>
        )}
      </div>

      {/* Footer */}
      <div className="thermal-footer">
        <div className="thermal-divider">{'═'.repeat(32)}</div>
        <div className="thermal-footer-thanks">Thank you for your business!</div>
        <div className="thermal-footer-contact">
          {company?.phone && <div>{company.phone}</div>}
          {company?.email && <div>{company.email}</div>}
        </div>
        <div className="thermal-footer-terms">
          Payment due within {invoice.payment_terms_days || 14} days
        </div>
      </div>
    </div>
  );
}
