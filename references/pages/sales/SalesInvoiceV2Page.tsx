/**
 * SalesInvoiceV2Page — Page orchestrator for the v2 invoice creation modal.
 *
 * Integrates: CustomerPanel, ItemsGrid, TotalsPanel, PaymentSection, Header, Footer.
 * Manages form state, calculations, mutations, and source document pre-fill.
 */

import { useState, useCallback, useEffect, useRef } from 'react';
import { ChevronDown } from 'lucide-react';
import { useSearchParams, useNavigate } from 'react-router-dom';

import { useSettings } from '../../context/SettingsContext';
import { useInvoiceData } from '../../hooks/useInvoiceData';
import { useSaveInvoice, useRecordPayment } from '../../hooks/useInvoiceMutations';
import api from '../../utils/api';

import { generateInvoiceNo } from '../../utils/invoiceCalculations';
import type {
  InvoiceV2State,
  InvoiceV2Customer,
  InvoiceV2Source,
} from '../../types/invoiceV2';
import type { Discount, InvoiceSubmitData } from '../../types';
import {
  createDefaultInvoiceV2State,
  createEmptyInvoiceV2Item,
  calculateItemTotal,
  calculateSubtotal,
  calculateTax,
  calculateDiscount,
  calculateTotal,
} from '../../utils/invoiceV2Calculations';

import InvoiceV2Modal from '../../components/invoice-v2/InvoiceV2Modal';
import InvoiceV2Header from '../../components/invoice-v2/InvoiceV2Header';
import InvoiceV2Footer from '../../components/invoice-v2/InvoiceV2Footer';
import InvoiceV2CustomerPanel from '../../components/invoice-v2/InvoiceV2CustomerPanel';
import InvoiceV2ItemsGrid from '../../components/invoice-v2/InvoiceV2ItemsGrid';
import InvoiceV2TotalsPanel from '../../components/invoice-v2/InvoiceV2TotalsPanel';
import InvoiceV2PaymentSection from '../../components/invoice-v2/InvoiceV2PaymentSection';

/**
 * SalesInvoiceV2Page — Page orchestrator for the v2 invoice creation modal.
 */
