import { useState, useEffect } from 'react';
import { useQuery } from '@tanstack/react-query';
import MiniERPGrid from '../../components/common/MiniERPGrid';
import {
  AlertTriangle,
  Package,
  Download,
  Filter,
  X,
  Tag,
  Hash
} from 'lucide-react';

import Button from '../../components/common/Button';
import { useSettings } from '../../context/SettingsContext';
import api from '../../utils/api';
import { exportToPDF, exportToExcel } from '../../utils/exportUtils';
import './InventoryReports.css';

interface Warehouse {
  id: number;
  warehouse_name: string;
}

interface LowStockItem {
  id?: number;
  item_code?: string;
  item_name: string;
  item_category?: string;
  unit_of_measure?: string;
  current_stock?: number;
  minimum_stock?: number;
  shortage?: number;
  reorder_level?: number;
}

export default function LowStockReport() {
  const [warehouseId, setWarehouseId] = useState('');
  const [showFilters, setShowFilters] = useState(false);
  const [selectedItem, setSelectedItem] = useState<LowStockItem | null>(null);
  const [showDetailModal, setShowDetailModal] = useState(false);
  const { formatCurrency } = useSettings();

  useEffect(() => {
    const handleEsc = (event: KeyboardEvent) => { if (event.key === 'Escape') setShowDetailModal(false); };
    if (showDetailModal) document.addEventListener('keydown', handleEsc);
    return () => document.removeEventListener('keydown', handleEsc);
  }, [showDetailModal]);

  const handleCardClick = (item: LowStockItem) => { setSelectedItem(item); setShowDetailModal(true); };

  const { data: warehouses = [] } = useQuery<Warehouse[]>({
    queryKey: ['warehouses'], queryFn: async () => { const r = await api.get('/inventory/warehouses'); return r.data.data || []; }
  });

  const { data: reportData, isLoading, refetch } = useQuery<LowStockItem[]>({
    queryKey: ['lowStock', warehouseId],
    queryFn: async () => {
      const params = new URLSearchParams();
      if (warehouseId) params.append('warehouseId', warehouseId);
      const r = await api.get(`/reports/low-stock?${params}`); return r.data.data;
    }
  });

  const handleFilterSubmit = (e: React.FormEvent) => { e.preventDefault(); refetch(); };

  const handleExport = (format = 'pdf') => {
    if (!reportData) return;
    const cols = [
      { headerName: 'Item Name', field: 'item_name' },
      { headerName: 'Item Code', field: 'item_code' },
      { headerName: 'Category', field: 'item_category' },
      { headerName: 'Current Stock', field: 'current_stock' },
      { headerName: 'Minimum Stock', field: 'minimum_stock' },
      { headerName: 'Shortage', field: 'shortage' },
      { headerName: 'Reorder Level', field: 'reorder_level' }
    ];
    if (format === 'pdf') exportToPDF(reportData as unknown as Record< string,unknown >[], cols, 'Low Stock Alert Report', `low-stock-${new Date().toISOString().split('T')[0]}.pdf`);
    else exportToExcel(reportData as unknown as Record< string,unknown >[], cols, 'Low Stock Alert Report', `low-stock-${new Date().toISOString().split('T')[0]}.csv`);
  };

  const columnDefs = [
    { headerName: 'Item Name', field: 'item_name', filter: true, flex: 1 },
    { headerName: 'Item Code', field: 'item_code', filter: true, width: 140 },
    { headerName: 'Category', field: 'item_category', filter: true, width: 140 },
    { headerName: 'Current Stock', field: 'current_stock', filter: 'agNumberColumnFilter', width: 120, cellClass: 'number-cell' },
    { headerName: 'Minimum Stock', field: 'minimum_stock', filter: 'agNumberColumnFilter', width: 140, cellClass: 'number-cell' },
    { headerName: 'Shortage', field: 'shortage', filter: 'agNumberColumnFilter', width: 120, cellClass: 'number-cell' },
    { headerName: 'Reorder Level', field: 'reorder_level', filter: 'agNumberColumnFilter', width: 140, cellClass: 'number-cell' }
  ];

  return (
    <div className="low-stock-report">
      <div className="page-header">
        <div><h1>Low Stock Alert Report</h1><p className="page-subtitle">Items that are below minimum stock levels</p></div>
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
          <div className="mobile-low-stock-list">
            {reportData.map((item, index) => (
              <div key={item.id || item.item_code || `item-${index}`} className="low-stock-card"
                onClick={() => handleCardClick(item)} role="button" tabIndex={0}
                onKeyDown={(e: React.KeyboardEvent) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); handleCardClick(item); } }}>
                <div className="low-stock-card-content">
                  <h3 className="low-stock-item-name">{item.item_name}</h3>
                  <span className="low-stock-item-qty">{item.current_stock} {item.unit_of_measure}</span>
                </div>
              </div>
            ))}
          </div>
        </> : <div className="no-data"><AlertTriangle size={48} /><h3>No low stock items found</h3><p>All items are above their minimum stock levels.</p></div>}
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
                  <div className="stock-detail-item"><span className="stock-detail-label"><AlertTriangle size={14} /> Minimum Stock</span><span className="stock-detail-value">{selectedItem.minimum_stock} {selectedItem.unit_of_measure}</span></div>
                  <div className="stock-detail-item"><span className="stock-detail-label"><AlertTriangle size={14} /> Shortage</span><span className="stock-detail-value shortage">{selectedItem.shortage} {selectedItem.unit_of_measure}</span></div>
                  <div className="stock-detail-item"><span className="stock-detail-label"><AlertTriangle size={14} /> Reorder Level</span><span className="stock-detail-value">{selectedItem.reorder_level} {selectedItem.unit_of_measure}</span></div>
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
