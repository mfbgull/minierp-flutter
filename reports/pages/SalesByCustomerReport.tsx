import { useState, useEffect, useRef } from 'react';
import { useQuery } from '@tanstack/react-query';
import MiniERPGrid from '../../components/common/MiniERPGrid';
import {
  Users,
  TrendingUp as TrendingUpIcon,
  FileText,
  DollarSign,
  Calendar,
  Download,
  Filter,
  X,
  Mail,
  Phone,
  Receipt,
  Package,
  Clock
} from 'lucide-react';

import Button from '../../components/common/Button';
import DateRangePicker from '../../components/common/DateRangePicker';
import type { DateRangeFilter } from '../../types';
import { useSettings } from '../../context/SettingsContext';
import api from '../../utils/api';
import { exportToPDF, exportToExcel } from '../../utils/exportUtils';
import './SalesReports.css';

interface CustomerSalesRecord {
  customer_code?: string;
  customer_name: string;
  email?: string;
  phone?: string;
  total_invoices?: number;
  total_sales?: number;
  total_items?: number;
  average_order_value?: number;
  last_purchase_date?: string;
}

export default function SalesByCustomerReport() {
  const [dateRange, setDateRange] = useState<DateRangeFilter>({
    fromDate: new Date(new Date().setMonth(new Date().getMonth() - 1)).toISOString().split('T')[0],
    toDate: new Date().toISOString().split('T')[0]
  });
  const [showFilters, setShowFilters] = useState(false);
  const [selectedCustomer, setSelectedCustomer] = useState<CustomerSalesRecord | null>(null);
  const [showDetailModal, setShowDetailModal] = useState(false);
  const modalRef = useRef<HTMLDivElement>(null);
  const { formatCurrency } = useSettings();

  useEffect(() => {
    const handleEsc = (event: KeyboardEvent) => { if (event.key === 'Escape') setShowDetailModal(false); };
    if (showDetailModal) document.addEventListener('keydown', handleEsc);
    return () => document.removeEventListener('keydown', handleEsc);
  }, [showDetailModal]);

  const handleCardClick = (customer: CustomerSalesRecord) => { setSelectedCustomer(customer); setShowDetailModal(true); };

  const { data: reportData, isLoading, refetch } = useQuery<CustomerSalesRecord[]>({
    queryKey: ['salesByCustomer', dateRange],
    queryFn: async () => {
      const params = new URLSearchParams();
      params.append('fromDate', dateRange.fromDate); params.append('toDate', dateRange.toDate);
      const r = await api.get(`/reports/sales-by-customer?${params}`); return r.data.data;
    }
  });

  const handleFilterSubmit = (e: React.FormEvent) => { e.preventDefault(); refetch(); };

  const handleExport = (format = 'pdf') => {
    if (!reportData) return;
    const cols = [
      { headerName: 'Customer Name', field: 'customer_name' },
      { headerName: 'Customer Code', field: 'customer_code' },
      { headerName: 'Email', field: 'email' },
      { headerName: 'Phone', field: 'phone' },
      { headerName: 'Total Invoices', field: 'total_invoices' },
      { headerName: 'Total Sales', field: 'total_sales', valueFormatter: (p: { value: number }) => formatCurrency(p.value || 0) },
      { headerName: 'Total Items', field: 'total_items' },
      { headerName: 'Avg. Order Value', field: 'average_order_value', valueFormatter: (p: { value: number }) => formatCurrency(p.value || 0) },
      { headerName: 'Last Purchase', field: 'last_purchase_date', valueFormatter: (p: { value: string }) => p.value ? new Date(p.value).toLocaleDateString() : '' }
    ];
    if (format === 'pdf') exportToPDF(reportData as unknown as Record<string, unknown>[], cols, 'Sales by Customer Report', `sales-by-customer-${new Date().toISOString().split('T')[0]}.pdf`);
    else exportToExcel(reportData as unknown as Record<string, unknown>[], cols, 'Sales by Customer Report', `sales-by-customer-${new Date().toISOString().split('T')[0]}.csv`);
  };

  const columnDefs = [
    { headerName: 'Customer Name', field: 'customer_name', filter: true, flex: 1 },
    { headerName: 'Customer Code', field: 'customer_code', filter: true, width: 140 },
    { headerName: 'Email', field: 'email', filter: true, width: 200 },
    { headerName: 'Phone', field: 'phone', filter: true, width: 140 },
    { headerName: 'Total Invoices', field: 'total_invoices', filter: 'agNumberColumnFilter', width: 120, cellClass: 'number-cell' },
    { headerName: 'Total Sales', field: 'total_sales', filter: 'agNumberColumnFilter', width: 140, valueFormatter: (p: { value: number }) => formatCurrency(p.value || 0), cellClass: 'amount-cell' },
    { headerName: 'Total Items', field: 'total_items', filter: 'agNumberColumnFilter', width: 120, cellClass: 'number-cell' },
    { headerName: 'Avg. Order Value', field: 'average_order_value', filter: 'agNumberColumnFilter', width: 150, valueFormatter: (p: { value: number }) => formatCurrency(p.value || 0), cellClass: 'amount-cell' },
    { headerName: 'Last Purchase', field: 'last_purchase_date', filter: 'agDateColumnFilter', width: 140, valueFormatter: (p: { value: string }) => p.value ? new Date(p.value).toLocaleDateString() : '' }
  ];

  return (
    <div className="sales-by-customer-report">
      <div className="page-header">
        <div><h1>Sales by Customer Report</h1><p className="page-subtitle">Analyze sales performance by customer</p></div>
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
            <Button type="submit" variant="primary" className="apply-filters-btn">Apply Filters</Button>
          </div>
        </form>
      )}
      <div className="report-content">
        {isLoading ? <div className="loading"><div className="spinner"></div></div>
        : reportData && reportData.length > 0 ? <>
          <MiniERPGrid
            wrapperClassName="desktop-view ag-grid-container"
            rowData={reportData}
            columnDefs={columnDefs as any}
            paginationPageSize={20}
            paginationPageSizeSelector={[10, 20, 50, 100]}
          />
          <div className="mobile-sales-list">
            {reportData.map((customer, index) => (
              <div key={customer.customer_code || customer.customer_name || `customer-${index}`} className="sales-customer-card"
                onClick={() => handleCardClick(customer)} role="button" tabIndex={0}
                onKeyDown={(e: React.KeyboardEvent) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); handleCardClick(customer); } }}>
                <div className="sales-customer-card-content">
                  <h3 className="customer-card-name">{customer.customer_name}</h3>
                  <span className="customer-card-amount">{formatCurrency(customer.total_sales || 0)}</span>
                </div>
              </div>
            ))}
          </div>
        </> : <div className="no-data"><Users size={48} /><h3>No sales by customer data found</h3><p>Try adjusting your filters to see customer sales data.</p></div>}
      </div>
      {showDetailModal && selectedCustomer && (
        <div className="customer-modal-overlay" onClick={() => setShowDetailModal(false)} role="dialog" aria-modal="true">
          <div className="customer-modal" onClick={(e: React.MouseEvent) => e.stopPropagation()} ref={modalRef}>
            <div className="customer-modal-header">
              <h2 className="customer-modal-title">{selectedCustomer.customer_name}</h2>
              <button type="button" className="customer-modal-close" onClick={() => setShowDetailModal(false)}><X size={24} /></button>
            </div>
            <div className="customer-modal-content">
              <div className="customer-detail-section">
                <div className="customer-details-grid">
                  <div className="customer-detail-item"><span className="customer-detail-label"><Mail size={14} /> Email</span><span className="customer-detail-value">{selectedCustomer.email || '-'}</span></div>
                  <div className="customer-detail-item"><span className="customer-detail-label"><Phone size={14} /> Phone</span><span className="customer-detail-value">{selectedCustomer.phone || '-'}</span></div>
                  <div className="customer-detail-item"><span className="customer-detail-label"><Receipt size={14} /> Total Invoices</span><span className="customer-detail-value">{selectedCustomer.total_invoices}</span></div>
                  <div className="customer-detail-item"><span className="customer-detail-label"><Package size={14} /> Total Items</span><span className="customer-detail-value">{selectedCustomer.total_items}</span></div>
                  <div className="customer-detail-item"><span className="customer-detail-label"><TrendingUpIcon size={14} /> Avg. Order Value</span><span className="customer-detail-value">{formatCurrency(selectedCustomer.average_order_value || 0)}</span></div>
                  <div className="customer-detail-item"><span className="customer-detail-label"><Clock size={14} /> Last Purchase</span><span className="customer-detail-value">{selectedCustomer.last_purchase_date ? new Date(selectedCustomer.last_purchase_date).toLocaleDateString() : '-'}</span></div>
                </div>
              </div>
              <div className="customer-sales-highlight">
                <span className="sales-label">Total Sales</span>
                <span className="sales-value">{formatCurrency(selectedCustomer.total_sales || 0)}</span>
              </div>
            </div>
            <div className="customer-modal-actions">
              <button type="button" className="customer-action-btn customer-action-secondary" onClick={() => setShowDetailModal(false)}>Close</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
