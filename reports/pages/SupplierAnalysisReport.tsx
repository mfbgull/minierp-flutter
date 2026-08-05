import { useState, useEffect } from 'react';
import { useQuery } from '@tanstack/react-query';
import MiniERPGrid from '../../components/common/MiniERPGrid';
import {
  Users,
  ShoppingCart,
  TrendingUp,
  FileText,
  DollarSign,
  Calendar,
  Download,
  Filter,
  BarChart3,
  X,
  Tag,
  Hash,
  Receipt,
  TrendingUp as TrendingUpIcon
} from 'lucide-react';

import Button from '../../components/common/Button';
import DateRangePicker from '../../components/common/DateRangePicker';
import type { DateRangeFilter } from '../../types';
import { useSettings } from '../../context/SettingsContext';
import api from '../../utils/api';
import { exportToPDF, exportToExcel } from '../../utils/exportUtils';
import './SupplierAnalysisReport.css';
import '../../styles/ag-grid-status-cells.css';
import { getDeliveryRateCellClass } from '../../utils/statusCellUtils';

interface SupplierRecord {
  supplier_id?: number;
  supplier_name: string;
  supplier_code?: string;
  email?: string;
  phone?: string;
  total_orders?: number;
  total_purchase_value?: number;
  average_order_value?: number;
  on_time_delivery_rate?: number;
  last_purchase_date?: string;
  total_items?: number;
}

