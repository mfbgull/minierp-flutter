import { useState, useEffect } from 'react';
import toast from 'react-hot-toast';
import { useMutation, useQueryClient } from '@tanstack/react-query';

import api from '../../utils/api';
import Button from '../common/Button';
import type { PurchaseOrderDetail } from '../../types';
import './POPaymentModal.css';

interface POPaymentModalProps {
  po: PurchaseOrderDetail;
  onClose: () => void;
  onSuccess?: () => void;
}

interface FormData {
  payment_date: string;
  amount: string;
  payment_method: string;
  reference_no: string;
  notes: string;
}

interface FormErrors {
  payment_date?: string;
  amount?: string;
}

export default function POPaymentModal({ po, onClose, onSuccess }: POPaymentModalProps) {
  const queryClient = useQueryClient();
  const poBalance = parseFloat(String(po.balance_amount ?? po.total_amount ?? 0));

  const [formData, setFormData] = useState<FormData>({
    payment_date: new Date().toISOString().split('T')[0],
    amount: String(poBalance.toFixed(2)),
    payment_method: 'Cash',
    reference_no: '',
    notes: '',
  });
  const [errors, setErrors] = useState<FormErrors>({});

  const mutation = useMutation({
    mutationFn: async (data: Record<string, unknown>) => {
      return api.post('/payments', data);
    },
    onSuccess: () => {
      toast.success('Payment recorded successfully');
      queryClient.invalidateQueries({ queryKey: ['purchaseOrder', po.id] });
      queryClient.invalidateQueries({ queryKey: ['supplierPurchaseOrders', po.supplier_id] });
      queryClient.invalidateQueries({ queryKey: ['purchaseOrders'] });
      onSuccess?.();
      onClose();
    },
    onError: (error: unknown) => {
      const err = error as { response?: { data?: { error?: string } } };
      toast.error(err.response?.data?.error || 'Failed to record payment');
    },
  });

  const handleChange = (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement>) => {
    const { name, value } = e.target;
    setFormData(prev => ({ ...prev, [name]: value }));
    if (errors[name as keyof FormErrors]) {
      setErrors(prev => ({ ...prev, [name]: '' }));
    }
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();

    const newErrors: FormErrors = {};
    if (poBalance <= 0) {
      newErrors.amount = 'This PO is fully paid. No payment can be recorded.';
    }
    if (!formData.payment_date) newErrors.payment_date = 'Payment date is required';
    if (!formData.amount || parseFloat(formData.amount) <= 0) newErrors.amount = newErrors.amount || 'Amount must be greater than 0';

    const balance = poBalance;
    if (parseFloat(formData.amount) > balance) {
      newErrors.amount = `Amount cannot exceed PO balance (${poBalance.toFixed(2)})`;
    }

    if (Object.keys(newErrors).length > 0) {
      setErrors(newErrors);
      return;
    }

    mutation.mutate({
      supplier_id: po.supplier_id,
      payment_date: formData.payment_date,
      amount: parseFloat(formData.amount),
      payment_method: formData.payment_method,
      reference_no: formData.reference_no || undefined,
      notes: formData.notes || undefined,
      po_allocations: [{ po_id: po.id, amount: parseFloat(formData.amount) }],
    });
  };

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-container modal-large" onClick={(e) => e.stopPropagation()}>
        <div className="modal-header">
          <h2>Pay Supplier</h2>
          <button className="modal-close" onClick={onClose}>&times;</button>
        </div>
        <div className="modal-body">
          <form onSubmit={handleSubmit}>
            <div className="po-payment-info">
              <div className="po-payment-info-item">
                <span className="po-payment-label">Supplier</span>
                <span className="po-payment-value">{po.supplier_name}</span>
              </div>
              <div className="po-payment-info-item">
                <span className="po-payment-label">PO Number</span>
                <span className="po-payment-value">{po.po_no}</span>
              </div>
              <div className="po-payment-info-item">
                <span className="po-payment-label">Balance</span>
                <span className="po-payment-value po-payment-balance">
                  ${poBalance.toFixed(2)}
                </span>
              </div>
            </div>

            <div className="form-row">
              <div className="form-group">
                <label className="form-label">Payment Date *</label>
                <input
                  type="date"
                  name="payment_date"
                  value={formData.payment_date}
                  onChange={handleChange}
                  className={`form-input ${errors.payment_date ? 'form-input-error' : ''}`}
                />
                {errors.payment_date && <div className="error-message">{errors.payment_date}</div>}
              </div>

              <div className="form-group">
                <label className="form-label">Amount *</label>
                <input
                  type="number"
                  name="amount"
                  value={formData.amount}
                  onChange={handleChange}
                  step="0.01"
                  className={`form-input ${errors.amount ? 'form-input-error' : ''}`}
                />
                {errors.amount && <div className="error-message">{errors.amount}</div>}
              </div>
            </div>

            <div className="form-row">
              <div className="form-group">
                <label className="form-label">Payment Method</label>
                <select
                  name="payment_method"
                  value={formData.payment_method}
                  onChange={handleChange}
                  className="form-select"
                >
                  <option value="Cash">Cash</option>
                  <option value="Check">Check</option>
                  <option value="Bank Transfer">Bank Transfer</option>
                  <option value="Credit Card">Credit Card</option>
                  <option value="Online Payment">Online Payment</option>
                </select>
              </div>

              <div className="form-group">
                <label className="form-label">Reference Number</label>
                <input
                  type="text"
                  name="reference_no"
                  value={formData.reference_no}
                  onChange={handleChange}
                  className="form-input"
                  placeholder="Check #, TXN ID..."
                />
              </div>
            </div>

            <div className="form-group">
              <label className="form-label">Notes</label>
              <textarea
                name="notes"
                value={formData.notes}
                onChange={handleChange}
                className="form-input"
                rows={2}
                placeholder="Optional notes..."
              />
            </div>

            <div className="allocation-section">
              <h3 className="allocation-title">PO Allocation</h3>
              <div className="allocation-item">
                <div className="allocation-info">
                  <div className="allocation-invoice">{po.po_no}</div>
                  <div className="allocation-details">
                    <span className="allocation-amount">Balance: ${poBalance.toFixed(2)}</span>
                  </div>
                </div>
                <div className="allocation-amount-display">
                  ${parseFloat(formData.amount || '0').toFixed(2)}
                </div>
              </div>
            </div>

            <div className="form-actions">
              <Button type="button" variant="secondary" onClick={onClose}>
                Cancel
              </Button>
              <Button type="submit" variant="primary" loading={mutation.isPending} disabled={poBalance <= 0}>
                Record Payment
              </Button>
            </div>
          </form>
        </div>
      </div>
    </div>
  );
}
