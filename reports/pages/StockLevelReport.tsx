import { useState, useEffect } from 'react';
import { useQuery } from '@tanstack/react-query';
import MiniERPGrid from '../../components/common/MiniERPGrid';
import {
  Package,
  AlertTriangle,
  CheckCircle,
  XCircle,
  Download,
  Filter,
  X,
  Tag,
  Hash,
  DollarSign,
  AlertCircle
} from 'lucide-react';

import Button from '../../components/common/Button';
import StatCard, { StatsGrid } from '../../components/common/StatCard';
import { useSettings } from '../../context/SettingsContext';
import api from '../../utils/api';
import { exportToPDF, exportToExcel } from '../../utils/exportUtils';
import './InventoryReports.css';

interface Warehouse {
  id: number;
  warehouse_name: string;
}

interface InventoryItem {
  id: number;
  item_name: string;
  item_category?: string;
}

interface StockLevelItem {
  id?: number;
  item_code?: string;
  item_name: string;
  item_category?: string;
  unit_of_measure?: string;
  current_stock?: number;
  minimum_stock?: number;
  reorder_level?: number;
  standard_selling_price?: number;
  stock_status?: string;
}

interface StockLevelData {
  stockLevels?: StockLevelItem[];
  summary?: {
    totalItems?: number;
    inStock?: number;
    lowStock?: number;
    outOfStock?: number;
  };
}

