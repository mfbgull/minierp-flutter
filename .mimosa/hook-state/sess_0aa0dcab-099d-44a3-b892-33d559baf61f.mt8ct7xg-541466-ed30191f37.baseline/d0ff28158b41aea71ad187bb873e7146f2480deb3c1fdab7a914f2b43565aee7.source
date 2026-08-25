/**
 * InvoiceV2PaymentSection — Payment recording with method shortcuts.
 *
 * Features:
 * - Record payment checkbox (always visible, never collapses)
 * - Multiple payment methods with type/amount/reference
 * - Keyboard shortcuts: C=Cash, T=Bank Transfer, K=Check, O=Online, R=Card
 * - Total auto-aggregation from payment amounts
 */

import { memo, useCallback, useRef } from 'react';
import { Plus, X } from 'lucide-react';
import type { InvoiceV2PaymentSectionProps } from '../../types/invoiceV2';

const SHORTCUTS = [
  { key: 'C', label: 'Cash', method: 'Cash' },
  { key: 'T', label: 'Transfer', method: 'Bank Transfer' },
  { key: 'K', label: 'Check', method: 'Check' },
  { key: 'O', label: 'Online', method: 'Online Payment' },
  { key: 'R', label: 'Card', method: 'Credit Card' },
] as const;

const METHOD_OPTIONS = ['Cash', 'Bank Transfer', 'Check', 'Credit Card', 'Online Payment'];

const InvoiceV2PaymentSection = memo(function InvoiceV2PaymentSection({
  payment,
  totalAmount,
  onUpdatePayment,
  onAddPaymentMethod,
  onRemovePaymentMethod,
  onUpdatePaymentMethod,
  formatCurrency,
}: InvoiceV2PaymentSectionProps) {
  const sectionRef = useRef<HTMLDivElement>(null);

  const handleShortcut = useCallback(
    (method: string) => {
      // Set the first payment method to the chosen type
      if (payment.paymentMethods.length > 0) {
        const first = payment.paymentMethods[0];
        if (!payment.recordPayment) {
          onUpdatePayment({ recordPayment: true });
        }
        onUpdatePaymentMethod(first.id, 'method', method);
        // Focus the amount field of the first method row
        const input = sectionRef.current?.querySelector<HTMLInputElement>(
          `.iv2-payment-field.amount input`
        );
        input?.focus();
        input?.select();
      }
    },
    [payment.paymentMethods, payment.recordPayment, onUpdatePayment, onUpdatePaymentMethod],
  );

  // Keyboard handler for payment section — letter shortcuts
  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      const key = e.key.toUpperCase();
      const shortcut = SHORTCUTS.find((s) => s.key === key);
      if (shortcut) {
        // Only fire if no input is focused (or if focused input is within payment section)
        // This prevents conflicts with the items grid
        const active = document.activeElement;
        const inGrid = active?.closest('.iv2-grid-wrapper');
        const inPayment = active?.closest('.iv2-payment-section');
        if (!inGrid || inPayment) {
          e.preventDefault();
          e.stopPropagation();
          handleShortcut(shortcut.method);
        }
      }
    },
    [handleShortcut],
  );

  const paymentTotal = payment.paymentMethods.reduce(
    (sum, m) => sum + (parseFloat(String(m.amount)) || 0),
    0,
  );

  return (
    <div
      className="iv2-payment-section"
      ref={sectionRef}
      data-payment-section
      onKeyDown={handleKeyDown}
    >
      {/* Header */}
      <div className="iv2-payment-header">
        <label className="iv2-payment-checkbox">
          <input
            type="checkbox"
            checked={payment.recordPayment}
            onChange={(e) => onUpdatePayment({ recordPayment: e.target.checked })}
          />
          <span>Record payment — {formatCurrency(paymentTotal || totalAmount)}</span>
        </label>
      </div>

      {/* Payment methods */}
      {payment.recordPayment &&
        payment.paymentMethods.map((pm) => (
          <div className="iv2-payment-row" key={pm.id}>
            <div className="iv2-payment-field method">
              <label>Method</label>
              <select
                value={pm.method}
                onChange={(e) => onUpdatePaymentMethod(pm.id, 'method', e.target.value)}
              >
                {METHOD_OPTIONS.map((m) => (
                  <option key={m} value={m}>
                    {m}
                  </option>
                ))}
              </select>
            </div>
            <div className="iv2-payment-field amount">
              <label>Amount</label>
              <input
                type="number"
                value={pm.amount || ''}
                onChange={(e) => onUpdatePaymentMethod(pm.id, 'amount', e.target.value)}
                placeholder={String(totalAmount)}
                min="0"
                step="any"
              />
            </div>
            <div className="iv2-payment-field ref">
              <label>Reference</label>
              <input
                type="text"
                value={pm.reference_no || ''}
                onChange={(e) => onUpdatePaymentMethod(pm.id, 'reference_no', e.target.value)}
                placeholder="Ref #"
              />
            </div>
            {payment.paymentMethods.length > 1 && (
              <button
                className="iv2-btn"
                onClick={() => onRemovePaymentMethod(pm.id)}
                style={{
                  padding: '0.25rem 0.375rem',
                  border: 'none',
                  background: 'none',
                  color: 'var(--iv2-text-tertiary)',
                  cursor: 'pointer',
                  alignSelf: 'flex-end',
                  marginBottom: '1px',
                }}
                type="button"
                title="Remove payment method"
              >
                <X size={14} />
              </button>
            )}
          </div>
        ))}

      {/* Shortcut badges */}
      {payment.recordPayment && (
        <div className="iv2-payment-shortcuts">
          {SHORTCUTS.map((s) => (
            <button
              key={s.key}
              className="iv2-shortcut-badge"
              onClick={() => handleShortcut(s.method)}
              type="button"
            >
              <span className="key">{s.key}</span>
              <span>{s.label}</span>
            </button>
          ))}
        </div>
      )}

      {/* Add method + total */}
      {payment.recordPayment && (
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <button className="iv2-add-method-btn" onClick={onAddPaymentMethod} type="button">
            <Plus size={12} />
            Add Method
          </button>
          <div className="iv2-payment-total">
            <span>Payment Total</span>
            <span style={{ color: 'var(--iv2-primary)' }}>
              {formatCurrency(paymentTotal)}
            </span>
          </div>
        </div>
      )}
    </div>
  );
});

export default InvoiceV2PaymentSection;
