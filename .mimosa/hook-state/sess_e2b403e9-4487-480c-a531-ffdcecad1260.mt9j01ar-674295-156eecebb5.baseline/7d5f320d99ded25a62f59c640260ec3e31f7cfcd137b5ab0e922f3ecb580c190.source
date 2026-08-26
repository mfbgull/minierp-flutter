import { useState, useMemo } from 'react';
import toast from 'react-hot-toast';

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Plus, Printer, FileText } from 'lucide-react';

import Button from '../../components/common/Button';
import FormInput from '../../components/common/FormInput';
import { usePaymentPrint } from '../../components/payment/usePaymentPrint';
import api from '../../utils/api';

interface SupplierInfo {
  supplier_name: string;
  supplier_code: string;
}

interface PurchaseOrder {
  id: number;
  po_no: string;
  po_date: string;
  total_amount: number;
  balance_amount?: number;
}

interface POAllocation {
  po_id: number;
  po_no: string;
  amount: number;
  max_amount: number;
}

interface FormData {
  payment_date: string;
  amount: string;
  payment_method: string;
  reference_no: string;
  notes: string;
  po_allocations: POAllocation[];
}

interface SupplierPaymentModalProps {
  supplierId: string | number;
  supplier: SupplierInfo;
  onClose: () => void;
  onSuccess?: () => void;
}

