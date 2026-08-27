/**
 * Ledger export utilities — CSV, PDF, Image, Print.
 * All export logic extracted from the LedgerTab component into pure functions.
 */

import toast from 'react-hot-toast';

import html2canvas from 'html2canvas';
import { jsPDF } from 'jspdf';

import type { SupplierTransaction } from '../types';

/** Column definitions used across all export formats. */
const EXPORT_HEADERS = ['Date', 'Type', 'Reference', 'Description', 'Debit', 'Credit', 'Balance'] as const;

interface ExportTotals {
  debit: number;
  credit: number;
  balance: number;
}

interface ExportRow {
  date: string;
  type: string;
  ref: string;
  description: string;
  debit: string;
  credit: string;
  balance: string;
}

/**
 * Prepares ledger data into a flat row format for all exporters.
 */
function prepareExportData(
  ledger: SupplierTransaction[],
  formatCurrency: (amount: number | string | null | undefined) => string,
): { rows: ExportRow[]; totals: ExportTotals } {
  const totals: ExportTotals = ledger.reduce(
    (acc, item) => ({
      debit: acc.debit + (item.debit || 0),
      credit: acc.credit + (item.credit || 0),
      balance: 0,
    }),
    { debit: 0, credit: 0, balance: 0 },
  );
  totals.balance = totals.debit - totals.credit;

  const rows: ExportRow[] = ledger.map((item) => ({
    date: item.transaction_date ? new Date(item.transaction_date).toLocaleDateString() : '',
    type: item.transaction_type || '',
    ref: item.reference_no || '',
    description: item.description || '',
    debit: item.debit ? formatCurrency(item.debit) : '',
    credit: item.credit ? formatCurrency(item.credit) : '',
    balance: formatCurrency(item.balance || 0),
  }));

  return { rows, totals };
}

/**
 * Build a sanitized filename-friendly customer name.
 */
function sanitizeCustomerName(name: string): string {
  return name.replace(/\s+/g, '_');
}

/**
 * Get today's date as YYYY-MM-DD.
 */
function todayStr(): string {
  return new Date().toISOString().split('T')[0];
}

/* ── Exported Functions ─────────────────────────────────────────── */

/**
 * Export ledger to CSV file.
 */
export function exportToCSV(
  ledger: SupplierTransaction[],
  customerName?: string,
  formatCurrency?: (amount: number | string | null | undefined) => string,
): void {
  if (!ledger || ledger.length === 0) {
    toast.error('No data to export');
    return;
  }

  const fmt = formatCurrency || ((v: number | string | null | undefined) => String(v));
  const { rows, totals } = prepareExportData(ledger, fmt);

  const csvRows = rows.map((r) => [r.date, r.type, r.ref, r.description, r.debit, r.credit, r.balance]);
  csvRows.push(['', '', '', 'TOTALS', fmt(totals.debit), fmt(totals.credit), fmt(totals.balance)]);

  const csvContent = [
    `Customer Ledger - ${customerName || 'Customer'}`,
    `Generated: ${new Date().toLocaleString()}`,
    '',
    EXPORT_HEADERS.join(','),
    ...csvRows.map((row) => row.map((cell) => `"${cell}"`).join(',')),
  ].join('\n');

  const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
  const link = document.createElement('a');
  link.href = URL.createObjectURL(blob);
  const name = sanitizeCustomerName(customerName || 'customer');
  link.download = `ledger_${name}_${todayStr()}.csv`;
  link.click();
  toast.success('CSV exported successfully');
}

/**
 * Export ledger to PDF using jsPDF.
 */
export async function exportToPDF(
  ledger: SupplierTransaction[],
  customerName?: string,
  formatCurrency?: (amount: number | string | null | undefined) => string,
): Promise<void> {
  if (!ledger || ledger.length === 0) {
    toast.error('No data to export');
    return;
  }

  try {
    toast.loading('Generating PDF...', { id: 'pdf-export' });

    const fmt = formatCurrency || ((v: number | string | null | undefined) => String(v));
    const pdf = new jsPDF('l', 'mm', 'a4');
    const pageWidth = pdf.internal.pageSize.getWidth();

    // Title
    pdf.setFontSize(16);
    pdf.setFont('helvetica', 'bold');
    pdf.text(`Customer Ledger - ${customerName || 'Customer'}`, 14, 15);

    pdf.setFontSize(10);
    pdf.setFont('helvetica', 'normal');
    pdf.text(`Generated: ${new Date().toLocaleString()}`, 14, 22);

    // Table column widths
    const colWidths = [25, 25, 30, 80, 30, 30, 30];
    const startX = 14;
    let startY = 32;

    // Draw header
    pdf.setFillColor(240, 240, 240);
    pdf.rect(startX, startY - 5, pageWidth - 28, 8, 'F');
    pdf.setFontSize(9);
    pdf.setFont('helvetica', 'bold');
    let xPos = startX;
    EXPORT_HEADERS.forEach((header, i) => {
      pdf.text(header, xPos + 2, startY);
      xPos += colWidths[i];
    });

    // Draw data rows
    pdf.setFont('helvetica', 'normal');
    pdf.setFontSize(8);
    startY += 8;

    ledger.forEach((item) => {
      if (startY > 190) {
        pdf.addPage();
        startY = 20;
      }

      xPos = startX;
      const row = [
        item.transaction_date ? new Date(item.transaction_date).toLocaleDateString() : '',
        item.transaction_type || '',
        item.reference_no || '',
        (item.description || '').substring(0, 40),
        item.debit ? fmt(item.debit) : '',
        item.credit ? fmt(item.credit) : '',
        fmt(item.balance || 0),
      ];

      row.forEach((cell) => {
        pdf.text(String(cell), xPos + 2, startY);
        xPos += colWidths[row.indexOf(cell)];
      });

      startY += 6;
    });

    // Totals row
    const totals: ExportTotals = ledger.reduce(
      (acc, item) => ({ debit: acc.debit + (item.debit || 0), credit: acc.credit + (item.credit || 0), balance: 0 }),
      { debit: 0, credit: 0, balance: 0 },
    );
    totals.balance = totals.debit - totals.credit;

    startY += 4;
    pdf.setFont('helvetica', 'bold');
    pdf.setFillColor(245, 245, 245);
    pdf.rect(startX, startY - 5, pageWidth - 28, 8, 'F');

    xPos = startX;
    const totalsRow = ['', '', '', 'TOTALS', fmt(totals.debit), fmt(totals.credit), fmt(totals.balance)];
    totalsRow.forEach((cell) => {
      pdf.text(String(cell), xPos + 2, startY);
      xPos += colWidths[totalsRow.indexOf(cell)];
    });

    const name = sanitizeCustomerName(customerName || 'customer');
    pdf.save(`ledger_${name}_${todayStr()}.pdf`);
    toast.success('PDF exported successfully', { id: 'pdf-export' });
  } catch (error) {
    console.error('PDF export error:', error);
    toast.error('Failed to export PDF', { id: 'pdf-export' });
  }
}

