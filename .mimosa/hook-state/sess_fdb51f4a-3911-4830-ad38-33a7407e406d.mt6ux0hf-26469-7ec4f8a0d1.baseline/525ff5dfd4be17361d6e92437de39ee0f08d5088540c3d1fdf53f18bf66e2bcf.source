/**
 * OverviewTab — financial summary, invoice status breakdown, collapsible sections
 * for contact info, account settings, recent invoices, and recent payments.
 *
 * Extracted from the monolithic CustomerDetailPage to separate presentation concerns.
 */

import { useState, useMemo, memo } from 'react';

import {
  DollarSign,
  FileText,
  CreditCard,
  Clock,
  Calendar,
  Receipt,
} from 'lucide-react';

import SummaryCard, { SummaryGrid } from '../../components/common/SummaryCard';
import {
  calculateTotalInvoiced,
  calculateTotalPaid,
  calculateTotalOutstanding,
  calculateAverageDaysToPay,
  countPaidInvoices,
  countUnpaidInvoices,
  calculateOverdueInvoices,
  getRecentInvoices,
  getRecentPayments,
  formatAsCurrency,
  formatDateString,
} from '../../utils/customerCalculations';
import type { OverviewTabProps } from '../../types';
import { getInvoiceStatusBadgeClass } from '../../utils/invoiceRules';

type SectionKey = 'contactInfo' | 'accountSettings' | 'recentInvoices' | 'recentPayments';

