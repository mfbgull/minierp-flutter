import { useState, useEffect } from 'react';
import { useQuery } from '@tanstack/react-query';
import MiniERPGrid from '../../components/common/MiniERPGrid';
import {
  Users,
  FileText,
  DollarSign,
  Calendar,
  Download,
  Filter,
  X,
  Receipt,
  Hash,
  TrendingUp
} from 'lucide-react';

import Button from '../../components/common/Button';
import DateRangePicker from '../../components/common/DateRangePicker';
import type { DateRangeFilter } from '../../types';
import { useSettings } from '../../context/SettingsContext';
import api from '../../utils/api';
import { exportToPDF, exportToExcel } from '../../utils/exportUtils';
import './CustomerStatementsReport.css';

interface Customer {
  id: number;
  customer_name: string;
}

interface StatementRecord {
  id?: number;
  customer_name: string;
  customer_code?: string;
  opening_balance?: number;
  total_debits?: number;
  total_credits?: number;
  closing_balance?: number;
  invoice_count?: number;
  total_amount?: number;
  paid_amount?: number;
  balance?: number;
  last_payment_date?: string;
}

interface StatementData {
  statements?: StatementRecord[];
}

export default function CustomerStatementsReport() {
  const [dateRange, setDateRange] = useState<DateRangeFilter>({
    fromDate: new Date(new Date().setMonth(new Date().getMonth() - 3)).toISOString().split('T')[0],
    toDate: new Date().toISOString().split('T')[0]
  });
  const [customerId, setCustomerId] = useState('');
  const [showFilters, setShowFilters] = useState(false);
  const [selectedStatement, setSelectedStatement] = useState<StatementRecord | null>(null);
  const [showDetailModal, setShowDetailModal] = useState(false);
  const { formatCurrency } = useSettings();

  useEffect(() => {
    const handleEsc = (event: KeyboardEvent) => { if (event.key === 'Escape') setShowDetailModal(false); };
    if (showDetailModal) document.addEventListener('keydown', handleEsc);
    return () => document.removeEventListener('keydown', handleEsc);
  }, [showDetailModal]);

  const handleCardClick = (statement: StatementRecord) => { setSelectedStatement(statement); setShowDetailModal(true); };

  const { data: customers = [] } = useQuery<Customer[]>({
    queryKey: ['customers'], queryFn: async () => { const r = await api.get('/customers'); return r.data.data || []; }
  });

  const { data: reportData, isLoading, refetch } = useQuery<StatementData>({
    queryKey: ['customerStatements', dateRange, customerId],
    queryFn: async () => {
      const params = new URLSearchParams();
      params.append('fromDate', dateRange.fromDate); params.append('toDate', dateRange.toDate);
      if (customerId) params.append('customerId', customerId);
      const r = await api.get(`/reports/customer-statements?${params}`); return r.data.data;
    }
  });

  const handleFilterSubmit = (e: React.FormEvent) => { e.preventDefault(); refetch(); };

  const handleExport = (format = 'pdf') => {
    if (!reportData?.statements) return;
    const cols = [
      { headerName: 'Customer Name', field: 'customer_name' },
      { headerName: 'Customer Code', field: 'customer_code' },
      { headerName: 'Opening Balance', field: 'opening_balance', valueFormatter: (p: { value: number }) => formatCurrency(p.value || 0) },
      { headerName: 'Total Debits', field: 'total_debits', valueFormatter: (p: { value: number }) => formatCurrency(p.value || 0) },
      { headerName: 'Total Credits', field: 'total_credits', valueFormatter: (p: { value: number }) => formatCurrency(p.value || 0) },
      { headerName: 'Closing Balance', field: 'closing_balance', valueFormatter: (p: { value: number }) => formatCurrency(p.value || 0) }
    ];
    if (format === 'pdf') exportToPDF(reportData.statements as unknown as Record< string,unknown >[], cols, 'Customer Statements Report', `customer-statements-${new Date().toISOString().split('T')[0]}.pdf`);
    else exportToExcel(reportData.statements as unknown as Record< string,unknown >[], cols, 'Customer Statements Report', `customer-statements-${new Date().toISOString().split('T')[0]}.csv`);
  };

  const columnDefs = [
    { headerName: 'Customer Name', field: 'customer_name', filter: true, flex: 1 },
    { headerName: 'Customer Code', field: 'customer_code', filter: true, width: 140 },
    { headerName: 'Opening Balance', field: 'opening_balance', filter: 'agNumberColumnFilter', width: 150, valueFormatter: (p: { value: number }) => formatCurrency(p.value || 0), cellClass: 'amount-cell' },
    { headerName: 'Total Debits', field: 'total_debits', filter: 'agNumberColumnFilter', width: 140, valueFormatter: (p: { value: number }) => formatCurrency(p.value || 0), cellClass: 'amount-cell' },
    { headerName: 'Total Credits', field: 'total_credits', filter: 'agNumberColumnFilter', width: 140, valueFormatter: (p: { value: number }) => formatCurrency(p.value || 0), cellClass: 'amount-cell' },
    { headerName: 'Closing Balance', field: 'closing_balance', filter: 'agNumberColumnFilter', width: 150, valueFormatter: (p: { value: number }) => formatCurrency(p.value || 0), cellClass: 'amount-cell' }
  ];

  return (
    <div className="customer-statements-report">
      <div className="page-header">
        <div><h1>Customer Statements Report</h1><p className="page-subtitle">Detailed account statements for customers</p></div>
      </div>
      <div className="report-controls">
        <Button variant="secondary" onClick={() => setShowFilters(!showFilters)} className="filter-toggle" type="button"><Filter size={18} />{showFilters ? 'Hide Filters' : 'Show Filters'}</Button>
        <div className="export-buttons">
          <Button variant="secondary" onClick={() => handleExport('pdf')} className="export-btn" type="button"><Download size={18} /> Export PDF</Button>
          <Button variant="secondary" onClick={() => handleExport('excel')} className="export-btn" type="button"><Download size={18} /> Export Excel</Button>
        </div>
      </div>
      {showFilters && (
        <form onSubmit={handleFilterSubmit} className="report-filters">
          <div className="filter-row">
            <DateRangePicker fromDate={dateRange.fromDate} toDate={dateRange.toDate}
              onFromDateChange={(d: string) => setDateRange(p => ({ ...p, fromDate: d }))}
              onToDateChange={(d: string) => setDateRange(p => ({ ...p, toDate: d }))} />
            <div className="filter-group"><label>Customer</label>
              <select value={customerId} onChange={(e: React.ChangeEvent<HTMLSelectElement>) => setCustomerId(e.target.value)} className="filter-select">
                <option value="">All Customers</option>
                {customers.map(c => <option key={c.id} value={c.id}>{c.customer_name}</option>)}
              </select>
            </div>
            <Button type="submit" variant="primary" className="apply-filters-btn">Apply Filters</Button>
          </div>
        </form>
      )}
      <div className="report-content">
        {isLoading ? <div className="loading"><div className="spinner"></div></div>
        : reportData?.statements && reportData.statements.length > 0 ? <>
          <MiniERPGrid
            wrapperClassName="desktop-view ag-grid-container"
            rowData={reportData.statements}
            columnDefs={columnDefs as any}
            paginationPageSize={20}
            paginationPageSizeSelector={[10, 20, 50, 100]}
          />
          <div className="mobile-statements-list">
            {reportData.statements.map((statement, index) => (
              <div key={`${statement.id || statement.customer_name}-${index}`} className="statement-card"
                onClick={() => handleCardClick(statement)} role="button" tabIndex={0}
                onKeyDown={(e: React.KeyboardEvent) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); handleCardClick(statement); } }}>
                <div className="statement-card-content">
                  <h3 className="statement-customer">{statement.customer_name}</h3>
                  <span className="statement-balance">{formatCurrency(statement.balance || 0)}</span>
                </div>
              </div>
            ))}
          </div>
        </> : <div className="no-data"><Users size={48} /><h3>No customer statement data found</h3><p>Try adjusting your filters to see customer statement data.</p></div>}
      </div>
      {showDetailModal && selectedStatement && (
        <div className="statement-modal-overlay" onClick={() => setShowDetailModal(false)} role="dialog" aria-modal="true">
          <div className="statement-modal" onClick={(e: React.MouseEvent) => e.stopPropagation()}>
            <div className="statement-modal-header">
              <h2 className="statement-modal-title">{selectedStatement.customer_name}</h2>
              <button type="button" className="statement-modal-close" onClick={() => setShowDetailModal(false)}><X size={24} /></button>
            </div>
            <div className="statement-modal-content">
              <div className="statement-detail-section">
                <div className="statement-details-grid">
                  <div className="statement-detail-item"><span className="statement-detail-label"><Hash size={14} /> Customer Code</span><span className="statement-detail-value">{selectedStatement.customer_code || '-'}</span></div>
                  <div className="statement-detail-item"><span className="statement-detail-label"><Receipt size={14} /> Invoice Count</span><span className="statement-detail-value">{selectedStatement.invoice_count || 0}</span></div>
                  <div className="statement-detail-item"><span className="statement-detail-label"><DollarSign size={14} /> Total Amount</span><span className="statement-detail-value">{formatCurrency(selectedStatement.total_amount || 0)}</span></div>
                  <div className="statement-detail-item"><span className="statement-detail-label"><DollarSign size={14} /> Paid Amount</span><span className="statement-detail-value">{formatCurrency(selectedStatement.paid_amount || 0)}</span></div>
                  <div className="statement-detail-item"><span className="statement-detail-label"><TrendingUp size={14} /> Balance</span><span className="statement-detail-value">{formatCurrency(selectedStatement.balance || 0)}</span></div>
                  <div className="statement-detail-item"><span className="statement-detail-label"><Calendar size={14} /> Last Payment</span><span className="statement-detail-value">{selectedStatement.last_payment_date ? new Date(selectedStatement.last_payment_date).toLocaleDateString() : '-'}</span></div>
                </div>
              </div>
            </div>
            <div className="statement-modal-actions">
              <button type="button" className="statement-action-btn statement-action-secondary" onClick={() => setShowDetailModal(false)}>Close</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
