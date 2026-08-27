/**
 * OverviewTab — supplier financial summary, PO status breakdown, collapsible sections
 * for contact info, and recent POs and payments.
 */

import { useState, useMemo, memo } from 'react';

import {
  Package,
  FileText,
  Clock,
  Calendar,
  DollarSign,
} from 'lucide-react';

import SummaryCard, { SummaryGrid } from '../../components/common/SummaryCard';
import type { SupplierOverviewTabProps } from '../../types';
import { formatAsCurrency, formatDateString } from '../../utils/customerCalculations';

type SectionKey = 'contactInfo' | 'accountSettings' | 'recentPOs' | 'recentPayments';

function OverviewTab({ supplier, poSummary, balanceData }: SupplierOverviewTabProps) {
  const [expandedSections, setExpandedSections] = useState<Record<SectionKey, boolean>>({
    contactInfo: true,
    accountSettings: true,
    recentPOs: true,
    recentPayments: true,
  });

  const toggleSection = (section: SectionKey) => {
    setExpandedSections((prev) => ({ ...prev, [section]: !prev[section] }));
  };

  const currentBalance = useMemo(() => balanceData?.currentBalance || 0, [balanceData]);

  const poCounts = useMemo(
    () => ({
      total: poSummary?.total_pos || 0,
      draft: poSummary?.draft_pos || 0,
      submitted: poSummary?.submitted_pos || 0,
      partial: poSummary?.partially_received_pos || 0,
      completed: poSummary?.completed_pos || 0,
    }),
    [poSummary],
  );

  return (
    <div className="overview-tab">
      {/* Financial Summary */}
      <div className="overview-financial-summary">
        <h3 className="section-title">
          <DollarSign size={18} />
          Financial Summary
        </h3>
        <SummaryGrid columns={3}>
          <SummaryCard
            icon={Package}
            label="Current Balance"
            value={formatAsCurrency(currentBalance)}
            variant={currentBalance > 0 ? 'warning' : 'default'}
          />
          <SummaryCard
            icon={FileText}
            label="Total PO Value"
            value={formatAsCurrency(poSummary?.total_value || 0)}
            variant="info"
          />
          <SummaryCard
            icon={Calendar}
            label="Total POs"
            value={poSummary?.total_pos || 0}
          />
        </SummaryGrid>
      </div>

      {/* PO Status */}
      <div className="overview-invoice-status">
        <h3 className="section-title">
          <Clock size={18} />
          Purchase Order Status
        </h3>
        <div className="invoice-status-grid">
          <div className="status-card draft">
            <div className="status-count">{poCounts.draft}</div>
            <div className="status-label">Draft</div>
          </div>
          <div className="status-card pending">
            <div className="status-count">{poCounts.submitted}</div>
            <div className="status-label">Submitted</div>
          </div>
          <div className="status-card partial">
            <div className="status-count">{poCounts.partial}</div>
            <div className="status-label">Partial</div>
          </div>
          <div className="status-card completed">
            <div className="status-count">{poCounts.completed}</div>
            <div className="status-label">Completed</div>
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
            value={supplier.phone || 'Not provided'}
          />
          <InfoItem
            icon={
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M4 4h16c1.1 0 2 .9 2 2v12c0 1.1-.9 2-2 2H4c-1.1 0-2-.9-2-2V6c0-1.1.9-2 2-2z" />
                <polyline points="22,6 12,13 2,6" />
              </svg>
            }
            label="Email"
            value={supplier.email || 'Not provided'}
          />
          <InfoItem
            fullWidth
            icon={
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z" />
                <circle cx="12" cy="10" r="3" />
              </svg>
            }
            label="Address"
            value={supplier.address || 'Not provided'}
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
          <SettingItem label="Payment Terms" value={supplier.payment_terms || 'Net 30'} />
          <SettingItem label="Current Balance" value={formatAsCurrency(currentBalance)} />
          <SettingItem
            label="Supplier Since"
            value={supplier.created_at ? formatDateString(supplier.created_at) : 'N/A'}
          />
        </div>
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

export default memo(OverviewTab);
