/**
 * SupplierHeader — page header bar with supplier info, quick stats, and action buttons.
 */

import { memo } from 'react';

import { ArrowLeft, Plus, Package, AlertTriangle } from 'lucide-react';

import Button from '../../components/common/Button';
import type { SupplierHeaderProps } from '../../types';
import { formatAsCurrency } from '../../utils/customerCalculations';

function SupplierHeader({
  supplier,
  currentBalance,
  onBack,
  onRecordPayment,
}: SupplierHeaderProps) {
  return (
    <>
      {/* Page Header */}
      <div className="page-header-wrapper">
        <div className="page-header">
          <div className="supplier-header">
            <div className="supplier-info-left">
              <h1>
                {supplier.supplier_name}
                {supplier.contact_person && (
                  <span className="supplier-code">({supplier.contact_person})</span>
                )}
              </h1>
              {supplier.phone && <div className="phone-number">{supplier.phone}</div>}
            </div>

            <div className="header-actions">
              <Button variant="secondary" onClick={onBack} className="back-button">
                <ArrowLeft size={16} />
                Back to Suppliers
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
          <Package size={18} />
          <div className="quick-stat-content">
            <span className="quick-stat-value">{formatAsCurrency(currentBalance)}</span>
            <span className="quick-stat-label">Balance</span>
          </div>
        </div>
        <div className="quick-stat-divider" />
        <div className={`quick-stat ${currentBalance > 0 ? 'warning' : ''}`}>
          <AlertTriangle size={18} />
          <div className="quick-stat-content">
            <span className="quick-stat-value">{supplier.payment_terms || 'Net 30'}</span>
            <span className="quick-stat-label">Payment Terms</span>
          </div>
        </div>
      </div>
    </>
  );
}

export default memo(SupplierHeader);
