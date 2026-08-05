/**
 * CustomerHeader — page header bar with customer info, quick stats, and action buttons.
 * Extracted from CustomerDetailPage to separate presentation from data fetching.
 */

import { memo } from 'react';

import { ArrowLeft, Plus, DollarSign, CreditCard, TrendingUp, AlertTriangle } from 'lucide-react';

import Button from '../../components/common/Button';
import { formatAsCurrency, formatAsFixed } from '../../utils/customerCalculations';
import type { CustomerHeaderProps } from '../../types';

function CustomerHeader({
  customer,
  currentBalance,
  creditLimit,
  creditUtilization,
  overdueInvoicesCount,
  onBack,
  onRecordPayment,
}: CustomerHeaderProps) {
  const utilizationClass =
    creditUtilization > 90 ? 'danger' : creditUtilization > 75 ? 'warning' : '';

  return (
    <>
      {/* Page Header */}
      <div className="page-header-wrapper">
        <div className="page-header">
          <div className="customer-header">
            <div className="customer-info-left">
              <h1>
                {customer.customer_name}
                {customer.contact_person && (
                  <span className="customer-code">({customer.contact_person})</span>
                )}
              </h1>
              {customer.phone && <div className="phone-number">{customer.phone}</div>}
            </div>

            <div className="header-actions">
              <Button variant="secondary" onClick={onBack} className="back-button">
                <ArrowLeft size={16} />
                Back to Customers
              </Button>
              <Button variant="primary" onClick={onRecordPayment}>
                <Plus size={16} />
                Record Payment
              </Button>
            </div>
          </div>
        </div>
      </div>

      {/* Quick Stats Bar */}
      <div className="quick-stats-bar">
        <div className="quick-stat">
          <DollarSign size={18} />
          <div className="quick-stat-content">
            <span className="quick-stat-value">{formatAsCurrency(currentBalance)}</span>
            <span className="quick-stat-label">Balance</span>
          </div>
        </div>
        <div className="quick-stat-divider" />
        <div className="quick-stat">
          <CreditCard size={18} />
          <div className="quick-stat-content">
            <span className="quick-stat-value">{formatAsCurrency(creditLimit)}</span>
            <span className="quick-stat-label">Credit Limit</span>
          </div>
        </div>
        <div className="quick-stat-divider" />
        <div className={`quick-stat ${utilizationClass}`}>
          <TrendingUp size={18} />
          <div className="quick-stat-content">
            <span className="quick-stat-value">{formatAsFixed(creditUtilization)}%</span>
            <span className="quick-stat-label">Utilization</span>
          </div>
        </div>
        <div className="quick-stat-divider" />
        <div className={`quick-stat ${overdueInvoicesCount > 0 ? 'danger' : ''}`}>
          <AlertTriangle size={18} />
          <div className="quick-stat-content">
            <span className="quick-stat-value">{overdueInvoicesCount}</span>
            <span className="quick-stat-label">Overdue</span>
          </div>
        </div>
      </div>
    </>
  );
}

export default memo(CustomerHeader);
