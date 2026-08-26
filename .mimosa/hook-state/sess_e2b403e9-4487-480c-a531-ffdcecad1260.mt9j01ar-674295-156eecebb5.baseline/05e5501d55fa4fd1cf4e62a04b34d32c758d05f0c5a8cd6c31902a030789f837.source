/**
 * LedgerTab — AG-Grid for supplier ledger entries with export toolbar and totals sidebar.
 */

import { useMemo, memo, useCallback, useRef } from 'react';

import { ColDef } from 'ag-grid-community';
import {
  FileText,
  FileSpreadsheet,
  Download,
  Image,
  Printer,
} from 'lucide-react';

import MiniERPGrid from '../../components/common/MiniERPGrid';
import type { SupplierLedger, SupplierLedgerTabProps } from '../../types';
import { formatAsCurrency, formatDateString } from '../../utils/customerCalculations';
import { exportToCSV, exportToPDF, exportToImage, handlePrint } from '../../utils/ledgerExport';

function LedgerTab({ ledger, loading, supplierName, formatCurrency }: SupplierLedgerTabProps) {
  const ledgerRef = useRef<HTMLDivElement>(null);

  const totals = useMemo(() => {
    const debit = ledger.reduce((sum, entry) => sum + (entry.debit || 0), 0);
    const credit = ledger.reduce((sum, entry) => sum + (entry.credit || 0), 0);
    const balance = ledger.length > 0 ? ledger[ledger.length - 1].balance : 0;
    return { debit, credit, balance };
  }, [ledger]);

  const columnDefs = useMemo<ColDef<SupplierLedger>[]>(
    () => [
      {
        headerName: 'Date',
        field: 'transaction_date',
        filter: true,
        width: 110,
        valueFormatter: (params) => formatDateString(params.value),
      },
      {
        headerName: 'Type',
        field: 'transaction_type',
        filter: true,
        width: 110,
        cellRenderer: (params) => (
          <span className={`transaction-type ${params.value?.toLowerCase()}`}>
            {params.value}
          </span>
        ),
      },
      {
        headerName: 'Reference',
        field: 'reference_no',
        filter: true,
        width: 130,
      },
      {
        headerName: 'Description',
        field: 'description',
        filter: true,
        flex: 1,
      },
      {
        headerName: 'Debit',
        field: 'debit',
        filter: 'agNumberColumnFilter',
        width: 110,
        valueFormatter: (params) => (params.value ? formatCurrency(params.value) : ''),
      },
      {
        headerName: 'Credit',
        field: 'credit',
        filter: 'agNumberColumnFilter',
        width: 110,
        valueFormatter: (params) => (params.value ? formatCurrency(params.value) : ''),
      },
      {
        headerName: 'Balance',
        field: 'balance',
        filter: 'agNumberColumnFilter',
        width: 120,
        valueFormatter: (params) => formatAsCurrency(params.value || 0),
      },
    ],
    [formatCurrency],
  );

  const handleCSV = useCallback(() => {
    exportToCSV(ledger, supplierName, formatCurrency);
  }, [ledger, supplierName, formatCurrency]);

  const handlePDF = useCallback(() => {
    exportToPDF(ledger, supplierName, formatCurrency);
  }, [ledger, supplierName, formatCurrency]);

  const handleImage = useCallback(() => {
    exportToImage(ledgerRef.current);
  }, []);

  const handlePrintClick = useCallback(() => {
    handlePrint(ledger, supplierName, formatCurrency);
  }, [ledger, supplierName, formatCurrency]);

  return (
    <div className="ledger-tab">
      <div className="ledger-toolbar">
        <div className="ledger-title">
          <FileText size={18} />
          <span>Supplier Ledger</span>
        </div>
        <div className="ledger-actions">
          <button className="export-btn" onClick={handleCSV} title="Export to CSV">
            <FileSpreadsheet size={16} />
            <span>CSV</span>
          </button>
          <button className="export-btn" onClick={handlePDF} title="Export to PDF">
            <Download size={16} />
            <span>PDF</span>
          </button>
          <button className="export-btn" onClick={handleImage} title="Export to Image">
            <Image size={16} />
            <span>Image</span>
          </button>
          <button className="export-btn" onClick={handlePrintClick} title="Print">
            <Printer size={16} />
            <span>Print</span>
          </button>
        </div>
      </div>

      {loading ? (
        <div className="loading">
          <div className="spinner" />
        </div>
      ) : (
        <div ref={ledgerRef}>
          <div className="ledger-content">
            <MiniERPGrid
              wrapperClassName="ledger-grid"
              containerStyle={{ height: 350 }}
              rowData={ledger}
              columnDefs={columnDefs}
              paginationPageSize={10}
              paginationPageSizeSelector={[10, 15, 25, 50]}
            />

            <div className="ledger-totals">
              <div className="totals-grid">
                <div className="total-item">
                  <span className="total-label">Total Debit</span>
                  <span className="total-value debit">{totals.debit.toFixed(2)}</span>
                </div>
                <div className="total-item">
                  <span className="total-label">Total Credit</span>
                  <span className="total-value credit">{totals.credit.toFixed(2)}</span>
                </div>
                <div className="total-item">
                  <span className="total-label">Current Balance</span>
                  <span className={`total-value balance ${totals.balance > 0 ? 'positive' : 'zero'}`}>
                    {totals.balance.toFixed(2)}
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

export default memo(LedgerTab);
