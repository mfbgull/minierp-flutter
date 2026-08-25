import { useState, useEffect, useRef } from 'react';
import { useQuery } from '@tanstack/react-query';
import MiniERPGrid from '../../components/common/MiniERPGrid';
import {
  Package,
  TrendingUp,
  FileText,
  DollarSign,
  Calendar,
  Download,
  Filter,
  BarChart3,
  X,
  Tag,
  Hash
} from 'lucide-react';

import Button from '../../components/common/Button';
import DateRangePicker from '../../components/common/DateRangePicker';
import type { DateRangeFilter } from '../../types';
import { useSettings } from '../../context/SettingsContext';
import api from '../../utils/api';
import { exportToPDF, exportToExcel } from '../../utils/exportUtils';
import './SalesByItemReport.css';

interface ItemSalesRecord {
  item_code?: string;
  item_name: string;
  item_category?: string;
  total_quantity_sold?: number;
  total_sales?: number;
  avg_selling_price?: number;
}

export default function SalesByItemReport() {
  const [dateRange, setDateRange] = useState<DateRangeFilter>({
    fromDate: new Date(new Date().setMonth(new Date().getMonth() - 1)).toISOString().split('T')[0],
    toDate: new Date().toISOString().split('T')[0]
  });
  const [showFilters, setShowFilters] = useState(false);
  const [selectedItem, setSelectedItem] = useState<ItemSalesRecord | null>(null);
  const [showDetailModal, setShowDetailModal] = useState(false);
  const modalRef = useRef<HTMLDivElement>(null);
  const { formatCurrency } = useSettings();

  useEffect(() => {
    const handleEsc = (event: KeyboardEvent) => { if (event.key === 'Escape') setShowDetailModal(false); };
    if (showDetailModal) document.addEventListener('keydown', handleEsc);
    return () => document.removeEventListener('keydown', handleEsc);
  }, [showDetailModal]);

  const handleCardClick = (item: ItemSalesRecord) => { setSelectedItem(item); setShowDetailModal(true); };

  const { data: reportData, isLoading, refetch } = useQuery<ItemSalesRecord[]>({
    queryKey: ['salesByItem', dateRange],
    queryFn: async () => {
      const params = new URLSearchParams();
      params.append('fromDate', dateRange.fromDate); params.append('toDate', dateRange.toDate);
      const r = await api.get(`/reports/sales-by-item?${params}`); return r.data.data;
    }
  });

  const handleFilterSubmit = (e: React.FormEvent) => { e.preventDefault(); refetch(); };

  const handleExport = (format = 'pdf') => {
    if (!reportData) return;
    const cols = [
      { headerName: 'Item Name', field: 'item_name' },
      { headerName: 'Item Code', field: 'item_code' },
      { headerName: 'Category', field: 'item_category' },
      { headerName: 'Total Quantity Sold', field: 'total_quantity_sold' },
      { headerName: 'Total Sales', field: 'total_sales', valueFormatter: (p: { value: number }) => formatCurrency(p.value || 0) },
      { headerName: 'Avg. Selling Price', field: 'avg_selling_price', valueFormatter: (p: { value: number }) => formatCurrency(p.value || 0) }
    ];
    if (format === 'pdf') exportToPDF(reportData as unknown as Record< string,unknown >[], cols, 'Sales by Item Report', `sales-by-item-${new Date().toISOString().split('T')[0]}.pdf`);
    else exportToExcel(reportData as unknown as Record< string,unknown >[], cols, 'Sales by Item Report', `sales-by-item-${new Date().toISOString().split('T')[0]}.csv`);
  };

  const columnDefs = [
    { headerName: 'Item Name', field: 'item_name', filter: true, flex: 1 },
    { headerName: 'Item Code', field: 'item_code', filter: true, width: 140 },
    { headerName: 'Category', field: 'item_category', filter: true, width: 140 },
    { headerName: 'Total Quantity Sold', field: 'total_quantity_sold', filter: 'agNumberColumnFilter', width: 150, cellClass: 'number-cell' },
    { headerName: 'Total Sales', field: 'total_sales', filter: 'agNumberColumnFilter', width: 140, valueFormatter: (p: { value: number }) => formatCurrency(p.value || 0), cellClass: 'amount-cell' },
    { headerName: 'Avg. Selling Price', field: 'avg_selling_price', filter: 'agNumberColumnFilter', width: 150, valueFormatter: (p: { value: number }) => formatCurrency(p.value || 0), cellClass: 'amount-cell' }
  ];

  return (
    <div className="sales-by-item-report">
      <div className="page-header">
        <div><h1>Sales by Item Report</h1><p className="page-subtitle">Analyze sales performance by item</p></div>
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
            {reportData.map((item, index) => (
              <div key={item.item_code || item.item_name || `item-${index}`} className="sales-item-card"
                onClick={() => handleCardClick(item)} role="button" tabIndex={0}
                onKeyDown={(e: React.KeyboardEvent) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); handleCardClick(item); } }}>
                <div className="sales-item-card-content">
                  <h3 className="item-card-name">{item.item_name}</h3>
                  <span className="item-card-amount">{formatCurrency(item.total_sales || 0)}</span>
                </div>
              </div>
            ))}
          </div>
        </> : <div className="no-data"><Package size={48} /><h3>No sales by item data found</h3><p>Try adjusting your filters to see item sales data.</p></div>}
      </div>
      {showDetailModal && selectedItem && (
        <div className="item-modal-overlay" onClick={() => setShowDetailModal(false)} role="dialog" aria-modal="true">
          <div className="item-modal" onClick={(e: React.MouseEvent) => e.stopPropagation()} ref={modalRef}>
            <div className="item-modal-header">
              <h2 className="item-modal-title">{selectedItem.item_name}</h2>
              <button type="button" className="item-modal-close" onClick={() => setShowDetailModal(false)}><X size={24} /></button>
            </div>
            <div className="item-modal-content">
              <div className="item-detail-section">
                <div className="item-details-grid">
                  <div className="item-detail-item"><span className="item-detail-label"><Tag size={14} /> Item Code</span><span className="item-detail-value">{selectedItem.item_code || '-'}</span></div>
                  <div className="item-detail-item"><span className="item-detail-label"><Package size={14} /> Category</span><span className="item-detail-value">{selectedItem.item_category || '-'}</span></div>
                  <div className="item-detail-item"><span className="item-detail-label"><Hash size={14} /> Quantity Sold</span><span className="item-detail-value">{selectedItem.total_quantity_sold}</span></div>
                  <div className="item-detail-item"><span className="item-detail-label"><TrendingUp size={14} /> Avg. Selling Price</span><span className="item-detail-value">{formatCurrency(selectedItem.avg_selling_price || 0)}</span></div>
                </div>
              </div>
              <div className="item-sales-highlight">
                <span className="sales-label">Total Sales</span>
                <span className="sales-value">{formatCurrency(selectedItem.total_sales || 0)}</span>
              </div>
            </div>
            <div className="item-modal-actions">
              <button type="button" className="item-action-btn item-action-secondary" onClick={() => setShowDetailModal(false)}>Close</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