export default function SalesInvoiceV2Page() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const { formatCurrency, getCurrencySymbol } = useSettings();

  /* ── Source document params ───────────────────────────────── */
  const fromType = searchParams.get('from'); // 'quotation' | 'so' | null
  const fromId = searchParams.get('id');
  /* ── Data ── */
  const { customers, customersLoading, items, settings } = useInvoiceData();

  /* ── Mutations ── */
  const saveMutation = useSaveInvoice(undefined, undefined);
  const recordPaymentMutation = useRecordPayment(undefined);

  /* ── State ── */
  const [state, setState] = useState<InvoiceV2State>(() => createDefaultInvoiceV2State());
  const [isLoading, setIsLoading] = useState(false);
  const [source, setSource] = useState<InvoiceV2Source | null>(null);
  const [isSaving, setIsSaving] = useState(false);
  const [showDates, setShowDates] = useState(false);
  const sourceFetchedRef = useRef(false);

  /* ── Update company info when settings load ── */
  useEffect(() => {
    if (settings && Object.keys(settings).length > 0) {
      setState((prev) => ({
        ...prev,
        company: {
          name: (settings as Record<string, { value: string }>).company_name?.value || 'Mini ERP',
          email: (settings as Record<string, { value: string }>).company_email?.value || 'support@minierp.com',
          phone: (settings as Record<string, { value: string }>).company_phone?.value || '+1 123 456 7890',
          address: (settings as Record<string, { value: string }>).company_address?.value || '456 Enterprise Ave, BC 12345',
          taxId: (settings as Record<string, { value: string }>).company_tax_id?.value || 'TAX-123456789',
        },
      }));
    }
  }, [settings]);

  /* ── Fetch source document data ── */
  useEffect(() => {
    if (sourceFetchedRef.current) return;
    if (fromType && fromId) {
      setIsLoading(true);
      sourceFetchedRef.current = true;

      const fetchSource = async () => {
        try {
          const endpoint = fromType === 'quotation' ? `/quotations/${fromId}` : `/sales-orders/${fromId}`;
          const response = await api.get(endpoint);
          const data = response.data;

          const ref =
            fromType === 'quotation'
              ? data.quotation_no || `Q-${fromId}`
              : data.so_no || `SO-${fromId}`;

          setSource({ type: fromType as 'quotation' | 'so', id: Number(fromId), reference: ref });

          const srcCustomer = customers.find(
            (c) => c.id === Number(data.customer_id)
          );

          const srcItems = (data.items || []).map(
            (item: Record<string, unknown>, index: number) => ({
              id: Date.now() + index,
              itemId: Number(item.item_id),
              description: String(item.item_name || item.description || ''),
              quantity: Number(item.quantity) || 1,
              rate: Number(item.unit_price || item.rate) || 0,
              tax: Number(item.tax_rate || item.tax || 0),
              discount: { type: 'flat' as const, value: 0 },
            })
          );

          setState((prev) => ({
            ...prev,
            customer: srcCustomer
              ? {
                  id: srcCustomer.id,
                  name: srcCustomer.customer_name,
                  code: srcCustomer.customer_code,
                  email: srcCustomer.email || '',
                  phone: srcCustomer.phone || '',
                  address: srcCustomer.billing_address || '',
                  balance: 0,
                  creditLimit: 0,
                  creditUtilization: 0,
                }
              : prev.customer,
            items: srcItems.length > 0 ? srcItems : prev.items,
          }));

          if (data.customer_id) {
            try {
              const balRes = await api.get(`/customers/${data.customer_id}/balance`);
              const balData = balRes.data.data;
              const custRes = await api.get(`/customers/${data.customer_id}`);
              const custData = custRes.data.data;

              setState((prev) => ({
                ...prev,
                customer: prev.customer
                  ? {
                      ...prev.customer,
                      balance: balData.currentBalance || 0,
                      creditLimit: Number(custData.credit_limit) || 0,
                      creditUtilization:
                        custData.credit_limit && Number(custData.credit_limit) > 0
                          ? ((balData.currentBalance || 0) / Number(custData.credit_limit)) * 100
                          : 0,
                    }
                  : prev.customer,
              }));
            } catch {
              // Non-critical
            }
          }
        } catch {
          console.error('Failed to load source document');
        } finally {
          setIsLoading(false);
        }
      };

      fetchSource();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [fromType, fromId, customers]);

  /* ── Customer select ── */
  const handleCustomerSelect = useCallback(
    async (customer: InvoiceV2Customer) => {
      try {
        const balRes = await api.get(`/customers/${customer.id}/balance`);
        const balData = balRes.data.data;
        const custRes = await api.get(`/customers/${customer.id}`);
        const custData = custRes.data.data;

        setState((prev) => ({
          ...prev,
          customer: {
            ...customer,
            balance: balData.currentBalance || 0,
            creditLimit: Number(custData.credit_limit) || 0,
            creditUtilization:
              custData.credit_limit && Number(custData.credit_limit) > 0
                ? ((balData.currentBalance || 0) / Number(custData.credit_limit)) * 100
                : 0,
          },
        }));
      } catch {
        setState((prev) => ({ ...prev, customer }));
      }
    },
    []
  );

  /* ── Item-level update ── */
  const handleUpdateItem = useCallback(
    (id: number, field: string, value: unknown) => {
      setState((prev) => ({
        ...prev,
        items: prev.items.map((item) => {
          if (item.id !== id) return item;

          // Multi-field atomic update (used by the grid for loose-item recalculation)
          if (field === 'patch') return { ...item, ...(value as Partial<typeof item>) };
          if (field === 'itemId') return { ...item, itemId: value as number | string };
          if (field === 'description') return { ...item, description: value as string };
          if (field === 'quantity') return { ...item, quantity: Number(value) || 0 };
          if (field === 'rate') return { ...item, rate: Number(value) || 0 };
          if (field === 'tax') return { ...item, tax: Number(value) || 0 };
          if (field === 'discountValue')
            return { ...item, discount: { ...item.discount, value: Number(value) || 0 } };
          if (field === 'discountType')
            return { ...item, discount: { ...item.discount, type: value as 'flat' | 'percentage' } };

          return item;
        }),
      }));
    },
    []
  );

  /* ── Add new item row ── */
  const handleAddNewItem = useCallback(() => {
    const newId = Date.now();
    setState((prev) => ({
      ...prev,
      items: [...prev.items, createEmptyInvoiceV2Item(newId)],
    }));
    return newId;
  }, []);

  /* ── Remove item row ── */
  const handleRemoveItem = useCallback((id: number) => {
    setState((prev) => {
      if (prev.items.length <= 1) return prev;
      return { ...prev, items: prev.items.filter((item) => item.id !== id) };
    });
  }, []);

  /* ── Discount scope ── */
  const handleUpdateDiscountScope = useCallback((scope: 'item' | 'invoice') => {
    setState((prev) => ({ ...prev, discountScope: scope }));
  }, []);

  /* ── Discount update ── */
  const handleUpdateDiscount = useCallback((discount: Discount) => {
    setState((prev) => ({ ...prev, discount }));
  }, []);

  /* ── Notes / Terms ── */
  const handleUpdateNotes = useCallback((notes: string) => {
    setState((prev) => ({ ...prev, notes }));
  }, []);

  const handleUpdateTerms = useCallback((terms: string) => {
    setState((prev) => ({ ...prev, terms }));
  }, []);

  /* ── Payment updates ── */
  const handleUpdatePayment = useCallback(
    (payment: Partial<InvoiceV2State['payment']>) => {
      setState((prev) => ({
        ...prev,
        payment: { ...prev.payment, ...payment },
      }));
    },
    []
  );

  const handleAddPaymentMethod = useCallback(() => {
    setState((prev) => ({
      ...prev,
      payment: {
        ...prev.payment,
        paymentMethods: [
          ...prev.payment.paymentMethods,
          { id: Date.now(), method: 'Cash', amount: 0, reference_no: '' },
        ],
      },
    }));
  }, []);

  const handleRemovePaymentMethod = useCallback((id: number) => {
    setState((prev) => ({
      ...prev,
      payment: {
        ...prev.payment,
        paymentMethods: prev.payment.paymentMethods.filter((pm) => pm.id !== id),
      },
    }));
  }, []);

  const handleUpdatePaymentMethod = useCallback(
    (id: number, field: string, value: string) => {
      setState((prev) => ({
        ...prev,
        payment: {
          ...prev.payment,
          paymentMethods: prev.payment.paymentMethods.map((pm) => {
            if (pm.id !== id) return pm;
            if (field === 'method') return { ...pm, method: value };
            if (field === 'amount') return { ...pm, amount: parseFloat(value) || 0 };
            if (field === 'reference_no') return { ...pm, reference_no: value };
            return pm;
          }),
        },
      }));
    },
    []
  );

  /* ── Build submit payload ── */
  const buildInvoicePayload = useCallback(
    (invoiceNo: string): InvoiceSubmitData => {
      const total = calculateTotal(state.items, state.discountScope, state.discount);

      return {
        invoice_no: invoiceNo,
        customer_id: state.customer?.id || 0,
        invoice_date: state.invoiceDate,
        due_date: state.dueDate,
        total_amount: total,
        discount_scope: state.discountScope,
        discount_type: state.discount.type,
        discount_value: state.discount.value,
        notes: state.notes,
        terms: state.terms,
        items: state.items.map((item) => ({
          item_id: item.itemId,
          description: item.description,
          quantity: item.quantity,
          unit_price: item.rate,
          tax_rate: item.tax,
          discount_type: state.discountScope === 'item' ? item.discount.type : state.discount.type,
          discount_value: state.discountScope === 'item' ? item.discount.value : state.discount.value,
        })),
        status: 'Unpaid',
        record_payment: state.payment.recordPayment,
        payment: state.payment.recordPayment
          ? {
              payment_date: state.payment.paymentDate,
              amount: state.payment.paymentMethods.reduce(
                (sum, pm) => sum + (pm.amount || 0),
                0,
              ),
              payment_method: state.payment.paymentMethods[0]?.method || 'Cash',
              reference_no: state.payment.paymentMethods[0]?.reference_no || '',
              notes: state.payment.paymentNotes,
            }
          : undefined,
      };
    },
    [state]
  );

  /* ── Save handlers ── */
  const doSave = useCallback(
    async (action: 'view' | 'new') => {
      if (!state.customer) {
        return;
      }

      setIsSaving(true);

      // Generate a fresh invoice number for each save
      const invoiceNo = generateInvoiceNo();
      const payload = buildInvoicePayload(invoiceNo);

      try {
        const response = await saveMutation.mutateAsync(payload as unknown as Record<string, unknown>);

        // Record payment if enabled
        if (state.payment.recordPayment) {
          const invoiceId = response.data?.data?.id || response.data?.id;
          const actualInvoiceNo = response.data?.data?.invoice_no || invoiceNo;

          let paymentAmount = state.payment.paymentMethods.reduce(
            (sum, pm) => sum + (pm.amount || 0),
            0,
          );
          if (paymentAmount <= 0) {
            paymentAmount = calculateTotal(state.items, state.discountScope, state.discount);
          }

          try {
            await recordPaymentMutation.mutateAsync({
              customer_id: state.customer.id,
              invoice_id: invoiceId,
              invoice_no: actualInvoiceNo,
              payment_date: state.payment.paymentDate,
              amount: paymentAmount,
              payment_method: state.payment.paymentMethods[0]?.method || 'Cash',
              reference_no: state.payment.paymentMethods[0]?.reference_no || '',
              notes: state.payment.paymentNotes || `Payment for ${actualInvoiceNo}`,
            } as unknown as Record<string, unknown>);
          } catch {
            // Payment recording failed but invoice was created — still navigate
          }

          if (action === 'view' && invoiceId) {
            navigate(`/sales/invoice/${invoiceId}/view`);
          } else {
            // Reset for new invoice
            setState(createDefaultInvoiceV2State());
            setSource(null);
            sourceFetchedRef.current = false;
          }
        } else {
          const invoiceId = response.data?.data?.id || response.data?.id;
          if (action === 'view' && invoiceId) {
            navigate(`/sales/invoice/${invoiceId}/view`);
          } else {
            setState(createDefaultInvoiceV2State());
            setSource(null);
            sourceFetchedRef.current = false;
          }
        }
      } catch {
        // Error handled by mutation's onError
      } finally {
        setIsSaving(false);
      }
    },
    [state, buildInvoicePayload, saveMutation, recordPaymentMutation, navigate]
  );

  const handleCreateAndView = useCallback(() => doSave('view'), [doSave]);
  const handleCreateAndNew = useCallback(() => doSave('new'), [doSave]);

  /* ── Close handler ── */
  const handleClose = useCallback(() => {
    navigate('/sales');
  }, [navigate]);

  /* ── Auto-sync first payment method amount to invoice total ── */
  const currentTotal = calculateTotal(state.items, state.discountScope, state.discount);
  useEffect(() => {
    if (!state.payment.recordPayment) return;
    setState((prev) => ({
      ...prev,
      payment: {
        ...prev.payment,
        paymentMethods: prev.payment.paymentMethods.map((pm, i) =>
          i === 0 ? { ...pm, amount: currentTotal } : pm
        ),
      },
    }));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.items, state.discountScope, state.discount, state.payment.recordPayment]);

  /* ── Keyboard shortcuts (Ctrl+Enter, Alt+E) ── */
  const createAndViewRef = useRef(handleCreateAndView);
  createAndViewRef.current = handleCreateAndView;

  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      // Ctrl+Enter — Create & View
      if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') {
        e.preventDefault();
        if (state.customer) {
          createAndViewRef.current();
        }
        return;
      }
      // Alt+E — Toggle dates section
      if (e.altKey && e.key === 'e') {
        e.preventDefault();
        setShowDates((prev) => !prev);
        return;
      }
    };
    document.addEventListener('keydown', handler);
    return () => document.removeEventListener('keydown', handler);
  }, [state.customer]);

  /* ── Cancel handler (with dirty check via modal's Escape path) ── */
  const handleCancel = useCallback(() => {
    // Dispatch Escape key which the modal handles with dirty confirmation
    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
  }, []);

  /* ── Render ── */
  const isModalOpen = true;

  const isDirty =
    !!state.customer ||
    state.items.some((item) => item.description || item.rate > 0);

  // Memoize calc functions for components
  const calcItemTotal = useCallback(
    (item: Parameters<typeof calculateItemTotal>[0]) =>
      calculateItemTotal(item, state.discountScope),
    [state.discountScope],
  );

  const calcSubtotal = useCallback(
    () => calculateSubtotal(state.items),
    [state.items],
  );
  const calcTax = useCallback(
    () => calculateTax(state.items, state.discountScope),
    [state.items, state.discountScope],
  );
  const calcDiscount = useCallback(
    () => calculateDiscount(state.items, state.discountScope, state.discount),
    [state.items, state.discountScope, state.discount],
  );
  const calcTotal = useCallback(
    () => calculateTotal(state.items, state.discountScope, state.discount),
    [state.items, state.discountScope, state.discount],
  );

  return (
    <InvoiceV2Modal
      isOpen={isModalOpen}
      onClose={handleClose}
      isDirty={isDirty}
      source={source}
      onCreated={() => {}}
    >
      <InvoiceV2Header
        invoiceNo={state.invoiceNo}
        source={source}
        onClose={handleClose}
      />

      <div className="iv2-body">
        {isLoading ? (
          <div className="iv2-loading">
            <div className="iv2-skeleton iv2-skeleton-row" style={{ width: '60%' }} />
            <div className="iv2-skeleton iv2-skeleton-row" />
            <div className="iv2-skeleton iv2-skeleton-row" />
            <div className="iv2-skeleton iv2-skeleton-row" />
          </div>
        ) : (
          <>
            {/* Customer Panel */}
            <InvoiceV2CustomerPanel
              customer={state.customer}
              customers={customers}
              loading={customersLoading}
              onSelect={handleCustomerSelect}
              formatCurrency={formatCurrency}
            />

            {/* Dates (collapsible, Alt+E) */}
            <div className="iv2-collapsible">
              <div
                className="iv2-collapsible-header"
                onClick={() => setShowDates(!showDates)}
                tabIndex={0}
                onKeyDown={(e) => {
                  if (e.key === 'Enter' || e.key === ' ') {
                    e.preventDefault();
                    setShowDates(!showDates);
                  }
                }}
              >
                <span>Dates ({state.invoiceDate} → {state.dueDate})</span>
                <ChevronDown
                  size={14}
                  className={`chevron${showDates ? ' open' : ''}`}
                />
              </div>
              {showDates && (
                <div className="iv2-collapsible-body" style={{ display: 'flex', gap: '1rem' }}>
                  <div style={{ flex: 1 }}>
                    <label style={{ fontSize: '0.6875rem', fontWeight: 600, textTransform: 'uppercase', color: 'var(--iv2-text-tertiary)', display: 'block', marginBottom: '0.25rem' }}>
                      Invoice Date
                    </label>
                    <input
                      type="date"
                      className="iv2-editable-input"
                      value={state.invoiceDate}
                      onChange={(e) => setState((prev) => ({ ...prev, invoiceDate: e.target.value }))}
                    />
                  </div>
                  <div style={{ flex: 1 }}>
                    <label style={{ fontSize: '0.6875rem', fontWeight: 600, textTransform: 'uppercase', color: 'var(--iv2-text-tertiary)', display: 'block', marginBottom: '0.25rem' }}>
                      Due Date
                    </label>
                    <input
                      type="date"
                      className="iv2-editable-input"
                      value={state.dueDate}
                      onChange={(e) => setState((prev) => ({ ...prev, dueDate: e.target.value }))}
                    />
                  </div>
                </div>
              )}
            </div>

            {/* Items Grid */}
            <InvoiceV2ItemsGrid
              items={state.items}
              discountScope={state.discountScope}
              inventoryItems={items}
              onUpdateItem={handleUpdateItem}
              onRemoveItem={handleRemoveItem}
              onAddNewItem={handleAddNewItem}
              onUpdateDiscountScope={handleUpdateDiscountScope}
              formatCurrency={formatCurrency}
              calculateItemTotal={calcItemTotal}
              getCurrencySymbol={getCurrencySymbol}
            />

            {/* Totals + Notes/Terms */}
            <InvoiceV2TotalsPanel
              items={state.items}
              discountScope={state.discountScope}
              discount={state.discount}
              notes={state.notes}
              terms={state.terms}
              onUpdateDiscount={handleUpdateDiscount}
              onUpdateNotes={handleUpdateNotes}
              onUpdateTerms={handleUpdateTerms}
              formatCurrency={formatCurrency}
              getCurrencySymbol={getCurrencySymbol}
              calculateSubtotal={calcSubtotal}
              calculateTax={calcTax}
              calculateDiscount={calcDiscount}
              calculateTotal={calcTotal}
            />

            {/* Payment Section */}
            <InvoiceV2PaymentSection
              payment={state.payment}
              totalAmount={calcTotal()}
              onUpdatePayment={handleUpdatePayment}
              onAddPaymentMethod={handleAddPaymentMethod}
              onRemovePaymentMethod={handleRemovePaymentMethod}
              onUpdatePaymentMethod={handleUpdatePaymentMethod}
              formatCurrency={formatCurrency}
            />
          </>
        )}
      </div>

      <InvoiceV2Footer
        isSaving={isSaving}
        isEditMode={false}
        onCreateAndView={handleCreateAndView}
        onCreateAndNew={handleCreateAndNew}
        onCancel={handleCancel}
      />
    </InvoiceV2Modal>
  );
}
