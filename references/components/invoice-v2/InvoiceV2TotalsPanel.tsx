/**
 * InvoiceV2TotalsPanel — Totals breakdown panel + collapsible discount & notes/terms.
 *
 * Left side: collapsible Notes & Terms textareas
 * Right side: totals panel (subtotal, invoice-level discount input, tax, total)
 */

import { memo, useState, useCallback } from 'react';
import { ChevronDown } from 'lucide-react';
import type { InvoiceV2TotalsPanelProps } from '../../types/invoiceV2';

const InvoiceV2TotalsPanel = memo(function InvoiceV2TotalsPanel({
  items,
  discountScope,
  discount,
  notes,
  terms,
  onUpdateDiscount,
  onUpdateNotes,
  onUpdateTerms,
  formatCurrency,
  getCurrencySymbol,
  calculateSubtotal,
  calculateTax,
  calculateDiscount,
  calculateTotal,
}: InvoiceV2TotalsPanelProps) {
  const [showDiscount, setShowDiscount] = useState(false);
  const [showNotesTerms, setShowNotesTerms] = useState(false);

  const handleDiscTypeChange = useCallback(
    (type: 'flat' | 'percentage') => {
      onUpdateDiscount({ ...discount, type });
    },
    [discount, onUpdateDiscount],
  );

  const handleDiscValueChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      onUpdateDiscount({ ...discount, value: Number(e.target.value) || 0 });
    },
    [discount, onUpdateDiscount],
  );

  // In per-item mode, discount is calculated from items — no inline input needed
  const isItemMode = discountScope === 'item';

  return (
    <div className="iv2-totals-section">
      {/* Left: Notes & Terms (collapsible) */}
      <div style={{ flex: 1, minWidth: 0 }}>
        <div className="iv2-collapsible">
          <div
            className="iv2-collapsible-header"
            onClick={() => setShowNotesTerms(!showNotesTerms)}
            tabIndex={0}
            onKeyDown={(e) => {
              if (e.key === 'Enter' || e.key === ' ') {
                e.preventDefault();
                setShowNotesTerms(!showNotesTerms);
              }
            }}
          >
            <span>Notes &amp; Terms</span>
            <ChevronDown
              size={14}
              className={`chevron${showNotesTerms ? ' open' : ''}`}
            />
          </div>
          {showNotesTerms && (
            <div className="iv2-collapsible-body">
              <div className="iv2-notes-row">
                <div className="iv2-notes-field">
                  <label>Notes</label>
                  <textarea
                    value={notes}
                    onChange={(e) => onUpdateNotes(e.target.value)}
                    placeholder="Thank you for your business..."
                  />
                </div>
                <div className="iv2-notes-field">
                  <label>Terms &amp; Conditions</label>
                  <textarea
                    value={terms}
                    onChange={(e) => onUpdateTerms(e.target.value)}
                    placeholder="Net 14 days..."
                  />
                </div>
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Right: Totals panel */}
      <div className="iv2-totals-panel">
        {/* Discount section (collapsible, but only relevant in invoice mode) */}
        <div style={{ marginBottom: '0.5rem' }}>
          <div
            style={{
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              cursor: 'pointer',
              fontSize: '0.75rem',
              fontWeight: 500,
              color: 'var(--iv2-text-secondary)',
              textTransform: 'uppercase',
              letterSpacing: '0.03em',
            }}
            onClick={() => {
              if (!isItemMode) setShowDiscount(!showDiscount);
            }}
            tabIndex={0}
            onKeyDown={(e) => {
              if ((e.key === 'Enter' || e.key === ' ') && !isItemMode) {
                e.preventDefault();
                setShowDiscount(!showDiscount);
              }
            }}
          >
            <span>Discount ({isItemMode ? 'per item' : discount.type === 'percentage' ? '%' : getCurrencySymbol()})</span>
            <ChevronDown
              size={12}
              className={`chevron${showDiscount ? ' open' : ''}`}
              style={{ opacity: isItemMode ? 0.4 : 1 }}
            />
          </div>
          {showDiscount && !isItemMode && (
            <div className="iv2-discount-controls" style={{ marginTop: '0.375rem' }}>
              <select
                value={discount.type}
                onChange={(e) => handleDiscTypeChange(e.target.value as 'flat' | 'percentage')}
              >
                <option value="percentage">%</option>
                <option value="flat">{getCurrencySymbol()}</option>
              </select>
              <input
                type="number"
                value={discount.value || ''}
                onChange={handleDiscValueChange}
                placeholder="0"
                min="0"
                step="any"
              />
            </div>
          )}
        </div>

        {/* Totals */}
        <div className="iv2-total-row">
          <span>Subtotal</span>
          <span className="value">{formatCurrency(calculateSubtotal())}</span>
        </div>

        <div className="iv2-total-row discount">
          <span>Discount {isItemMode ? '(per item)' : ''}</span>
          <span className="value">
            -{formatCurrency(calculateDiscount())}
          </span>
        </div>

        <div className="iv2-total-row border-top">
          <span>Tax</span>
          <span className="value">{formatCurrency(calculateTax())}</span>
        </div>

        <div className="iv2-total-row final">
          <span>Total</span>
          <span className="value">{formatCurrency(calculateTotal())}</span>
        </div>
      </div>
    </div>
  );
});

export default InvoiceV2TotalsPanel;
