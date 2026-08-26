import React from 'react';

import { X, Eye, Edit2, Trash2, Package } from 'lucide-react';

import SummaryCard, { SummaryGrid } from '../../components/common/SummaryCard';
import type { Supplier } from '../../types';
import { formatCurrency } from '../../utils/formatters';
import './SupplierPreview.css';

interface SupplierPreviewProps {
  supplier: Supplier;
  onClose: () => void;
  onView?: () => void;
  onEdit?: () => void;
  onDelete?: () => void;
}

export default function SupplierPreview({
  supplier,
  onClose,
  onView,
  onEdit,
  onDelete,
}: SupplierPreviewProps) {
  const handleBackdropClick = (e: React.MouseEvent) => {
    if (e.target === e.currentTarget) {
      onClose();
    }
  };

  return (
    <div className="mobile-preview-backdrop" onClick={handleBackdropClick}>
      <div className="mobile-preview-container">
        {/* Header */}
        <div className="mobile-preview-header">
          <div className="preview-icon supplier-icon">
            <Package size={24} />
          </div>
          <div className="preview-title-section">
            <h2 className="preview-title">{supplier.supplier_name}</h2>
            <p className="preview-subtitle">{supplier.supplier_code}</p>
          </div>
          <button className="preview-close-btn" onClick={onClose}>
            <X size={24} />
          </button>
        </div>

        {/* Content */}
        <div className="mobile-preview-content">
          {/* Key Stats */}
          <SummaryGrid columns={1}>
            <SummaryCard
              icon={Package}
              label="Current Balance"
              value={formatCurrency(parseFloat(String(supplier.current_balance || 0)))}
              variant={(supplier.current_balance || 0) > 0 ? 'warning' : 'default'}
            />
          </SummaryGrid>

          {/* Status */}
          <div className="preview-section">
            <div className={`supplier-status-banner ${supplier.is_active ? 'active' : 'inactive'}`}>
              <span className="status-indicator"></span>
              {supplier.is_active ? 'Active Supplier' : 'Inactive Supplier'}
            </div>
          </div>

          {/* Contact Information */}
          <div className="preview-section">
            <h3 className="preview-section-title">Contact Information</h3>
            <div className="preview-detail-grid">
              {supplier.contact_person && (
                <div className="preview-detail-item">
                  <span className="detail-label">Contact Person</span>
                  <span className="detail-value">{supplier.contact_person}</span>
                </div>
              )}
              {supplier.phone && (
                <div className="preview-detail-item">
                  <span className="detail-label">Phone</span>
                  <span className="detail-value">{supplier.phone}</span>
                </div>
              )}
              {supplier.email && (
                <div className="preview-detail-item">
                  <span className="detail-label">Email</span>
                  <span className="detail-value">{supplier.email}</span>
                </div>
              )}
              {supplier.payment_terms && (
                <div className="preview-detail-item">
                  <span className="detail-label">Payment Terms</span>
                  <span className="detail-value">{supplier.payment_terms}</span>
                </div>
              )}
            </div>
          </div>

          {/* Address */}
          {supplier.address && (
            <div className="preview-section">
              <h3 className="preview-section-title">Address</h3>
              <div className="preview-address-card">
                {supplier.address.split('\n').map((line, idx) => (
                  <p key={idx}>{line}</p>
                ))}
              </div>
            </div>
          )}
        </div>

        {/* Actions */}
        <div className="mobile-preview-actions">
          {onEdit && (
            <button className="preview-action-btn primary" onClick={onEdit}>
              <Edit2 size={18} />
              <span>Edit Supplier</span>
            </button>
          )}
          {onView && (
            <button className="preview-action-btn secondary" onClick={onView}>
              <Eye size={18} />
              <span>View Details</span>
            </button>
          )}
          {onDelete && (
            <button className="preview-action-btn danger" onClick={onDelete}>
              <Trash2 size={18} />
              <span>Delete</span>
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
