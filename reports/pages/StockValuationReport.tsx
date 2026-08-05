import { useState, useEffect } from 'react';
import { useQuery } from '@tanstack/react-query';
import MiniERPGrid from '../../components/common/MiniERPGrid';
import {
  Package,
  DollarSign,
  Download,
  Filter,
  X,
  Tag,
  Hash
} from 'lucide-react';

import Button from '../../components/common/Button';
import StatCard, { StatsGrid } from '../../components/common/StatCard';
import { useSettings } from '../../context/SettingsContext';
import api from '../../utils/api';
import { exportToPDF, exportToExcel } from '../../utils/exportUtils';
import './StockValuationReport.css';

interface Warehouse {
  id: number;
  warehouse_name: string;
}

interface InventoryItem {
  id: number;
  item_name: string;
  item_category?: string;
}

interface StockValuationItem {
  id?: number;
  item_code?: string;
  item_name: string;
  item_category?: string;
  unit_of_measure?: string;
  current_stock?: number;
  unit_cost?: number;
  total_value?: number;
  valuation_method?: string;
}

interface StockValuationData {
  stockValuation?: StockValuationItem[];
  summary?: {
    totalItems?: number;
    totalValue?: number;
  };
}

export default function StockValuationReport() {
  const [warehouseId, setWarehouseId] = useState('');
  const [categoryId, setCategoryId] = useState('');
  const [valuationMethod, setValuationMethod] = useState('average-cost');
  const [showFilters, setShowFilters] = useState(false);
  const [selectedItem, setSelectedItem] = useState<StockValuationItem | null>(null);
  const [showDetailModal, setShowDetailModal] = useState(false);
  const { formatCurrency } = useSettings();

  useEffect(() => {
    const handleEsc = (event: KeyboardEvent) => { if (event.key === 'Escape') setShowDetailModal(false); };
    if (showDetailModal) document.addEventListener('keydown', handleEsc);
    return () => document.removeEventListener('keydown', handleEsc);
  }, [showDetailModal]);

  const handleCardClick = (item: StockValuationItem) => { setSelectedItem(item); setShowDetailModal(true); };

  const { data: warehouses = [] } = useQuery<Warehouse[]>({
    queryKey: ['warehouses'], queryFn: async () => { const r = await api.get('/inventory/warehouses'); return r.data.data || []; }
  });

  const { data: items = [] } = useQuery<InventoryItem[]>({
    queryKey: ['items'], queryFn: async () => { const r = await api.get('/inventory/items'); return r.data.data || []; }
  });

  const categories = [...new Set(items.map(item => item.item_category).filter(Boolean))] as string[];

  const { data: reportData, isLoading, refetch } = useQuery<StockValuationData>({
    queryKey: ['stockValuation', warehouseId, categoryId, valuationMethod],
    queryFn: async () => {
      const params = new URLSearchParams();
      if (warehouseId) params.append('warehouseId', warehouseId);
      if (categoryId) params.append('categoryId', categoryId);
      params.append('valuationMethod', valuationMethod);
      const r = await api.get(`/reports/stock-valuation?${params}`); return r.data.data;
    }
  });

  const handleFilterSubmit = (e: React.FormEvent) => { e.preventDefault(); refetch(); };

  const handleExport = (format = 'pdf') => {
    if (!reportData?.stockValuation) return;
    const cols = [
      { headerName: 'Item Name', field: 'item_name' },
      { headerName: 'Item Code', field: 'item_code' },
      { headerName: 'Category', field: 'item_category' },
      { headerName: 'UOM', field: 'unit_of_measure' },
      { headerName: 'Current Stock', field: 'current_stock' },
      { headerName: 'Unit Cost', field: 'unit_cost', valueFormatter: (p: { value: number }) => formatCurrency(p.value || 0) },
      { headerName: 'Total Value', field: 'total_value', valueFormatter: (p: { value: number }) => formatCurrency(p.value || 0) },
      { headerName: 'Valuation Method', field: 'valuation_method' }
    ];
    if (format === 'pdf') exportToPDF(reportData.stockValuation as unknown as Record< string,unknown >[], cols, 'Stock Valuation Report', `stock-valuation-${new Date().toISOString().split('T')[0]}.pdf`);
    else exportToExcel(reportData.stockValuation as unknown as Record< string,unknown >[], cols, 'Stock Valuation Report', `stock-valuation-${new Date().toISOString().split('T')[0]}.csv`);
  };

  const columnDefs = [
    { headerName: 'Item Name', field: 'item_name', filter: true, flex: 1 },
    { headerName: 'Item Code', field: 'item_code', filter: true, width: 140 },
    { headerName: 'Category', field: 'item_category', filter: true, width: 140 },
    { headerName: 'UOM', field: 'unit_of_measure', filter: true, width: 100 },
    { headerName: 'Current Stock', field: 'current_stock', filter: 'agNumberColumnFilter', width: 120, cellClass: 'number-cell' },
    { headerName: 'Unit Cost', field: 'unit_cost', filter: 'agNumberColumnFilter', width: 140, valueFormatter: (p: { value: number }) => formatCurrency(p.value || 0), cellClass: 'amount-cell' },
    { headerName: 'Total Value', field: 'total_value', filter: 'agNumberColumnFilter', width: 140, valueFormatter: (p: { value: number }) => formatCurrency(p.value || 0), cellClass: 'amount-cell' },
    { headerName: 'Valuation Method', field: 'valuation_method', filter: true, width: 140 }
  ];

  return (
    <div className="stock-valuation-report">
      <div className="page-header">
        <div><h1>Stock Valuation Report</h1><p className="page-subtitle">Inventory value analysis using various valuation methods</p></div>
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
            <div className="filter-group"><label>Warehouse</label>
              <select value={warehouseId} onChange={(e: React.ChangeEvent<HTMLSelectElement>) => setWarehouseId(e.target.value)} className="filter-select">
                <option value="">All Warehouses</option>
                {warehouses.map(w => <option key={w.id} value={w.id}>{w.warehouse_name}</option>)}
              </select>
            </div>
            <div className="filter-group"><label>Category</label>
              <select value={categoryId} onChange={(e: React.ChangeEvent<HTMLSelectElement>) => setCategoryId(e.target.value)} className="filter-select">
                <option value="">All Categories</option>
                {categories.map(c => <option key={c} value={c}>{c}</option>)}
              </select>
            </div>
            <div className="filter-group"><label>Valuation Method</label>
              <select value={valuationMethod} onChange={(e: React.ChangeEvent<HTMLSelectElement>) => setValuationMethod(e.target.value)} className="filter-select">
                <option value="average-cost">Average Cost</option>
                <option value="fifo">FIFO</option>
                <option value="lifo">LIFO</option>
              </select>
            </div>
            <Button type="submit" variant="primary" className="apply-filters-btn">Apply Filters</Button>
          </div>
        </form>
      )}
      {reportData?.summary && (
        <StatsGrid className="compact">
          <StatCard icon={Package} label="Total Items" value={reportData.summary.totalItems} />
          <StatCard icon={DollarSign} label="Total Inventory Value" value={formatCurrency(reportData.summary.totalValue)} />
        </StatsGrid>
      )}
      <div className="report-content">
        {isLoading ? <div className="loading"><div className="spinner"></div></div>
        : reportData?.stockValuation && reportData.stockValuation.length > 0 ? <>
          <MiniERPGrid
            wrapperClassName="desktop-view ag-grid-container"
            rowData={reportData.stockValuation}
            columnDefs={columnDefs as any}
            paginationPageSize={20}
            paginationPageSizeSelector={[10, 20, 50, 100]}
          />
          <div className="mobile-stock-valuation-list">
            {reportData.stockValuation.map((item, index) => (
              <div key={`${item.id || item.item_code}-${index}`} className="stock-valuation-card"
                onClick={() => handleCardClick(item)} role="button" tabIndex={0}
                onKeyDown={(e: React.KeyboardEvent) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); handleCardClick(item); } }}>
                <div className="stock-valuation-card-content">
                  <h3 className="valuation-item-name">{item.item_name}</h3>
                  <span className="valuation-item-value">{formatCurrency(item.total_value || 0)}</span>
                </div>
              </div>
            ))}
          </div>
        </> : <div className="no-data"><Package size={48} /><h3>No stock valuation data found</h3><p>Try adjusting your filters to see stock valuation data.</p></div>}
      </div>
      {showDetailModal && selectedItem && (
        <div className="stock-modal-overlay" onClick={() => setShowDetailModal(false)} role="dialog" aria-modal="true">
          <div className="stock-modal" onClick={(e: React.MouseEvent) => e.stopPropagation()}>
            <div className="stock-modal-header">
              <h2 className="stock-modal-title">{selectedItem.item_name}</h2>
              <button type="button" className="stock-modal-close" onClick={() => setShowDetailModal(false)}><X size={24} /></button>
            </div>
            <div className="stock-modal-content">
              <div className="stock-detail-section">
                <div className="stock-details-grid">
                  <div className="stock-detail-item"><span className="stock-detail-label"><Tag size={14} /> Item Code</span><span className="stock-detail-value">{selectedItem.item_code || '-'}</span></div>
                  <div className="stock-detail-item"><span className="stock-detail-label"><Package size={14} /> Category</span><span className="stock-detail-value">{selectedItem.item_category || '-'}</span></div>
                  <div className="stock-detail-item"><span className="stock-detail-label"><Hash size={14} /> UOM</span><span className="stock-detail-value">{selectedItem.unit_of_measure || '-'}</span></div>
                  <div className="stock-detail-item"><span className="stock-detail-label"><Package size={14} /> Current Stock</span><span className="stock-detail-value">{selectedItem.current_stock} {selectedItem.unit_of_measure}</span></div>
                  <div className="stock-detail-item"><span className="stock-detail-label"><DollarSign size={14} /> Unit Cost</span><span className="stock-detail-value">{formatCurrency(selectedItem.unit_cost || 0)}</span></div>
                  <div className="stock-detail-item"><span className="stock-detail-label"><DollarSign size={14} /> Total Value</span><span className="stock-detail-value">{formatCurrency(selectedItem.total_value || 0)}</span></div>
                  <div className="stock-detail-item"><span className="stock-detail-label">Valuation Method</span><span className="stock-detail-value">{selectedItem.valuation_method || '-'}</span></div>
                </div>
              </div>
            </div>
            <div className="stock-modal-actions">
              <button type="button" className="stock-action-btn stock-action-secondary" onClick={() => setShowDetailModal(false)}>Close</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
