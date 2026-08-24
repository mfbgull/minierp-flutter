import { useState } from 'react';
import toast from 'react-hot-toast';

import { useQuery, useMutation } from '@tanstack/react-query';

import type { Supplier, SupplierFormData } from '../../types';
import api from '../../utils/api';
import Button from '../common/Button';
import FormInput from '../common/FormInput';

interface SupplierFormProps {
  supplier?: Supplier | null;
  onClose: () => void;
  onSuccess: () => void;
}

export default function SupplierForm({ supplier, onClose, onSuccess }: SupplierFormProps) {
  const [formData, setFormData] = useState<SupplierFormData>({
    supplier_code: supplier?.supplier_code || '',
    supplier_name: supplier?.supplier_name || '',
    contact_person: supplier?.contact_person || '',
    email: supplier?.email || '',
    phone: supplier?.phone || '',
    address: supplier?.address || '',
    payment_terms: supplier?.payment_terms || 'Net 30',
    is_active: supplier?.is_active ?? 1
  });

  const [errors, setErrors] = useState<Record<string, string>>({});

  const { data: nextSupplierCode } = useQuery<string>({
    queryKey: ['supplierNextCode', supplier?.id],
    queryFn: async () => {
      const response = await api.get('/suppliers/next-code');
      return response.data.data.code as string;
    },
    enabled: !supplier,
    staleTime: 0
  });

  const effectiveSupplierCode = formData.supplier_code || (!supplier ? nextSupplierCode : '') || '';

  const mutation = useMutation({
    mutationFn: async (data: Record<string, unknown>) => {
      if (supplier) {
        return api.put(`/suppliers/${supplier.id}`, data);
      } else {
        return api.post('/suppliers', data);
      }
    },
    onSuccess: () => {
      toast.success(supplier ? 'Supplier updated successfully' : 'Supplier created successfully');
      onSuccess();
    },
    onError: (error: { response?: { data?: { error?: string } } }) => {
      const errorMsg = error.response?.data?.error || (supplier ? 'Failed to update supplier' : 'Failed to create supplier');
      toast.error(errorMsg);
    }
  });

  const handleChange = (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement>) => {
    const { name, value, type } = e.target;
    const checked = type === 'checkbox' ? (e.target as HTMLInputElement).checked : undefined;
    setFormData(prev => ({
      ...prev,
      [name]: type === 'checkbox' ? (checked ? 1 : 0) : value
    }));

    if (errors[name]) {
      setErrors(prev => ({
        ...prev,
        [name]: ''
      }));
    }
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();

    const newErrors: Record<string, string> = {};
    const submitSupplierCode = formData.supplier_code || (!supplier ? nextSupplierCode : '') || '';
    if (!formData.supplier_name.trim()) newErrors.supplier_name = 'Supplier name is required';
    if (!submitSupplierCode.trim()) newErrors.supplier_code = 'Supplier code is required';
    if (formData.email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(formData.email)) {
      newErrors.email = 'Invalid email format';
    }

    if (Object.keys(newErrors).length > 0) {
      setErrors(newErrors);
      return;
    }

    mutation.mutate({
      ...formData,
      supplier_code: formData.supplier_code || (!supplier ? nextSupplierCode : '') || ''
    } as unknown as Record<string, unknown>);
  };

  return (
    <form onSubmit={handleSubmit} className="supplier-form">
      <div className="form-row">
        <FormInput
          label="Supplier Code *"
          name="supplier_code"
          value={effectiveSupplierCode}
          onChange={handleChange}
          error={errors.supplier_code}
          required
          readOnly={!supplier}
          autoFocus={!supplier}
          help="Unique identifier for the supplier"
        />
        <FormInput
          label="Supplier Name *"
          name="supplier_name"
          value={formData.supplier_name}
          onChange={handleChange}
          error={errors.supplier_name}
          required
        />
      </div>

      <div className="form-row">
        <FormInput
          label="Contact Person"
          name="contact_person"
          value={formData.contact_person}
          onChange={handleChange}
        />
        <FormInput
          label="Email"
          name="email"
          type="email"
          value={formData.email}
          onChange={handleChange}
          error={errors.email}
        />
      </div>

      <div className="form-row">
        <FormInput
          label="Phone"
          name="phone"
          type="tel"
          value={formData.phone}
          onChange={handleChange}
        />
        <FormInput
          label="Payment Terms"
          name="payment_terms"
          type="select"
          value={formData.payment_terms}
          onChange={handleChange}
          options={[
            { value: 'COD', label: 'COD (Cash on Delivery)' },
            { value: 'Net 15', label: 'Net 15 Days' },
            { value: 'Net 30', label: 'Net 30 Days' },
            { value: 'Net 45', label: 'Net 45 Days' },
            { value: 'Net 60', label: 'Net 60 Days' },
            { value: 'Net 90', label: 'Net 90 Days' }
          ]}
        />
      </div>

      <FormInput
        label="Address"
        name="address"
        type="textarea"
        value={formData.address}
        onChange={handleChange}
        rows={3}
      />

      <FormInput
        label="Status"
        name="is_active"
        type="checkbox"
        value={formData.is_active}
        onChange={handleChange}
        placeholder="Active"
      />

      <div className="form-actions">
        <Button type="button" variant="secondary" onClick={onClose}>
          Cancel
        </Button>
        <Button type="submit" variant="primary" loading={mutation.isPending}>
          {supplier ? 'Update' : 'Create'} Supplier
        </Button>
      </div>
    </form>
  );
}