function OverviewTab({ customer, invoices, payments }: OverviewTabProps) {
  const [expandedSections, setExpandedSections] = useState<Record<SectionKey, boolean>>({
    contactInfo: true,
    accountSettings: true,
    recentInvoices: true,
    recentPayments: true,
  });

  const toggleSection = (section: SectionKey) => {
    setExpandedSections((prev) => ({ ...prev, [section]: !prev[section] }));
  };

  // Memoized calculations
  const totals = useMemo(
    () => ({
      invoiced: calculateTotalInvoiced(invoices),
      paid: calculateTotalPaid(invoices),
      outstanding: calculateTotalOutstanding(invoices),
    }),
    [invoices],
  );

  const invoiceCounts = useMemo(
    () => ({
      paid: countPaidInvoices(invoices),
      unpaid: countUnpaidInvoices(invoices),
      overdue: calculateOverdueInvoices(invoices).length,
      total: invoices.length,
    }),
    [invoices],
  );

  const avgDaysToPay = useMemo(() => calculateAverageDaysToPay(invoices), [invoices]);

  const recentInvoices = useMemo(() => getRecentInvoices(invoices, 5), [invoices]);
  const recentPayments = useMemo(() => getRecentPayments(payments, 5), [payments]);

  const paidPercent = invoiceCounts.total > 0 ? (invoiceCounts.paid / invoiceCounts.total) * 100 : 0;
  const unpaidPercent = invoiceCounts.total > 0 ? (invoiceCounts.unpaid / invoiceCounts.total) * 100 : 0;
  const overduePercent = invoiceCounts.total > 0 ? (invoiceCounts.overdue / invoiceCounts.total) * 100 : 0;

  return (
    <div className="overview-tab">
      {/* Financial Summary */}
      <div className="overview-financial-summary">
        <h3 className="section-title">
          <DollarSign size={18} />
          Financial Summary
        </h3>
        <SummaryGrid columns={4}>
          <SummaryCard
            icon={FileText}
            label="Total Invoiced"
            value={formatAsCurrency(totals.invoiced)}
            variant="info"
          />
          <SummaryCard
            icon={CreditCard}
            label="Total Received"
            value={formatAsCurrency(totals.paid)}
            variant="success"
          />
          <SummaryCard
            icon={Clock}
            label="Outstanding Balance"
            value={formatAsCurrency(totals.outstanding)}
            variant="warning"
          />
          <SummaryCard icon={Calendar} label="Avg. Days to Pay" value={avgDaysToPay} />
        </SummaryGrid>
      </div>

      {/* Invoice Status */}
      <div className="overview-invoice-status">
        <h3 className="section-title">
          <Receipt size={18} />
          Invoice Status
        </h3>
        <div className="invoice-status-grid">
          <div className="status-card paid">
            <div className="status-count">{invoiceCounts.paid}</div>
            <div className="status-label">Paid</div>
            <div className="status-bar">
              <div className="status-bar-fill" style={{ width: `${paidPercent}%` }} />
            </div>
          </div>
          <div className="status-card pending">
            <div className="status-count">{invoiceCounts.unpaid}</div>
            <div className="status-label">Pending</div>
            <div className="status-bar">
              <div className="status-bar-fill" style={{ width: `${unpaidPercent}%` }} />
            </div>
          </div>
          <div className="status-card overdue">
            <div className="status-count">{invoiceCounts.overdue}</div>
            <div className="status-label">Overdue</div>
            <div className="status-bar">
              <div className="status-bar-fill" style={{ width: `${overduePercent}%` }} />
            </div>
          </div>
          <div className="status-card total">
            <div className="status-count">{invoiceCounts.total}</div>
            <div className="status-label">Total Invoices</div>
            <div className="status-bar">
              <div className="status-bar-fill" style={{ width: '100%' }} />
            </div>
          </div>
        </div>
      </div>

      {/* Collapsible: Contact Information */}
      <CollapsibleSection
        title="Contact Information"
        icon={<FileText size={18} />}
        isExpanded={expandedSections.contactInfo}
        onToggle={() => toggleSection('contactInfo')}
      >
        <div className="info-grid">
          <InfoItem
            icon={
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7A2 2 0 0 1 22 16.92z" />
              </svg>
            }
            label="Phone"
            value={customer.phone || 'Not provided'}
          />
          <InfoItem
            icon={
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M4 4h16c1.1 0 2 .9 2 2v12c0 1.1-.9 2-2 2H4c-1.1 0-2-.9-2-2V6c0-1.1.9-2 2-2z" />
                <polyline points="22,6 12,13 2,6" />
              </svg>
            }
            label="Email"
            value={customer.email || 'Not provided'}
          />
          <InfoItem
            fullWidth
            icon={
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z" />
                <circle cx="12" cy="10" r="3" />
              </svg>
            }
            label="Billing Address"
            value={customer.billing_address || 'Not provided'}
          />
          <InfoItem
            fullWidth
            icon={
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <rect x="1" y="3" width="15" height="13" />
                <polygon points="16 8 20 8 23 11 23 16 16 16 16 8" />
                <circle cx="5.5" cy="18.5" r="2.5" />
                <circle cx="18.5" cy="18.5" r="2.5" />
              </svg>
            }
            label="Shipping Address"
            value={customer.shipping_address || 'Same as billing'}
          />
        </div>
      </CollapsibleSection>

      {/* Collapsible: Account Settings */}
      <CollapsibleSection
        title="Account Settings"
        icon={null}
        isExpanded={expandedSections.accountSettings}
        onToggle={() => toggleSection('accountSettings')}
        simpleTitle
      >
        <div className="account-settings">
          <SettingItem label="Payment Terms" value={`${customer.payment_terms_days || 14} days`} />
          <SettingItem label="Credit Limit" value={formatAsCurrency(customer.credit_limit || 0)} />
          <SettingItem label="Opening Balance" value={formatAsCurrency(customer.opening_balance || 0)} />
          <SettingItem
            label="Customer Since"
            value={customer.created_at ? formatDateString(customer.created_at) : 'N/A'}
          />
        </div>
      </CollapsibleSection>

      {/* Collapsible: Recent Invoices */}
      <CollapsibleSection
        title="Latest Invoices"
        icon={null}
        isExpanded={expandedSections.recentInvoices}
        onToggle={() => toggleSection('recentInvoices')}
        simpleTitle
      >
        {recentInvoices.length > 0 ? (
          <div className="activity-table">
            <div className="activity-table-header">
              <span>Invoice</span>
              <span>Date</span>
              <span>Amount</span>
              <span>Status</span>
            </div>
            {recentInvoices.map((invoice) => (
              <div key={invoice.id} className="activity-table-row">
                <span className="invoice-no">{invoice.invoice_no}</span>
                <span className="invoice-date">{formatDateString(invoice.invoice_date)}</span>
                <span className="invoice-amount">{formatAsCurrency(invoice.total_amount)}</span>
                <span className={getInvoiceStatusBadgeClass(invoice.status)}>
                  {invoice.status || 'Unknown'}
                </span>
              </div>
            ))}
          </div>
        ) : (
          <EmptyState icon={<FileText size={24} />} message="No invoices yet" />
        )}
      </CollapsibleSection>

      {/* Collapsible: Recent Payments */}
      <CollapsibleSection
        title="Latest Payments"
        icon={null}
        isExpanded={expandedSections.recentPayments}
        onToggle={() => toggleSection('recentPayments')}
        simpleTitle
      >
        {recentPayments.length > 0 ? (
          <div className="activity-table">
            <div className="activity-table-header">
              <span>Payment</span>
              <span>Date</span>
              <span>Amount</span>
              <span>Method</span>
            </div>
            {recentPayments.map((payment) => (
              <div key={payment.id} className="activity-table-row">
                <span className="payment-no">{payment.payment_no}</span>
                <span className="payment-date">{formatDateString(payment.payment_date)}</span>
                <span className="payment-amount success">{formatAsCurrency(payment.amount)}</span>
                <span className="payment-method">{payment.payment_method || 'Cash'}</span>
              </div>
            ))}
          </div>
        ) : (
          <EmptyState icon={<CreditCard size={24} />} message="No payments yet" />
        )}
      </CollapsibleSection>
    </div>
  );
}

