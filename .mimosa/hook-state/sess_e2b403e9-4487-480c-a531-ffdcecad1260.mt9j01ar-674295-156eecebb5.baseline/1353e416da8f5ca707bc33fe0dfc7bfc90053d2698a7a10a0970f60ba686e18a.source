import { memo } from 'react';
import { DollarSign, CreditCard, Edit2, Trash2 } from 'lucide-react';

import Button from '../common/Button';
import type { PaymentPanelProps, ExistingPayment } from '../../types';

const fallback = (key: string, fb?: string) => fb || key;

/* ── Existing Payments Table ──────────────────────────────────────── */

const ExistingPaymentsTable = memo(function ExistingPaymentsTable({
  existingPayments,
  deletedPayments,
  onEditPayment,
  onDeletePayment,
  formatCurrency,
}: {
  existingPayments: ExistingPayment[];
  deletedPayments: number[];
  onEditPayment: (payment: ExistingPayment) => void;
  onDeletePayment: (paymentId: number) => void;
  formatCurrency: (amount: number | string | null | undefined) => string;
}) {
  const visiblePayments = existingPayments.filter((p) => !deletedPayments.includes(p.id));
  if (visiblePayments.length === 0) return null;

  return (
    <div className="existing-payments">
      <h4 className="existing-payments-title">
        <CreditCard size={16} />
        Payment History
      </h4>
      <table className="payments-table">
        <thead>
          <tr>
            <th>Date</th>
            <th>Method</th>
            <th className="text-right">Amount</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          {visiblePayments.map((payment) => (
            <tr key={payment.id}>
              <td>{new Date(payment.payment_date).toLocaleDateString()}</td>
              <td>{payment.payment_method}</td>
              <td className="text-right">{formatCurrency(payment.amount)}</td>
              <td>
                <div className="payment-actions" style={{ flexDirection: 'row', gap: '0.25rem', borderTop: 'none', paddingTop: 0, marginTop: 0 }}>
                  <button className="action-btn-small" onClick={() => onEditPayment(payment)} title="Edit">
                    <Edit2 size={12} />
                  </button>
                  <button className="action-btn-small delete" onClick={() => onDeletePayment(payment.id)} title="Delete">
                    <Trash2 size={12} />
                  </button>
                </div>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
});

/* ── Payment Panel (main component) ──────────────────────────────── */

const InvoicePaymentPanel = memo(function InvoicePaymentPanel({
  invoice,
  invoiceId,
  existingPayments,
  deletedPayments,
  showNewPaymentForm,
  paymentMutationPending,
  editingPayment,
  onUpdateInvoice,
  onAddPaymentMethod,
  onRemovePaymentMethod,
  onUpdatePaymentMethod,
  onRecordPayment,
  onSetShowNewPaymentForm,
  onEditPayment,
  onDeletePayment,
  formatCurrency,
  getCurrencySymbol,
  calculateTotal,
  t,
}: PaymentPanelProps) {
  return (
    <div className="payment-section-modern">
      <div className="payment-header">
        <h3 className="payment-title">
          <DollarSign size={20} />
          Payment
        </h3>
        {!invoiceId ? (
          <label className="payment-checkbox">
            <input
              type="checkbox"
              checked={invoice.payment.record_payment}
              onChange={(e) =>
                onUpdateInvoice({
                  payment: { ...invoice.payment, record_payment: e.target.checked },
                })
              }
            />
            <span>{fallback(t('payment.recordNow'), 'Record payment now')}</span>
          </label>
        ) : (
          <div className="payment-summary-header">
            <span className="payment-summary-item">
              {fallback(t('payment.total'), 'Total')}: <strong>{formatCurrency(invoice.total_amount || 0)}</strong>
            </span>
            <span className="payment-summary-item">
              {fallback(t('payment.paid'), 'Paid')}: <strong className="text-green">{formatCurrency(invoice.paid_amount || 0)}</strong>
            </span>
            <span className="payment-summary-item">
              {fallback(t('payment.balance'), 'Balance')}: <strong className={(invoice.balance_amount || 0) > 0 ? 'text-red' : 'text-green'}>
                {formatCurrency(invoice.balance_amount || 0)}
              </strong>
            </span>
          </div>
        )}
      </div>

      {/* Existing Payments */}
      <ExistingPaymentsTable
        existingPayments={existingPayments}
        deletedPayments={deletedPayments}
        onEditPayment={onEditPayment}
        onDeletePayment={onDeletePayment}
        formatCurrency={formatCurrency}
      />

      {/* Payment Form */}
      {(!invoiceId && invoice.payment.record_payment) || invoiceId ? (
        <div className="payment-fields">
          <div className="payment-row">
            <div className="payment-method-field">                    <label>{fallback(t('payment.paymentDate'), 'Payment Date')}</label>
              <input
                type="date"
                value={invoice.payment.payment_date}
                onChange={(e) =>
                  onUpdateInvoice({
                    payment: { ...invoice.payment, payment_date: e.target.value },
                  })
                }
                className="payment-method-select"
              />
            </div>
          </div>

          {/* Multi Payment Methods */}
          <div className="multi-payment-section">
            <div className="multi-payment-header">
              <h4>{fallback(t('payment.paymentMethods'), 'Payment Methods')}</h4>
              <button type="button" className="add-payment-method-btn" onClick={onAddPaymentMethod}>
                + {fallback(t('payment.addMethod'), 'Add Method')}
              </button>
            </div>

            {(invoice.paymentMethods || []).map((method) => (
              <div key={method.id} className="payment-method-row">
                <div className="payment-method-grid">
                  <div className="payment-method-field">
                    <label>{fallback(t('payment.method'), 'Method')}</label>
                    <select
                      value={method.method}
                      onChange={(e) => onUpdatePaymentMethod(method.id, 'method', e.target.value)}
                      className="payment-method-select"
                    >
                      <option value="Cash">Cash</option>
                      <option value="Check">Check</option>
                      <option value="Bank Transfer">Bank Transfer</option>
                      <option value="Credit Card">Credit Card</option>
                      <option value="Online Payment">Online</option>
                    </select>
                  </div>

                  <div className="payment-method-field">
                    <label>{fallback(t('payment.amount'), 'Amount')} (Shift+Enter)</label>
                    <input
                      type="number"
                      step="0.01"
                      value={method.amount}
                      onChange={(e) => onUpdatePaymentMethod(method.id, 'amount', e.target.value)}
                      placeholder="0.00"
                      className="payment-method-amount"
                    />
                  </div>

                  <div className="payment-method-field">
                    <label>{fallback(t('payment.reference'), 'Reference')}</label>
                    <input
                      type="text"
                      value={method.reference_no}
                      onChange={(e) => onUpdatePaymentMethod(method.id, 'reference_no', e.target.value)}
                      placeholder="Check #, TXN ID..."
                      className="payment-method-reference"
                    />
                  </div>

                  {(invoice.paymentMethods || []).length > 1 && (
                    <div className="payment-method-field" style={{ justifyContent: 'flex-end' }}>
                      <button
                        type="button"
                        className="remove-payment-method-btn"
                        onClick={() => onRemovePaymentMethod(method.id)}
                        title="Remove"
                      >
                        ×
                      </button>
                    </div>
                  )}
                </div>
              </div>
            ))}

            {/* Payment Summary */}
            <div className="payment-summary">
              <div className="payment-summary-row">
                <span>{fallback(t('payment.paymentTotal'), 'Payment Total')}:</span>
                <span>
                  {formatCurrency(
                    (invoice.paymentMethods || []).reduce(
                      (sum, m) => sum + (parseFloat(String(m.amount)) || 0),
                      0,
                    ),
                  )}
                </span>
              </div>
              <div className="payment-summary-row">
                <span>{fallback(t('payment.invoiceBalance'), 'Invoice Balance')}:</span>
                <span>{formatCurrency(invoiceId ? invoice.balance_amount || 0 : calculateTotal())}</span>
              </div>
            </div>
          </div>

          {invoiceId && showNewPaymentForm && (
            <div className="payment-actions">
              <Button variant="secondary" onClick={() => onSetShowNewPaymentForm(false)}>
                {fallback(t('common.cancel'), 'Cancel')}
              </Button>
              <Button variant="primary" onClick={onRecordPayment} loading={paymentMutationPending}>
                {fallback(t('payment.savePayment'), 'Save Payment')}
              </Button>
            </div>
          )}
        </div>
      ) : null}
    </div>
  );
});

export default InvoicePaymentPanel;
