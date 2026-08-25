import { jsPDF } from 'jspdf';
import autoTable from 'jspdf-autotable';

interface Column {
  headerName: string;
  field: string;
  width?: number;
  valueFormatter?: (params: { value: unknown }) => string;
}

interface Summary {
  totalAmount?: number;
  totalRecords?: number;
  averageAmount?: number;
}

interface Metadata {
  dateRange?: string;
  filters?: Record<string, unknown>;
}

interface ExportOptions {
  summary?: Summary | null;
  metadata?: Metadata;
}

declare module 'jspdf' {
  interface jsPDF {
    autoTable: (options: Record<string, unknown>) => void;
  }
}

export const exportToPDF = (
  data: Record<string, unknown>[],
  columns: Column[],
  title: string,
  filename: string = 'report.pdf',
  options: ExportOptions = {}
): void => {
  const doc = new jsPDF();
  const { summary = null, metadata = {} } = options;

  const pageWidth = doc.internal.pageSize.getWidth();
  const margin = 5;

  doc.setFillColor(30, 41, 59);
  doc.rect(0, 0, pageWidth, 25, 'F');

  doc.setTextColor(255, 255, 255);
  doc.setFontSize(14);
  doc.setFont('helvetica', 'bold');
  doc.text('Mini ERP', margin, 10);

  doc.setFontSize(10);
  doc.setFont('helvetica', 'normal');
  doc.text(title, margin, 18);

  doc.setTextColor(100, 100, 100);
  doc.setFontSize(7);
  const metadataY = 32;

  const timestamp = new Date().toLocaleString();
  doc.text(`Generated: ${timestamp}`, margin, metadataY);

  if (metadata.dateRange) {
    doc.text(`Period: ${metadata.dateRange}`, margin + 80, metadataY);
  }

  if (metadata.filters) {
    Object.entries(metadata.filters).forEach(([key, value], index) => {
      if (value) {
        doc.text(`${key}: ${value}`, margin, metadataY + 5 + (index * 4));
      }
    });
  }

  let startY = 42;
  if (summary) {
    doc.setFillColor(249, 250, 251);
    doc.rect(margin, startY - 2, pageWidth - (margin * 2), 15, 'F');

    doc.setTextColor(30, 41, 59);
    doc.setFontSize(8);
    doc.setFont('helvetica', 'bold');

    let summaryX = margin;
    if (summary.totalAmount !== undefined) {
      doc.text(`Total: ${formatCurrencyForExport(summary.totalAmount)}`, summaryX, startY + 5);
      summaryX += 50;
    }
    if (summary.totalRecords !== undefined) {
      doc.text(`Records: ${summary.totalRecords}`, summaryX, startY + 5);
      summaryX += 40;
    }
    if (summary.averageAmount !== undefined) {
      doc.text(`Average: ${formatCurrencyForExport(summary.averageAmount)}`, summaryX, startY + 5);
    }

    startY += 18;
  }

  const tableColumnHeaders = columns
    .filter(col => col.headerName && col.field !== 'actions')
    .map(col => col.headerName);

  const tableData = data.map(row => {
    return columns
      .filter(col => col.headerName && col.field !== 'actions')
      .map(col => {
        let value = row[col.field];
        if (col.field.includes('date') && value) {
          value = new Date(value as string | number | Date).toLocaleDateString();
        }
        else if (col.valueFormatter && typeof col.valueFormatter === 'function') {
          value = col.valueFormatter({ value });
        }
        return value;
      });
  });

  const columnStyles: Record<number, Record<string, string | number>> = {};
  columns
    .filter(col => col.headerName && col.field !== 'actions')
    .forEach((col, index) => {
      const style: Record<string, string | number> = {};

      if (col.width) {
        style.cellWidth = col.width as string | number;
      }

      if (col.field === 'amount' || col.field.includes('amount') || col.field.includes('total') ||
          col.field.includes('price') || col.field.includes('quantity')) {
        style.halign = 'right';
      }

      if (Object.keys(style).length > 0) {
        columnStyles[index] = style;
      }
    });

  autoTable(doc, {
    head: [tableColumnHeaders],
    body: tableData,
    startY: startY,
    styles: {
      fontSize: 7,
      cellPadding: 1,
      lineColor: [200, 200, 200],
      lineWidth: 0.1
    },
    headStyles: {
      fillColor: [59, 130, 246],
      textColor: [255, 255, 255],
      fontStyle: 'bold',
      halign: 'left',
      cellPadding: 2,
      fontSize: 7
    },
    alternateRowStyles: {
      fillColor: [248, 250, 252]
    },
    columnStyles: columnStyles,
    theme: 'grid',
    showHead: 'everyPage',
    margin: { top: margin, left: margin, right: margin, bottom: 15 },
    didDrawPage: (data: { cursor: { y: number }; pageNumber: number }) => {
      const internal = doc.internal as { getNumberOfPages?: () => number };
      const pageCount = internal.getNumberOfPages?.() || 1;
      doc.setFontSize(7);
      doc.setTextColor(150, 150, 150);
      doc.text(
        `Page ${data.pageNumber} of ${pageCount}`,
        pageWidth / 2,
        doc.internal.pageSize.height - 5,
        { align: 'center' }
      );
    }
  });

  doc.save(filename);
};

export const exportToExcel = (
  data: Record<string, unknown>[],
  columns: Column[],
  title: string,
  filename: string = 'report.csv'
): void => {
  const headers = columns
    .filter(col => col.headerName && col.field !== 'actions')
    .map(col => `"${col.headerName}"`)
    .join(',');

  const rows = data.map(row => {
    return columns
      .filter(col => col.headerName && col.field !== 'actions')
      .map(col => {
        let value = row[col.field];
        if (col.field.includes('date') && value) {
          value = new Date(value as string | number | Date).toLocaleDateString();
        }
        else if (col.valueFormatter && typeof col.valueFormatter === 'function') {
          value = col.valueFormatter({ value });
        }
        value = String(value || '').replace(/"/g, '""');
        return `"${value}"`;
      })
      .join(',');
  });

  const csvContent = [headers, ...rows].join('\n');
  const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });

  const link = document.createElement('a');
  const url = URL.createObjectURL(blob);
  link.setAttribute('href', url);
  link.setAttribute('download', filename);
  link.style.visibility = 'hidden';

  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
};

const formatCurrencyForExport = (value: number, currency: string = 'USD'): string => {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: currency,
    minimumFractionDigits: 2
  }).format(value || 0);
};