/* ── Sub-components ─────────────────────────────────────────────── */

interface CollapsibleSectionProps {
  title: string;
  icon: React.ReactNode | null;
  isExpanded: boolean;
  onToggle: () => void;
  children: React.ReactNode;
  simpleTitle?: boolean;
}

function CollapsibleSection({
  title,
  icon,
  isExpanded,
  onToggle,
  children,
  simpleTitle,
}: CollapsibleSectionProps) {
  return (
    <div className="overview-card collapsible-section">
      <div className="section-header" onClick={onToggle}>
        {simpleTitle ? (
          <h4 className="subsection-title">{title}</h4>
        ) : (
          <h3 className="section-title">
            {icon}
            {title}
          </h3>
        )}
        <span className="expand-icon">{isExpanded ? '\u2212' : '+'}</span>
      </div>
      {isExpanded && <div className="section-content">{children}</div>}
    </div>
  );
}

interface InfoItemProps {
  icon: React.ReactNode;
  label: string;
  value: string;
  fullWidth?: boolean;
}

function InfoItem({ icon, label, value, fullWidth }: InfoItemProps) {
  return (
    <div className={`info-item${fullWidth ? ' full-width' : ''}`}>
      <span className="info-icon">{icon}</span>
      <div className="info-text">
        <span className="info-label">{label}</span>
        <span className="info-value">{value}</span>
      </div>
    </div>
  );
}

interface SettingItemProps {
  label: string;
  value: string;
}

function SettingItem({ label, value }: SettingItemProps) {
  return (
    <div className="setting-item">
      <span className="setting-label">{label}</span>
      <span className="setting-value">{value}</span>
    </div>
  );
}

interface EmptyStateProps {
  icon: React.ReactNode;
  message: string;
}

function EmptyState({ icon, message }: EmptyStateProps) {
  return (
    <div className="empty-state">
      {icon}
      <p>{message}</p>
    </div>
  );
}

export default memo(OverviewTab);