export default function SupplierPaymentModal({ supplierId, supplier, onClose, onSuccess }: SupplierPaymentModalProps) {
  const [formData, setFormData] = useState<FormData>({
    payment_date: new Date().toISOString().split('T')[0],
    amount: '',
    payment_method: 'Cash',
    reference_no: '',
    notes: '',
    po_allocations: []
  });

  const [errors, setErrors] = useState<Record<string, string>>({});
  const [lastPaymentId, setLastPaymentId] = useState<number | null>(null);
  const { fetchReceiptData, printA4, printThermal } = usePaymentPrint();
  const queryClient = useQueryClient();

  const { data: purchaseOrders = [], isLoading } = useQuery<PurchaseOrder[]>({
    queryKey: ['purchaseOrders', supplierId],
    queryFn: async () => {
      const response = await api.get(`/purchase-orders?supplier_id=${supplierId}`);
      const pos = Array.isArray(response.data?.data) ? response.data.data : response.data;
      return (Array.isArray(pos) ? pos : []).filter((po: PurchaseOrder) => (po.balance_amount ?? po.total_amount ?? 0) > 0);
    },
    enabled: !!supplierId
  });

  const allocationTotal = useMemo(() => {
    return formData.po_allocations.reduce((sum, alloc) =>
      sum + parseFloat(alloc.amount?.toString() || '0'), 0
    );
  }, [formData.po_allocations]);

  const unallocatedAmount = useMemo(() => {
    return parseFloat(formData.amount || '0') - allocationTotal;
  }, [formData.amount, allocationTotal]);

  const handleAddAllocation = (poId: number) => {
    const po = purchaseOrders.find(p => p.id === poId);
    if (!po) return;

    if (formData.po_allocations.some(alloc => alloc.po_id === poId)) {
      return;
    }

    const balance = po.balance_amount ?? po.total_amount;
    const newAllocation: POAllocation = {
      po_id: poId,
      po_no: po.po_no,
      amount: Math.min(balance, parseFloat(formData.amount || '0')),
      max_amount: balance
    };

    setFormData(prev => ({
      ...prev,
      po_allocations: [...prev.po_allocations, newAllocation]
    }));
  };

  const handleRemoveAllocation = (poId: number) => {
    setFormData(prev => ({
      ...prev,
      po_allocations: prev.po_allocations.filter(alloc => alloc.po_id !== poId)
    }));
  };

  const handleAllocationAmountChange = (poId: number, amount: string) => {
    const po = purchaseOrders.find(p => p.id === poId);
    if (!po) return;

    const newAmount = Math.min(parseFloat(amount || '0'), po.balance_amount ?? po.total_amount);

    setFormData(prev => ({
      ...prev,
      po_allocations: prev.po_allocations.map(alloc =>
        alloc.po_id === poId ? { ...alloc, amount: newAmount } : alloc
      )
    }));
  };

  const handleAutoAllocate = () => {
    const remainingAmount = parseFloat(formData.amount || '0');
    const newAllocations: POAllocation[] = [];
    let amountLeft = remainingAmount;

    purchaseOrders.forEach(po => {
      if (amountLeft <= 0) return;

      const existingAllocation = formData.po_allocations.find(alloc => alloc.po_id === po.id);
      if (existingAllocation) {
        amountLeft -= existingAllocation.amount;
        return;
      }

      const balance = po.balance_amount ?? po.total_amount;
      const allocationAmount = Math.min(balance, amountLeft);
      if (allocationAmount > 0) {
        newAllocations.push({
          po_id: po.id,
          po_no: po.po_no,
          amount: allocationAmount,
          max_amount: balance
        });
        amountLeft -= allocationAmount;
      }
    });

    setFormData(prev => ({
      ...prev,
      po_allocations: [...prev.po_allocations, ...newAllocations]
    }));
  };

  const handleChange = (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement>) => {
    const { name, value } = e.target;
    setFormData(prev => ({
      ...prev,
      [name]: name === 'amount' ? value : value
    }));

    if (errors[name]) {
      setErrors(prev => ({
        ...prev,
        [name]: ''
      }));
    }
  };

  const mutation = useMutation({
    mutationFn: async (data: Record<string, unknown>) => {
      return api.post('/payments', data);
    },
    onSuccess: (response) => {
      toast.success('Supplier payment recorded successfully');
      queryClient.invalidateQueries({ queryKey: ['suppliers'] });
      queryClient.invalidateQueries({ queryKey: ['supplier', supplierId] });
      queryClient.invalidateQueries({ queryKey: ['supplierPayments', supplierId] });
      queryClient.invalidateQueries({ queryKey: ['supplierLedger', supplierId] });
      queryClient.invalidateQueries({ queryKey: ['supplierBalance', supplierId] });
      queryClient.invalidateQueries({ queryKey: ['purchaseOrders'] });
      const paymentId = response.data.data?.id;
      if (paymentId) {
        setLastPaymentId(paymentId);
      } else {
        onSuccess?.();
        onClose();
      }
    },
    onError: (error: unknown) => {
      const errorMsg = (error as { response?: { data?: { error?: string } } })?.response?.data?.error || 'Failed to record payment';
      toast.error(errorMsg);
    }
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();

    const newErrors: Record<string, string> = {};
    if (!formData.payment_date) newErrors.payment_date = 'Payment date is required';
    if (!formData.amount || parseFloat(formData.amount) <= 0) newErrors.amount = 'Amount must be greater than 0';
    if (parseFloat(formData.amount) !== allocationTotal) {
      newErrors.amount = `Amount must match total allocated (${allocationTotal.toFixed(2)})`;
    }
    if (formData.po_allocations.length === 0) {
      newErrors.po_allocations = 'At least one PO allocation is required';
    }

    if (Object.keys(newErrors).length > 0) {
      setErrors(newErrors);
      return;
    }

    const poNos = formData.po_allocations.map(alloc => alloc.po_no);

    const description = poNos.length > 0
      ? `Payment for ${poNos.length === 1 ? poNos[0] : poNos.join(', ')}`
      : 'Payment';

    mutation.mutate({
      ...formData,
      amount: parseFloat(formData.amount),
      supplier_id: supplierId,
      description,
      po_allocations: formData.po_allocations.map(alloc => ({
        po_id: alloc.po_id,
        amount: parseFloat(alloc.amount.toString())
      }))
    });
  };

  const handlePrintReceipt = async (thermal: boolean) => {
    if (!lastPaymentId) return;
    try {
      const data = await fetchReceiptData(lastPaymentId);
      if (thermal) {
        printThermal(data);
      } else {
        printA4(data);
      }
    } catch {
      toast.error('Failed to load receipt data');
    }
  };

  if (lastPaymentId) {
    return (
      <div className="payment-modal payment-modal-success">
        <div className="success-icon">✓</div>
        <h2 className="success-title">Payment Recorded Successfully</h2>
        <p className="success-subtitle">What would you like to do next?</p>
        <div className="success-actions">
          <Button variant="primary" onClick={() => handlePrintReceipt(false)}>
            <Printer size={18} />
            Print Receipt (A4)
          </Button>
          <Button variant="secondary" onClick={() => handlePrintReceipt(true)}>
            <FileText size={18} />
            Print Thermal Receipt
          </Button>
        </div>
        <div className="form-actions" style={{ marginTop: '24px' }}>
          <Button variant="secondary" onClick={() => { onClose(); onSuccess?.(); }}>
            Close
          </Button>
        </div>
      </div>
    );
  }

  return (
    <form onSubmit={handleSubmit} className="payment-modal">
      <div className="form-row">
        <div className="form-group">
          <label className="form-label">Supplier</label>
          <div className="customer-info">
            <div className="customer-name">{supplier?.supplier_name}</div>
            <div className="customer-code">{supplier?.supplier_code}</div>
          </div>
        </div>

        <FormInput
          label="Payment Date *"
          name="payment_date"
          type="date"
          value={formData.payment_date}
          onChange={handleChange}
          required
        />
      </div>

      <div className="form-row">
        <FormInput
          label="Total Amount *"
          name="amount"
          type="number"
          value={formData.amount}
          onChange={handleChange}
          required
          step="0.01"
        />

        <FormInput
          label="Payment Method"
          name="payment_method"
          type="select"
          value={formData.payment_method}
          onChange={handleChange}
          options={[
            { value: 'Cash', label: 'Cash' },
            { value: 'Check', label: 'Check' },
            { value: 'Bank Transfer', label: 'Bank Transfer' },
            { value: 'Credit Card', label: 'Credit Card' },
            { value: 'Debit Card', label: 'Debit Card' }
          ]}
        />
      </div>

      <FormInput
        label="Reference Number"
        name="reference_no"
        value={formData.reference_no}
        onChange={handleChange}
      />

      <FormInput
        label="Notes"
        name="notes"
        type="textarea"
        value={formData.notes}
        onChange={handleChange}
        rows={3}
      />

      <div className="allocation-section">
        <div className="allocation-header">
          <h3>PO Allocations</h3>
          <Button
            type="button"
            variant="secondary"
            onClick={handleAutoAllocate}
            disabled={formData.po_allocations.length === 0 && !formData.amount}
          >
            <Plus size={16} />
            Auto Allocate
          </Button>
        </div>

        {errors.po_allocations && (
          <div className="error-message">{errors.po_allocations}</div>
        )}

        {isLoading ? (
          <div className="loading">
            <div className="spinner"></div>
          </div>
        ) : (
          <>
            <div className="available-invoices">
              <label className="form-label">Available Purchase Orders</label>
              {purchaseOrders
                .filter(po => !formData.po_allocations.some(alloc => alloc.po_id === po.id))
                .map(po => (
                  <div key={po.id} className="invoice-item">
                    <div className="invoice-info">
                      <div className="invoice-no">{po.po_no}</div>
                      <div className="invoice-details">
                        <span className="invoice-date">{new Date(po.po_date).toLocaleDateString()}</span>
                        <span className="invoice-amount">${((po.balance_amount ?? po.total_amount) || 0).toFixed(2)}</span>
                      </div>
                    </div>
                    <Button
                      variant="secondary"
                      onClick={() => handleAddAllocation(po.id)}
                      disabled={parseFloat(formData.amount || '0') <= 0}
                    >
                      <Plus size={14} />
                    </Button>
                  </div>
                ))}

              {purchaseOrders.filter(po =>
                !formData.po_allocations.some(alloc => alloc.po_id === po.id)
              ).length === 0 && (
                <p className="no-invoices">No outstanding purchase orders</p>
              )}
            </div>

            {formData.po_allocations.length > 0 && (
              <div className="allocated-invoices">
                <label className="form-label">Allocated Purchase Orders</label>
                {formData.po_allocations.map(allocation => (
                    <div key={allocation.po_id.toString()} className="allocation-item">
                      <div className="allocation-info">
                        <div className="allocation-invoice">{allocation.po_no}</div>
                        <div className="allocation-details">
                          <span className="allocation-amount">Balance: ${allocation.max_amount.toFixed(2)}</span>
                          <FormInput
                            type="number"
                            value={allocation.amount}
                            onChange={(e) => handleAllocationAmountChange(allocation.po_id, e.target.value)}
                            className="allocation-input"
                            step="0.01"
                          />
                        </div>
                      </div>
                      <Button
                        variant="danger"
                        onClick={() => handleRemoveAllocation(allocation.po_id)}
                        className="allocation-remove-btn"
                      >
                        ×
                      </Button>
                    </div>
                ))}
              </div>
            )}
          </>
        )}

        <div className="allocation-summary">
          <div className="summary-row">
            <span>Total Payment Amount:</span>
            <span>${parseFloat(formData.amount || '0').toFixed(2)}</span>
          </div>
          <div className="summary-row">
            <span>Total Allocated:</span>
            <span>${allocationTotal.toFixed(2)}</span>
          </div>
          <div className="summary-row">
            <span>Unallocated Amount:</span>
            <span className={unallocatedAmount !== 0 ? 'unallocated-amount' : ''}>
              ${unallocatedAmount.toFixed(2)}
            </span>
          </div>
        </div>
      </div>

      <div className="form-actions">
        <Button type="button" variant="secondary" onClick={onClose}>
          Cancel
        </Button>
        <Button type="submit" variant="primary" loading={mutation.isPending}>
          Record Payment
        </Button>
      </div>
    </form>
  );
}
