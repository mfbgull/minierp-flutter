import React from 'react';
import { useParams, useSearchParams, Navigate } from 'react-router-dom';

import { useQuery } from '@tanstack/react-query';

import InvoiceViewPage from '../../pages/sales/InvoiceViewPage';
import SalesInvoicePage from '../../pages/sales/SalesInvoicePage';
import api from '../../utils/api';
import './InvoiceRouter.css';

interface InvoiceRouterProps {
  defaultMode?: 'view' | 'edit';
}

export default function InvoiceRouter({ defaultMode = 'view' }: InvoiceRouterProps) {
  const { id: invoiceId } = useParams();
  const [searchParams] = useSearchParams();

  const mode = searchParams.get('mode') || defaultMode;
  const action = searchParams.get('action');

  // Fetch invoice data to determine if it exists
  const { data: invoice, isLoading, error } = useQuery({
    queryKey: ['invoice', invoiceId],
    queryFn: async () => {
      const response = await api.get(`/invoices/${invoiceId}`);
      return response.data;
    },
    enabled: !!invoiceId,
    retry: 1,
    staleTime: 0,
  });

  // Loading state
  if (isLoading) {
    return (
      <div className="invoice-router-loading">
        <div className="spinner"></div>
        <p>Loading invoice...</p>
      </div>
    );
  }

  // Error state - invoice not found
  if (error || !invoice) {
    return <Navigate to="/sales" replace />;
  }

  // Route logic based on various conditions
  const shouldShowEditMode = () => {
    // Explicit mode parameter takes highest priority
    if (mode === 'edit') {
      return true;
    }
    if (mode === 'view') {
      return false;
    }

    // Action-based routing
    if (action === 'edit') {
      return true;
    }
    if (action === 'view' || action === 'print' || action === 'download' || action === 'email') {
      return false;
    }

    // Business logic routing based on invoice status
    if (invoice.status === 'Draft') {
      return true;
    }

    // Edit mode for unpaid invoices if user has edit permissions
    if (invoice.status === 'Unpaid') {
      // Check if user came from edit context (referrer analysis)
      const referrer = document.referrer;
      if (referrer.includes('/edit') || referrer.includes('/create')) {
        return true;
      }
      // For unpaid invoices, default to edit mode to allow modifications
      return true;
    }

    // Default to view mode for paid/completed invoices
    if (['Paid', 'Partially Paid', 'Cancelled'].includes(invoice.status)) {
      return false;
    }

    // If no specific status match, use defaultMode
    return defaultMode === 'edit';
  };

  const showEdit = shouldShowEditMode();

  if (showEdit) {
    return <SalesInvoicePage />;
  } else {
    return <InvoiceViewPage />;
  }
}