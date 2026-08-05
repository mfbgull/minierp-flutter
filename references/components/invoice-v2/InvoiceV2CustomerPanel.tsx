/**
 * InvoiceV2CustomerPanel — Enhanced customer search with balance preview.
 *
 * Shows a searchable dropdown with the customer's balance, credit limit,
 * and utilization bar. Selecting a customer calls onSelect.
 */

import { useState, useCallback, useRef, useEffect, memo } from 'react';
import { Search, ChevronDown } from 'lucide-react';
import type { InvoiceV2Customer, InvoiceV2CustomerPanelProps } from '../../types/invoiceV2';

const InvoiceV2CustomerPanel = memo(function InvoiceV2CustomerPanel({
  customer,
  customers,
  loading,
  onSelect,
  formatCurrency,
}: InvoiceV2CustomerPanelProps) {
  const [query, setQuery] = useState('');
  const [isOpen, setIsOpen] = useState(false);
  const [highlightIdx, setHighlightIdx] = useState(-1);
  const wrapperRef = useRef<HTMLDivElement>(null);

  const filtered = customers
    .filter((c) => {
      if (!query.trim()) return true;
      const q = query.toLowerCase();
      return (
        c.customer_name.toLowerCase().includes(q) ||
        (c.customer_code || '').toLowerCase().includes(q) ||
        (c.email || '').toLowerCase().includes(q)
      );
    })
    .slice(0, 15);

  const close = useCallback(() => {
    setIsOpen(false);
    setHighlightIdx(-1);
  }, []);

  const handleSelect = useCallback(
    (c: (typeof customers)[number]) => {
      onSelect({
        id: c.id,
        name: c.customer_name,
        code: c.customer_code,
        email: c.email || '',
        phone: c.phone || '',
        address: c.billing_address || '',
        balance: 0,
        creditLimit: Number(c.credit_limit) || 0,
        creditUtilization: 0,
      });
      setQuery('');
      close();
    },
    [onSelect, close],
  );

  // Click outside
  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (wrapperRef.current && !wrapperRef.current.contains(e.target as Node)) {
        close();
      }
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, [close]);

  if (customer) {
    return (
      <div className="iv2-customer-section">
        <div className="iv2-customer-field" style={{ flex: 1 }}>
          <div style={{ fontSize: '0.6875rem', color: 'var(--iv2-text-tertiary)', textTransform: 'uppercase', marginBottom: '0.125rem' }}>
            Customer
          </div>
          <div
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: '0.5rem',
              padding: '0.375rem 0.5rem',
              border: '1px solid var(--iv2-border)',
              borderRadius: '3px',
              cursor: 'pointer',
              fontSize: '0.8125rem',
              transition: 'background 0.15s',
            }}
            onMouseEnter={(e) => { e.currentTarget.style.background = 'var(--iv2-bg-muted)'; }}
            onMouseLeave={(e) => { e.currentTarget.style.background = ''; }}
            title="Click to change customer"
            onClick={() => {
              setQuery('');
              setIsOpen(true);
            }}
          >
            <span style={{ fontWeight: 600 }}>{customer.name}</span>
            {customer.code && (
              <span style={{ color: 'var(--iv2-text-tertiary)', fontSize: '0.75rem' }}>
                ({customer.code})
              </span>
            )}
          </div>
        </div>

        {/* Balance summary */}
        <div className="iv2-customer-balance">
          <span>Balance: </span>
          <span className={customer.balance > 0 ? 'positive' : 'zero'}>
            {formatCurrency(customer.balance)}
          </span>
          {customer.creditLimit > 0 && (
            <>
              <span style={{ margin: '0 0.5rem' }}>·</span>
              <span>Limit: {formatCurrency(customer.creditLimit)}</span>
              <span style={{ margin: '0 0.5rem' }}>·</span>
              <span
                style={{
                  color:
                    customer.creditUtilization > 80
                      ? 'var(--iv2-error)'
                      : 'var(--iv2-success)',
                }}
              >
                {customer.creditUtilization.toFixed(0)}% used
              </span>
            </>
          )}
        </div>
      </div>
    );
  }

  return (
    <div className="iv2-customer-section">
      <div className="iv2-customer-field" ref={wrapperRef} style={{ position: 'relative' }}>
        <div style={{ fontSize: '0.6875rem', color: 'var(--iv2-text-tertiary)', textTransform: 'uppercase', marginBottom: '0.125rem' }}>
          Customer
        </div>
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            border: '1px solid var(--iv2-border)',
            borderRadius: '3px',
            padding: '0 0.5rem',
          }}
        >
          <Search size={14} style={{ color: 'var(--iv2-text-tertiary)', flexShrink: 0 }} />
          <input
            type="text"
            className="iv2-editable-input"
            style={{ border: 'none', boxShadow: 'none', padding: '0.375rem 0.5rem' }}
            placeholder={loading ? 'Loading customers...' : 'Search customer...'}
            value={query}
            disabled={loading}
            onChange={(e) => {
              setQuery(e.target.value);
              setIsOpen(true);
              setHighlightIdx(0);
            }}
            onFocus={() => {
              setIsOpen(true);
              setHighlightIdx(0);
            }}
            onKeyDown={(e) => {
              if (e.key === 'ArrowDown') {
                e.preventDefault();
                setHighlightIdx((p) => (p < filtered.length - 1 ? p + 1 : 0));
              } else if (e.key === 'ArrowUp') {
                e.preventDefault();
                setHighlightIdx((p) => (p > 0 ? p - 1 : filtered.length - 1));
              } else if (e.key === 'Enter' && highlightIdx >= 0 && filtered[highlightIdx]) {
                e.preventDefault();
                handleSelect(filtered[highlightIdx]);
              } else if (e.key === 'Escape') {
                close();
              }
            }}
          />
          <ChevronDown size={14} style={{ color: 'var(--iv2-text-tertiary)', flexShrink: 0 }} />
        </div>

        {isOpen && filtered.length > 0 && (
          <div
            style={{
              position: 'absolute',
              top: '100%',
              left: 0,
              right: 0,
              zIndex: 100,
              background: 'var(--iv2-bg)',
              border: '1px solid var(--iv2-border)',
              borderRadius: '3px',
              boxShadow: '0 4px 12px rgba(0,0,0,0.1)',
              maxHeight: '280px',
              overflow: 'auto',
              marginTop: '2px',
            }}
          >
            {filtered.map((c, idx) => (
              <div
                key={c.id}
                className={`item-dropdown-option ${idx === highlightIdx ? 'selected' : ''}`}
                onMouseDown={(e) => {
                  e.preventDefault();
                  handleSelect(c);
                }}
                onMouseEnter={() => setHighlightIdx(idx)}
                style={{ padding: '0.5rem 0.625rem' }}
              >
                <div className="item-dropdown-main">
                  <span className="item-dropdown-name">{c.customer_name}</span>
                  {c.customer_code && (
                    <span className="item-dropdown-code">{c.customer_code}</span>
                  )}
                </div>
                <div className="item-dropdown-details">
                  <span>{c.email || c.phone || ''}</span>
                  {c.credit_limit ? (
                    <span>Limit: {formatCurrency(c.credit_limit)}</span>
                  ) : null}
                </div>
              </div>
            ))}
          </div>
        )}

        {isOpen && query.trim() && filtered.length === 0 && (
          <div
            style={{
              position: 'absolute',
              top: '100%',
              left: 0,
              right: 0,
              zIndex: 100,
              background: 'var(--iv2-bg)',
              border: '1px solid var(--iv2-border)',
              borderRadius: '3px',
              padding: '0.75rem',
              fontSize: '0.8125rem',
              color: 'var(--iv2-text-secondary)',
              textAlign: 'center',
            }}
          >
            No customers found
          </div>
        )}
      </div>
    </div>
  );
});

export default InvoiceV2CustomerPanel;
