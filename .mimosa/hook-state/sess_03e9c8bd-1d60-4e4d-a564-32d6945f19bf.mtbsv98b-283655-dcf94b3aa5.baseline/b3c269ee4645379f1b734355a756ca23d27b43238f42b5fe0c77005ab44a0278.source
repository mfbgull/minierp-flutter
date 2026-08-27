import toast from 'react-hot-toast';

import { createRoot } from 'react-dom/client';

import PaymentReceiptA4 from './PaymentReceiptA4';
import ThermalPaymentReceipt from './ThermalPaymentReceipt';
import thermalStyles from './ThermalPaymentReceipt.css?inline';
import api from '../../utils/api';

interface ReceiptData {
  payment: {
    id: number; payment_no: string; payment_date: string; amount: number;
    payment_method: string; reference_no: string; notes: string;
  };
  customer: { name: string; address: string; phone: string; email: string };
  entityType?: 'customer' | 'supplier';
  balance: { previous_balance: number; payment_amount: number; current_balance: number };
  allocations: { invoice_id: number; invoice_no: string; amount: number }[];
  company: { name: string; address: string; phone: string; email: string; tax_id: string };
}

interface UsePaymentPrintResult {
  fetchReceiptData: (paymentId: number) => Promise<ReceiptData>;
  printA4: (data: ReceiptData) => void;
  printThermal: (data: ReceiptData) => void;
}

async function fetchReceiptData(paymentId: number): Promise<ReceiptData> {
  const response = await api.get(`/payments/${paymentId}/receipt`);
  if (!response.data.success) throw new Error(response.data.error || 'Failed to fetch receipt data');
  const data = response.data.data;
  // Supplier payments come back under a `supplier` key; normalize so the receipt
  // components always receive `customer`.
  return {
    ...data,
    entityType: data.supplier ? 'supplier' : 'customer',
    customer: data.customer || data.supplier,
  };
}

function printA4(data: ReceiptData): void {
  const printWindow = window.open('', '_blank', 'width=800,height=900');
  if (!printWindow) {
    toast.error('Please allow popups to print receipts');
    return;
  }

  printWindow.document.write(`
    <!DOCTYPE html>
    <html>
      <head>
        <title>Receipt ${data.payment.payment_no}</title>
        <style>
          @page { size: A4; margin: 15mm 20mm; }
          body { margin: 0; padding: 0; background: #fff; font-family: 'Inter', sans-serif; }
          * { box-sizing: border-box; }
        </style>
        <link rel="preconnect" href="https://fonts.googleapis.com">
        <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap" rel="stylesheet">
      </head>
      <body>
        <div id="print-root"></div>
      </body>
    </html>
  `);
  printWindow.document.close();

  const rootEl = printWindow.document.getElementById('print-root');
  if (rootEl) {
    const root = createRoot(rootEl);
    root.render(
      <PaymentReceiptA4
        payment={data.payment}
        customer={data.customer}
        entityType={data.entityType}
        balance={data.balance}
        allocations={data.allocations}
        company={data.company}
      />
    );

    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        printWindow.print();
        printWindow.close();
      });
    });
  }
}

function printThermal(data: ReceiptData): void {
  const printWindow = window.open('', '_blank', 'width=400,height=600');
  if (!printWindow) {
    toast.error('Please allow popups to print receipts');
    return;
  }

  printWindow.document.write(`
    <!DOCTYPE html>
    <html>
      <head>
        <title>Receipt ${data.payment.payment_no}</title>
        <style>
          @page { size: 80mm 297mm; margin: 0; }
          body { margin: 0; padding: 0; background: #fff; width: 80mm; }
          * { box-sizing: border-box; }
        </style>
        <style>${thermalStyles}</style>
      </head>
      <body>
        <div id="thermal-print-root"></div>
      </body>
    </html>
  `);
  printWindow.document.close();

  const rootEl = printWindow.document.getElementById('thermal-print-root');
  if (rootEl) {
    const root = createRoot(rootEl);
    root.render(
      <ThermalPaymentReceipt
        payment={data.payment}
        customer={data.customer}
        entityType={data.entityType}
        balance={data.balance}
        allocations={data.allocations}
        company={data.company}
      />
    );

    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        printWindow.print();
        printWindow.close();
      });
    });
  }
}

/**
 * Hook providing print utility functions for payment receipts.
 * Fetches receipt data from the API and opens print windows.
 */
export function usePaymentPrint(): UsePaymentPrintResult {
  return { fetchReceiptData, printA4, printThermal };
}
