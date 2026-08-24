/**
 * LedgerTab — AG-Grid for ledger entries with export toolbar and totals sidebar.
 * Entries are grouped by invoice for visual clarity.
 */

import { useMemo, useState, memo, useRef, useCallback } from 'react';

import MiniERPGrid from '../../components/common/MiniERPGrid';
import {
  FileText,
  FileSpreadsheet,
  Download,
  Image,
  Printer,
  ChevronDown,
  ChevronRight,
} from 'lucide-react';

import { calculateLedgerTotals, formatDateString } from '../../utils/customerCalculations';
import { groupLedgerByInvoice } from '../../utils/ledgerGrouping';
import type { LedgerTabProps, LedgerColDef } from '../../types';
import type { InvoiceGroup } from '../../utils/ledgerGrouping';
import { exportToCSV, exportToPDF, exportToImage, handlePrint } from '../../utils/ledgerExport';

interface GroupedRow {
  _id: string;
  _isGroupHeader: boolean;
  _isChild: boolean;
  _groupId?: string;
  transaction_date: string;
  transaction_type: string;
  reference_no: string;
  description: string;
  debit: number;
  credit: number;
  balance: number;
  linked_invoice_no?: string;
}

function LedgerTab({ ledger, loading, customerName, formatCurrency, invoices }: LedgerTabProps) {
  const ledgerRef = useRef<HTMLDivElement>(null);
  const [expandedGroups, setExpandedGroups] = useState<Set<string>>(new Set());

  const returnedInvoiceNos = useMemo(() => {
    if (!invoices) return undefined;
    const returned = invoices
      .filter((inv) => inv.status === 'Returned')
      .map((inv) => inv.invoice_no);
    return returned.length > 0 ? new Set(returned) : undefined;
  }, [invoices]);

  const totals = useMemo(() => calculateLedgerTotals(ledger, returnedInvoiceNos), [ledger, returnedInvoiceNos]);

  const groupedNodes = useMemo(() => groupLedgerByInvoice(ledger), [ledger]);

  const rowData = useMemo(() => {
    const rows: GroupedRow[] = [];
    for (const node of groupedNodes) {
      if (node.type === 'ungrouped') {
        rows.push({
          _id: `u-${node.entry.id}`,
          _isGroupHeader: false,
          _isChild: false,
          transaction_date: node.entry.transaction_date,
          transaction_type: node.entry.transaction_type,
          reference_no: node.entry.reference_no || '',
          description: node.entry.description || '',
          debit: node.entry.debit,
          credit: node.entry.credit,
          balance: node.entry.balance,
        });
      } else {
        const group = node as InvoiceGroup;
        const gid = `g-${group.invoice.reference_no}`;
        rows.push({
          _id: gid,
          _isGroupHeader: true,
          _isChild: false,
          _groupId: gid,
          transaction_date: group.invoice.transaction_date,
          transaction_type: group.invoice.transaction_type,
          reference_no: group.invoice.reference_no || '',
          description: `${group.children.length} payment${group.children.length !== 1 ? 's' : ''} — Balance: ${group.balance.toFixed(2)}`,
          debit: group.invoice.debit,
          credit: group.totalPaid,
          balance: group.balance,
        });
        if (expandedGroups.has(gid)) {
          for (const child of group.children) {
            rows.push({
              _id: `c-${child.id}`,
              _isGroupHeader: false,
              _isChild: true,
              _groupId: gid,
              transaction_date: child.transaction_date,
              transaction_type: child.transaction_type,
              reference_no: child.reference_no || '',
              description: child.description || '',
              debit: child.debit,
              credit: child.credit,
              balance: child.balance,
            });
          }
        }
      }
    }
    return rows;
  }, [groupedNodes, expandedGroups]);

  const toggleGroup = useCallback((gid: string) => {
    setExpandedGroups(prev => {
      const next = new Set(prev);
      if (next.has(gid)) next.delete(gid);
      else next.add(gid);
      return next;
    });
  }, []);

  const columnDefs = useMemo<LedgerColDef[]>(
    () => [
      {
        headerName: '',
        field: '_isGroupHeader',
        width: 36,
        sortable: false,
        filter: false,
        resizable: false,
        cellRenderer: (params: any) => {
          if (params.data?._isChild) {
            return <span style={{ paddingLeft: 8, color: '#9ca3af' }}>—</span>;
          }
          if (params.data?._isGroupHeader) {
            const gid = params.data._groupId;
            const isExpanded = expandedGroups.has(gid);
            return (
              <span
                style={{ cursor: 'pointer', display: 'inline-flex', alignItems: 'center', gap: 2 }}
                onClick={(e) => { e.stopPropagation(); toggleGroup(gid); }}
              >
                {isExpanded ? <ChevronDown size={14} /> : <ChevronRight size={14} />}
              </span>
            );
          }
          return null;
        },
      },
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
        cellRenderer: (params: any) => (
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
        valueFormatter: (params) => formatCurrency(params.value || 0),
      },
    ],
    [formatCurrency, expandedGroups, toggleGroup],
  );

  const getRowClass = useCallback((params: any) => {
    if (params.data?._isGroupHeader) return 'ledger-group-header';
    if (params.data?._isChild) return 'ledger-child-row';
    return '';
  }, []);

  const handleCSV = useCallback(() => {
    exportToCSV(ledger, customerName, formatCurrency);
  }, [ledger, customerName, formatCurrency]);

  const handlePDF = useCallback(() => {
    exportToPDF(ledger, customerName, formatCurrency);
  }, [ledger, customerName, formatCurrency]);

  const handleImage = useCallback(() => {
    exportToImage(ledgerRef.current);
  }, []);

  const handlePrintClick = useCallback(() => {
    handlePrint(ledger, customerName, formatCurrency);
  }, [ledger, customerName, formatCurrency]);

  const gridOptions = useMemo(() => ({
    getRowClass,
    rowSelection: undefined,
    suppressRowClickSelection: true,
  }), [getRowClass]);

  return (
    <div className="ledger-tab">
      <div className="ledger-toolbar">
        <div className="ledger-title">
          <FileText size={18} />
          <span>Account Ledger</span>
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
              rowData={rowData}
              columnDefs={columnDefs as any}
              paginationPageSize={10}
              paginationPageSizeSelector={[10, 15, 25, 50]}
              gridOptions={gridOptions}
              getRowId={(params: any) => params.data._id}
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
