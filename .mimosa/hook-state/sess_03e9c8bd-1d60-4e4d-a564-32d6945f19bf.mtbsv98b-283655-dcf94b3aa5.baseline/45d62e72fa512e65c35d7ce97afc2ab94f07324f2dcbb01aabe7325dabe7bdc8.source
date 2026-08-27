/**
 * EditPaymentForm — form for editing payment details (date, method, reference, notes).
 * Extracted from the monolithic CustomerDetailPage.
 */

import { useState, memo, type FormEvent, type ChangeEvent } from 'react';

import Button from '../../components/common/Button';
import { useUpdatePayment } from '../../hooks/useCustomerMutations';
import type { EditPaymentFormProps, EditPaymentFormData } from '../../types';

function EditPaymentForm({ payment, onClose, onSuccess }: EditPaymentFormProps) {
  const [formData, setFormData] = useState<EditPaymentFormData>({
    payment_date: payment.payment_date?.split('T')[0] || '',
    payment_method: payment.payment_method || 'Cash',
    reference_no: payment.reference_no || '',
    notes: payment.notes || '',
  });

  const updatePaymentMutation = useUpdatePayment(onSuccess);

  const handleChange = (e: ChangeEvent<HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement>) => {
    const { name, value } = e.target;
    setFormData((prev) => ({ ...prev, [name]: value }));
  };

  const handleSubmit = (e: FormEvent) => {
    e.preventDefault();
    updatePaymentMutation.mutate({ paymentId: payment.id, data: formData as unknown as Record<string, unknown> });
  };

  return (
    <form onSubmit={handleSubmit} className="edit-payment-form">
      <div className="form-group">
        <label>Payment No</label>
        <input type="text" value={payment.payment_no} disabled className="form-input disabled" />
      </div>

      <div className="form-group">
        <label>Amount</label>
        <input
          type="text"
          value={`$${Number(payment.amount || 0).toFixed(2)}`}
          disabled
          className="form-input disabled"
        />
        <small className="form-hint">Amount cannot be changed. Delete and create new payment if needed.</small>
      </div>

      <div className="form-row-edit">
        <div className="form-group">
          <label>Payment Date</label>
          <input
            type="date"
            name="payment_date"
            value={formData.payment_date}
            onChange={handleChange}
            className="form-input"
          />
        </div>

        <div className="form-group">
          <label>Payment Method</label>
          <select
            name="payment_method"
            value={formData.payment_method}
            onChange={handleChange}
            className="form-input"
          >
            <option value="Cash">Cash</option>
            <option value="Check">Check</option>
            <option value="Bank Transfer">Bank Transfer</option>
            <option value="Credit Card">Credit Card</option>
            <option value="Debit Card">Debit Card</option>
          </select>
        </div>
      </div>

      <div className="form-group">
        <label>Reference No</label>
        <input
          type="text"
          name="reference_no"
          value={formData.reference_no}
          onChange={handleChange}
          placeholder="Check number, transaction ID, etc."
          className="form-input"
        />
      </div>

      <div className="form-group">
        <label>Notes</label>
        <textarea
          name="notes"
          value={formData.notes}
          onChange={handleChange}
          rows={3}
          className="form-input"
          placeholder="Optional notes..."
        />
      </div>

      <div className="form-actions">
        <Button variant="secondary" type="button" onClick={onClose}>
          Cancel
        </Button>
        <Button variant="primary" type="submit" loading={updatePaymentMutation.isPending}>
          Save Changes
        </Button>
      </div>
    </form>
  );
}

export default memo(EditPaymentForm);
