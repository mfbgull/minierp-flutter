import { memo } from 'react';
import { Hash, Send } from 'lucide-react';

import Button from '../common/Button';
import FormInput from '../common/FormInput';
import type { InvoiceFormHeaderProps } from '../../types';

const fallback = (key: string, fb?: string) => fb || key;

const InvoiceFormHeader = memo(function InvoiceFormHeader({
  invoice,
  customers,
  customersLoading,
  customersError,
  errors,
  mutationPending,
  invoiceId,
  onCustomerSelect,
  onUpdateInvoice,
  onSubmit,
  onBack,
  formatCurrency,
  t,
}: InvoiceFormHeaderProps) {
  return (
    <div className="invoice-header-modern">
      <div className="header-three-col">
        {/* Left: Invoice Title & Number */}
        <div className="header-col-left">
          <h1 className="invoice-title-modern">{fallback(t('invoice.title'), 'INVOICE')}</h1>
          <div className="invoice-number-modern">
            <Hash className="hash-icon" />
            <span>{invoice.invoice_no}</span>
          </div>
        </div>

        {/* Middle: Customer + Balance */}
        <div className="header-col-center">
          <div className="section-label-modern">{fallback(t('invoice.billTo'), 'BILL TO')}</div>
          <FormInput
            name="customer_name"
            type="searchable-select"
            value={invoice.customer_name}
            onChange={(e) => {
              const customer = Array.isArray(customers)
                ? customers.find((c) => c.customer_name === e.target.value)
                : null;
              if (customer) onCustomerSelect(customer);
            }}
            options={Array.isArray(customers)
              ? customers.map((c) => ({
                  value: c.customer_name,
                  label: `${c.customer_name}${c.customer_code ? ` (${c.customer_code})` : ''}`,
                }))
              : []
            }
            placeholder={customersLoading ? 'Loading...' : customersError ? 'Error' : 'Select customer...'}
            required
            disabled={customersLoading || !!customersError}
          />
          {errors.customer_id && (
            <div className="field-error">{errors.customer_id}</div>
          )}
          {invoice.customer_id && (
            <div className="customer-balance-box">
              <span className="balance-label-text">{fallback(t('invoice.balance'), 'Balance')}</span>
              <span className={`balance-value-text ${(invoice.customer_current_balance || 0) > 0 ? 'balance-positive' : 'balance-zero'}`}>
                {formatCurrency(Math.abs(invoice.customer_current_balance || 0))}
              </span>
            </div>
          )}
        </div>

        {/* Right: Actions */}
        <div className="header-col-right">
          <div className="header-actions">
            <Button variant="secondary" onClick={onBack}>
              {fallback(t('common.cancel'), 'Cancel')}
            </Button>
            <Button variant="primary" onClick={onSubmit} loading={mutationPending}>
              <Send className="action-icon" />
              {invoiceId ? fallback(t('invoice.update'), 'Update') : fallback(t('invoice.create'), 'Create')} {fallback(t('invoice.invoice'), 'Invoice')}
            </Button>
          </div>
        </div>
      </div>
    </div>
  );
});

export default InvoiceFormHeader;