export default function StockLevelReport() {
  const [warehouseId, setWarehouseId] = useState('');
  const [categoryId, setCategoryId] = useState('');
  const [showZeroStock, setShowZeroStock] = useState(true);
  const [showFilters, setShowFilters] = useState(false);
  const [selectedItem, setSelectedItem] = useState<StockLevelItem | null>(null);
  const [showDetailModal, setShowDetailModal] = useState(false);
  const { formatCurrency } = useSettings();

  useEffect(() => {
    const handleEsc = (event: KeyboardEvent) => { if (event.key === 'Escape') setShowDetailModal(false); };
    if (showDetailModal) document.addEventListener('keydown', handleEsc);
    return () => document.removeEventListener('keydown', handleEsc);
  }, [showDetailModal]);

  const handleCardClick = (item: StockLevelItem) => { setSelectedItem(item); setShowDetailModal(true); };

  const { data: warehouses = [] } = useQuery<Warehouse[]>({
    queryKey: ['warehouses'], queryFn: async () => { const r = await api.get('/inventory/warehouses'); return r.data.data || []; }
  });

  const { data: items = [] } = useQuery<InventoryItem[]>({
    queryKey: ['items'], queryFn: async () => { const r = await api.get('/inventory/items'); return r.data.data || []; }
  });

  const categories = [...new Set(items.map(item => item.item_category).filter(Boolean))] as string[];

  const { data: reportData, isLoading, refetch } = useQuery<StockLevelData>({
    queryKey: ['stockLevel', warehouseId, categoryId, showZeroStock],
    queryFn: async () => {
      const params = new URLSearchParams();
      if (warehouseId) params.append('warehouseId', warehouseId);
      if (categoryId) params.append('categoryId', categoryId);
      params.append('showZeroStock', String(showZeroStock));
      const r = await api.get(`/reports/stock-level?${params}`); return r.data.data;
    }
  });

  const handleFilterSubmit = (e: React.FormEvent) => { e.preventDefault(); refetch(); };

  const handleExport = (format = 'pdf') => {
    if (!reportData?.stockLevels) return;
    const cols = [
      { headerName: 'Item Name', field: 'item_name' },
      { headerName: 'Item Code', field: 'item_code' },
      { headerName: 'Category', field: 'item_category' },
      { headerName: 'UOM', field: 'unit_of_measure' },
      { headerName: 'Current Stock', field: 'current_stock' },
      { headerName: 'Minimum Stock', field: 'minimum_stock' },
      { headerName: 'Reorder Level', field: 'reorder_level' },
      { headerName: 'Selling Price', field: 'standard_selling_price', valueFormatter: (p: { value: number }) => formatCurrency(p.value || 0) },
      { headerName: 'Status', field: 'stock_status' }
    ];
    if (format === 'pdf') exportToPDF(reportData.stockLevels as unknown as Record< string,unknown >[], cols, 'Stock Level Report', `stock-level-${new Date().toISOString().split('T')[0]}.pdf`);
    else exportToExcel(reportData.stockLevels as unknown as Record< string,unknown >[], cols, 'Stock Level Report', `stock-level-${new Date().toISOString().split('T')[0]}.csv`);
  };

  const columnDefs = [
    { headerName: 'Item Name', field: 'item_name', filter: true, flex: 1 },
    { headerName: 'Item Code', field: 'item_code', filter: true, width: 140 },
    { headerName: 'Category', field: 'item_category', filter: true, width: 140 },
    { headerName: 'UOM', field: 'unit_of_measure', filter: true, width: 100 },
    { headerName: 'Current Stock', field: 'current_stock', filter: 'agNumberColumnFilter', width: 120, cellClass: 'number-cell' },
    { headerName: 'Minimum Stock', field: 'minimum_stock', filter: 'agNumberColumnFilter', width: 140, cellClass: 'number-cell' },
    { headerName: 'Reorder Level', field: 'reorder_level', filter: 'agNumberColumnFilter', width: 140, cellClass: 'number-cell' },
    { headerName: 'Selling Price', field: 'standard_selling_price', filter: 'agNumberColumnFilter', width: 140, valueFormatter: (p: { value: number }) => formatCurrency(p.value || 0), cellClass: 'amount-cell' },
    { headerName: 'Status', field: 'stock_status', filter: true, width: 140, cellClass: (p: { value: string }) => { const s = p.value?.toLowerCase(); if (s === 'out of stock') return 'status-out-of-stock'; if (s === 'low stock') return 'status-low-stock'; return 'status-in-stock'; } }
  ];

  return (
    <div className="stock-level-report">
      <div className="page-header">
        <div><h1>Stock Level Report</h1><p className="page-subtitle">Current inventory levels across all warehouses</p></div>
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
            <div className="filter-group checkbox-group">
              <label><input type="checkbox" checked={showZeroStock} onChange={(e: React.ChangeEvent<HTMLInputElement>) => setShowZeroStock(e.target.checked)} /> Show Zero Stock Items</label>
            </div>
            <Button type="submit" variant="primary" className="apply-filters-btn">Apply Filters</Button>
          </div>
        </form>
      )}
      {reportData?.summary && (
        <StatsGrid className="compact">
          <StatCard icon={Package} label="Total Items" value={reportData.summary.totalItems} />
          <StatCard icon={CheckCircle} label="In Stock" value={reportData.summary.inStock} />
          <StatCard icon={AlertTriangle} label="Low Stock" value={reportData.summary.lowStock} alert={true} />
          <StatCard icon={XCircle} label="Out of Stock" value={reportData.summary.outOfStock} alert={true} />
        </StatsGrid>
      )}
      <div className="report-content">
        {isLoading ? <div className="loading"><div className="spinner"></div></div>
        : reportData?.stockLevels && reportData.stockLevels.length > 0 ? <>
          <MiniERPGrid
            wrapperClassName="desktop-view ag-grid-container"
            rowData={reportData.stockLevels}
            columnDefs={columnDefs as any}
            getRowId={(params: any) => params.data.id || params.data.item_code || `row-${params.node.rowIndex}`}
            paginationPageSize={20}
            paginationPageSizeSelector={[10, 20, 50, 100]}
          />
          <div className="mobile-stock-level-list">
            {reportData.stockLevels.map((item, index) => (
              <div key={item.id || item.item_code || `stock-${index}`} className="stock-level-card"
                onClick={() => handleCardClick(item)} role="button" tabIndex={0}
                onKeyDown={(e: React.KeyboardEvent) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); handleCardClick(item); } }}>
                <div className="stock-level-card-content">
                  <h3 className="stock-item-name">{item.item_name}</h3>
                  <span className="stock-item-qty">{item.current_stock} {item.unit_of_measure}</span>
                </div>
              </div>
            ))}
          </div>
        </> : <div className="no-data"><Package size={48} /><h3>No stock level data found</h3><p>Try adjusting your filters to see stock level data.</p></div>}
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
                  <div className="stock-detail-item"><span className="stock-detail-label"><AlertCircle size={14} /> Minimum Stock</span><span className="stock-detail-value">{selectedItem.minimum_stock} {selectedItem.unit_of_measure}</span></div>
                  <div className="stock-detail-item"><span className="stock-detail-label"><AlertTriangle size={14} /> Reorder Level</span><span className="stock-detail-value">{selectedItem.reorder_level} {selectedItem.unit_of_measure}</span></div>
                  <div className="stock-detail-item"><span className="stock-detail-label"><DollarSign size={14} /> Selling Price</span><span className="stock-detail-value">{formatCurrency(selectedItem.standard_selling_price || 0)}</span></div>
                  <div className="stock-detail-item"><span className="stock-detail-label">Status</span><span className={`stock-detail-value status-badge ${selectedItem.stock_status?.toLowerCase().replace(/\s+/g, '-')}`}>{selectedItem.stock_status}</span></div>
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