/**
 * Export ledger to PNG image using html2canvas.
 */
export async function exportToImage(ledgerRef: HTMLElement | null): Promise<void> {
  if (!ledgerRef) {
    toast.error('No content to export');
    return;
  }

  try {
    toast.loading('Generating image...', { id: 'image-export' });

    // Wait for any pending renders
    await new Promise((resolve) => setTimeout(resolve, 100));

    const canvas = await html2canvas(ledgerRef, {
      scale: 2,
      useCORS: true,
      logging: false,
      backgroundColor: '#ffffff',
      allowTaint: true,
      foreignObjectRendering: false,
    });

    const link = document.createElement('a');
    link.download = `ledger_${new Date().toISOString().split('T')[0]}.png`;
    link.href = canvas.toDataURL('image/png');
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    toast.success('Image exported successfully', { id: 'image-export' });
  } catch (error) {
    console.error('Image export error:', error);
    toast.error('Failed to export image. Try using Print instead.', { id: 'image-export' });
  }
}

/**
 * Print ledger via browser print dialog.
 */
export function handlePrint(
  ledger: SupplierTransaction[],
  customerName?: string,
  formatCurrency?: (amount: number | string | null | undefined) => string,
): void {
  if (!ledger || ledger.length === 0) return;

  const fmt = formatCurrency || ((v: number | string | null | undefined) => String(v));
  const { rows, totals } = prepareExportData(ledger, fmt);

  const printWindow = window.open('', '_blank');
  if (!printWindow) return;

  const formattedRows = rows
    .map(
      (r) => `
    <tr>
      <td>${r.date}</td>
      <td><span class="transaction-type ${r.type.toLowerCase()}">${r.type}</span></td>
      <td>${r.ref}</td>
      <td>${r.description}</td>
      <td class="text-right">${r.debit}</td>
      <td class="text-right">${r.credit}</td>
      <td class="text-right">${r.balance}</td>
    </tr>`,
    )
    .join('');

  printWindow.document.write(`
    <html>
      <head>
        <title>Customer Ledger - ${customerName || 'Customer'}</title>
        <style>
          body { font-family: Arial, sans-serif; padding: 20px; }
          h1 { font-size: 18px; margin-bottom: 5px; }
          .print-date { font-size: 12px; color: #666; margin-bottom: 20px; }
          table { width: 100%; border-collapse: collapse; margin-top: 10px; }
          th, td { border: 1px solid #ddd; padding: 8px; text-align: left; font-size: 12px; }
          th { background-color: #f5f5f5; font-weight: 600; }
          .text-right { text-align: right; }
          .totals-row { font-weight: bold; background-color: #f9f9f9; }
          .transaction-type { padding: 2px 8px; border-radius: 4px; font-size: 11px; }
          .transaction-type.invoice { background: #e0f2fe; color: #0369a1; }
          .transaction-type.payment { background: #dcfce7; color: #166534; }
        </style>
      </head>
      <body>
        <h1>Customer Ledger - ${customerName || 'Customer'}</h1>
        <div class="print-date">Generated: ${new Date().toLocaleString()}</div>
        <table>
          <thead>
            <tr>
              <th>Date</th>
              <th>Type</th>
              <th>Reference</th>
              <th>Description</th>
              <th class="text-right">Debit</th>
              <th class="text-right">Credit</th>
              <th class="text-right">Balance</th>
            </tr>
          </thead>
          <tbody>
            ${formattedRows}
            <tr class="totals-row">
              <td colspan="4"><strong>TOTALS</strong></td>
              <td class="text-right"><strong>${fmt(totals.debit)}</strong></td>
              <td class="text-right"><strong>${fmt(totals.credit)}</strong></td>
              <td class="text-right"><strong>${fmt(totals.balance)}</strong></td>
            </tr>
          </tbody>
        </table>
      </body>
    </html>
  `);
  printWindow.document.close();
  printWindow.print();
}