export default function SupplierAnalysisReport() {
  const [dateRange, setDateRange] = useState<DateRangeFilter>({
    fromDate: new Date(new Date().setMonth(new Date().getMonth() - 3)).toISOString().split('T')[0],
    toDate: new Date().toISOString().split('T')[0]
  });
  const [showFilters, setShowFilters] = useState(false);
  const [selectedSupplier, setSelectedSupplier] = useState<SupplierRecord | null>(null);
  const [showDetailModal, setShowDetailModal] = useState(false);
  const { formatCurrency } = useSettings();

  useEffect(() => {
    const handleEsc = (event: KeyboardEvent) => { if (event.key === 'Escape') setShowDetailModal(false); };
    if (showDetailModal) document.addEventListener('keydown', handleEsc);
    return () => document.removeEventListener('keydown', handleEsc);
  }, [showDetailModal]);

  const handleCardClick = (supplier: SupplierRecord) => { setSelectedSupplier(supplier); setShowDetailModal(true); };

  const { data: reportData, isLoading, refetch } = useQuery<SupplierRecord[]>({
    queryKey: ['supplierAnalysis', dateRange],
    queryFn: async () => {
      const params = new URLSearchParams();
      params.append('fromDate', dateRange.fromDate); params.append('toDate', dateRange.toDate);
      const r = await api.get(`/reports/supplier-analysis?${params}`); return r.data.data;
    }
  });

  const handleFilterSubmit = (e: React.FormEvent) => { e.preventDefault(); refetch(); };

  const handleExport = (format = 'pdf') => {
    if (!reportData) return;
    const cols = [
      { headerName: 'Supplier Name', field: 'supplier_name' },
      { headerName: 'Supplier Code', field: 'supplier_code' },
      { headerName: 'Email', field: 'email' },
      { headerName: 'Phone', field: 'phone' },
      { headerName: 'Total Orders', field: 'total_orders' },
      { headerName: 'Total Purchase Value', field: 'total_purchase_value', valueFormatter: (p: { value: number }) => formatCurrency(p.value || 0) },
      { headerName: 'Avg. Order Value', field: 'average_order_value', valueFormatter: (p: { value: number }) => formatCurrency(p.value || 0) },
      { headerName: 'On-time Delivery Rate', field: 'on_time_delivery_rate', valueFormatter: (p: { value: number }) => `${p.value || 0}%` },
      { headerName: 'Last Purchase Date', field: 'last_purchase_date', valueFormatter: (p: { value: string }) => p.value ? new Date(p.value).toLocaleDateString() : '' }
    ];
    if (format === 'pdf') exportToPDF(reportData as unknown as Record< string,unknown >[], cols, 'Supplier Analysis Report', `supplier-analysis-${new Date().toISOString().split('T')[0]}.pdf`);
    else exportToExcel(reportData as unknown as Record< string,unknown >[], cols, 'Supplier Analysis Report', `supplier-analysis-${new Date().toISOString().split('T')[0]}.csv`);
  };

  const columnDefs = [
    { headerName: 'Supplier Name', field: 'supplier_name', filter: true, flex: 1 },
    { headerName: 'Supplier Code', field: 'supplier_code', filter: true, width: 140 },
    { headerName: 'Email', field: 'email', filter: true, width: 200 },
    { headerName: 'Phone', field: 'phone', filter: true, width: 140 },
    { headerName: 'Total Orders', field: 'total_orders', filter: 'agNumberColumnFilter', width: 120, cellClass: 'number-cell' },
    { headerName: 'Total Purchase Value', field: 'total_purchase_value', filter: 'agNumberColumnFilter', width: 150, valueFormatter: (p: { value: number }) => formatCurrency(p.value || 0), cellClass: 'amount-cell' },
    { headerName: 'Avg. Order Value', field: 'average_order_value', filter: 'agNumberColumnFilter', width: 150, valueFormatter: (p: { value: number }) => formatCurrency(p.value || 0), cellClass: 'amount-cell' },
    { headerName: 'On-time Delivery Rate', field: 'on_time_delivery_rate', filter: 'agNumberColumnFilter', width: 160, valueFormatter: (p: { value: number }) => `${p.value || 0}%`, cellClass: (p: { value: number }) => getDeliveryRateCellClass(p.value) },
    { headerName: 'Last Purchase Date', field: 'last_purchase_date', filter: 'agDateColumnFilter', width: 140, valueFormatter: (p: { value: string }) => p.value ? new Date(p.value).toLocaleDateString() : '' }
  ];

  return (
    <div className="supplier-analysis-report">
      <div className="page-header">
        <div><h1>Supplier Analysis Report</h1><p className="page-subtitle">Analyze supplier performance and purchasing patterns</p></div>
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
          <div className="mobile-supplier-analysis-list">
            {reportData.map((supplier, index) => (
              <div key={`${supplier.supplier_id || supplier.supplier_name}-${index}`} className="supplier-analysis-card"
                onClick={() => handleCardClick(supplier)} role="button" tabIndex={0}
                onKeyDown={(e: React.KeyboardEvent) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); handleCardClick(supplier); } }}>
                <div className="supplier-analysis-card-content">
                  <h3 className="supplier-analysis-name">{supplier.supplier_name}</h3>
                  <span className="supplier-analysis-amount">{formatCurrency(supplier.total_purchase_value || 0)}</span>
                </div>
              </div>
            ))}
          </div>
        </> : <div className="no-data"><Users size={48} /><h3>No supplier analysis data found</h3><p>Try adjusting your filters to see supplier analysis data.</p></div>}
      </div>
      {showDetailModal && selectedSupplier && (
        <div className="supplier-modal-overlay" onClick={() => setShowDetailModal(false)} role="dialog" aria-modal="true">
          <div className="supplier-modal" onClick={(e: React.MouseEvent) => e.stopPropagation()}>
            <div className="supplier-modal-header">
              <h2 className="supplier-modal-title">{selectedSupplier.supplier_name}</h2>
              <button type="button" className="supplier-modal-close" onClick={() => setShowDetailModal(false)}><X size={24} /></button>
            </div>
            <div className="supplier-modal-content">
              <div className="supplier-detail-section">
                <div className="supplier-details-grid">
                  <div className="supplier-detail-item"><span className="supplier-detail-label"><Receipt size={14} /> Total Orders</span><span className="supplier-detail-value">{selectedSupplier.total_orders || 0}</span></div>
                  <div className="supplier-detail-item"><span className="supplier-detail-label"><DollarSign size={14} /> Total Purchases</span><span className="supplier-detail-value">{formatCurrency(selectedSupplier.total_purchase_value || 0)}</span></div>
                  <div className="supplier-detail-item"><span className="supplier-detail-label"><TrendingUpIcon size={14} /> Average Order Value</span><span className="supplier-detail-value">{formatCurrency(selectedSupplier.average_order_value || 0)}</span></div>
                  <div className="supplier-detail-item"><span className="supplier-detail-label"><Hash size={14} /> Total Items</span><span className="supplier-detail-value">{selectedSupplier.total_items || 0}</span></div>
                  <div className="supplier-detail-item"><span className="supplier-detail-label"><Calendar size={14} /> Last Purchase</span><span className="supplier-detail-value">{selectedSupplier.last_purchase_date ? new Date(selectedSupplier.last_purchase_date).toLocaleDateString() : '-'}</span></div>
                </div>
              </div>
            </div>
            <div className="supplier-modal-actions">
              <button type="button" className="supplier-action-btn supplier-action-secondary" onClick={() => setShowDetailModal(false)}>Close</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
