import { useState, useEffect } from 'react';
import { useQuery } from '@tanstack/react-query';
import MiniERPGrid from '../../components/common/MiniERPGrid';
import {
  Package,
  Download,
  Filter,
  X,
  Tag,
  Hash,
  Calendar,
  MapPin,
  ArrowRight,
  PackagePlus,
  PackageMinus
} from 'lucide-react';

import Button from '../../components/common/Button';
import DateRangePicker from '../../components/common/DateRangePicker';
import StatCard, { StatsGrid } from '../../components/common/StatCard';
import type { DateRangeFilter } from '../../types';
import { useSettings } from '../../context/SettingsContext';
import api from '../../utils/api';
import { exportToPDF, exportToExcel } from '../../utils/exportUtils';
import './InventoryMovementReport.css';

interface InventoryItem {
  id: number;
  item_name: string;
}

interface Warehouse {
  id: number;
  warehouse_name: string;
}

interface MovementRecord {
  id?: number;
  item_code?: string;
  item_name: string;
  item_category?: string;
  unit_of_measure?: string;
  movement_date?: string;
  warehouse_name?: string;
  movement_type?: string;
  reference?: string;
  quantity?: number;
  unit_cost?: number;
  total_value?: number;
}

interface MovementSummary {
  totalInbound?: number;
  totalOutbound?: number;
  netMovement?: number;
}

interface MovementReportData {
  movements?: MovementRecord[];
  summary?: MovementSummary;
}

export default function InventoryMovementReport() {
  const [dateRange, setDateRange] = useState<DateRangeFilter>({
    fromDate: new Date(new Date().setMonth(new Date().getMonth() - 1)).toISOString().split('T')[0],
    toDate: new Date().toISOString().split('T')[0]
  });
  const [itemId, setItemId] = useState('');
  const [warehouseId, setWarehouseId] = useState('');
  const [movementType, setMovementType] = useState('all');
  const [showFilters, setShowFilters] = useState(false);
  const [selectedMovement, setSelectedMovement] = useState<MovementRecord | null>(null);
  const [showDetailModal, setShowDetailModal] = useState(false);
  const { formatCurrency } = useSettings();

  useEffect(() => {
    const handleEsc = (event: KeyboardEvent) => { if (event.key === 'Escape') setShowDetailModal(false); };
    if (showDetailModal) document.addEventListener('keydown', handleEsc);
    return () => document.removeEventListener('keydown', handleEsc);
  }, [showDetailModal]);

  const handleCardClick = (movement: MovementRecord) => { setSelectedMovement(movement); setShowDetailModal(true); };

  const { data: items = [] } = useQuery<InventoryItem[]>({
    queryKey: ['items'], queryFn: async () => { const r = await api.get('/inventory/items'); return r.data.data || []; }
  });

  const { data: warehouses = [] } = useQuery<Warehouse[]>({
    queryKey: ['warehouses'], queryFn: async () => { const r = await api.get('/inventory/warehouses'); return r.data.data || []; }
  });

  const { data: reportData, isLoading, refetch } = useQuery<MovementReportData>({
    queryKey: ['inventoryMovement', dateRange, itemId, warehouseId, movementType],
    queryFn: async () => {
      const params = new URLSearchParams();
      params.append('fromDate', dateRange.fromDate); params.append('toDate', dateRange.toDate);
      if (itemId) params.append('itemId', itemId);
      if (warehouseId) params.append('warehouseId', warehouseId);
      if (movementType !== 'all') params.append('movementType', movementType);
      const r = await api.get(`/reports/inventory-movement?${params}`); return r.data.data;
    }
  });

  const handleFilterSubmit = (e: React.FormEvent) => { e.preventDefault(); refetch(); };

  const handleExport = (format = 'pdf') => {
    if (!reportData?.movements) return;
    const cols = [
      { headerName: 'Date', field: 'movement_date', valueFormatter: (p: { value: string }) => p.value ? new Date(p.value).toLocaleDateString() : '' },
      { headerName: 'Item Name', field: 'item_name' },
      { headerName: 'Item Code', field: 'item_code' },
      { headerName: 'Warehouse', field: 'warehouse_name' },
      { headerName: 'Movement Type', field: 'movement_type' },
      { headerName: 'Reference', field: 'reference' },
      { headerName: 'Quantity', field: 'quantity' },
      { headerName: 'Unit Cost', field: 'unit_cost', valueFormatter: (p: { value: number }) => formatCurrency(p.value || 0) },
      { headerName: 'Total Value', field: 'total_value', valueFormatter: (p: { value: number }) => formatCurrency(p.value || 0) }
    ];
    if (format === 'pdf') exportToPDF(reportData.movements as unknown as Record<string, unknown>[], cols, 'Inventory Movement Report', `inventory-movement-${new Date().toISOString().split('T')[0]}.pdf`);
    else exportToExcel(reportData.movements as unknown as Record<string, unknown>[], cols, 'Inventory Movement Report', `inventory-movement-${new Date().toISOString().split('T')[0]}.csv`);
  };

  const columnDefs = [
    { headerName: 'Date', field: 'movement_date', filter: 'agDateColumnFilter', width: 120, valueFormatter: (p: { value: string }) => p.value ? new Date(p.value).toLocaleDateString() : '' },
    { headerName: 'Item Name', field: 'item_name', filter: true, flex: 1 },
    { headerName: 'Item Code', field: 'item_code', filter: true, width: 120 },
    { headerName: 'Warehouse', field: 'warehouse_name', filter: true, width: 140 },
    { headerName: 'Movement Type', field: 'movement_type', filter: true, width: 120, cellClass: (p: { value: string }) => { const t = p.value?.toLowerCase(); if (t === 'in') return 'movement-in'; if (t === 'out') return 'movement-out'; return ''; } },
    { headerName: 'Reference', field: 'reference', filter: true, width: 140 },
    { headerName: 'Quantity', field: 'quantity', filter: 'agNumberColumnFilter', width: 100, cellClass: 'number-cell' },
    { headerName: 'Unit Cost', field: 'unit_cost', filter: 'agNumberColumnFilter', width: 120, valueFormatter: (p: { value: number }) => formatCurrency(p.value || 0), cellClass: 'amount-cell' },
    { headerName: 'Total Value', field: 'total_value', filter: 'agNumberColumnFilter', width: 140, valueFormatter: (p: { value: number }) => formatCurrency(p.value || 0), cellClass: 'amount-cell' }
  ];

  return (
    <div className="inventory-movement-report">
      <div className="page-header">
        <div><h1>Inventory Movement Report</h1><p className="page-subtitle">Track stock movements across all warehouses</p></div>
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
            <div className="filter-group"><label>Item</label>
              <select value={itemId} onChange={(e: React.ChangeEvent<HTMLSelectElement>) => setItemId(e.target.value)} className="filter-select">
                <option value="">All Items</option>
                {items.map(i => <option key={i.id} value={i.id}>{i.item_name}</option>)}
              </select>
            </div>
            <div className="filter-group"><label>Warehouse</label>
              <select value={warehouseId} onChange={(e: React.ChangeEvent<HTMLSelectElement>) => setWarehouseId(e.target.value)} className="filter-select">
                <option value="">All Warehouses</option>
                {warehouses.map(w => <option key={w.id} value={w.id}>{w.warehouse_name}</option>)}
              </select>
            </div>
            <div className="filter-group"><label>Movement Type</label>
              <select value={movementType} onChange={(e: React.ChangeEvent<HTMLSelectElement>) => setMovementType(e.target.value)} className="filter-select">
                <option value="all">All Types</option><option value="in">Inbound</option><option value="out">Outbound</option>
              </select>
            </div>
            <Button type="submit" variant="primary" className="apply-filters-btn">Apply Filters</Button>
          </div>
        </form>
      )}
      {reportData?.summary && (
        <StatsGrid className="compact">
          <StatCard icon={PackagePlus} label="Total Inbound" value={reportData.summary.totalInbound} />
          <StatCard icon={PackageMinus} label="Total Outbound" value={reportData.summary.totalOutbound} />
          <StatCard icon={Package} label="Net Movement" value={reportData.summary.netMovement} />
        </StatsGrid>
      )}
      <div className="report-content">
        {isLoading ? <div className="loading"><div className="spinner"></div></div>
        : reportData?.movements && reportData.movements.length > 0 ? <>
          <MiniERPGrid
            wrapperClassName="desktop-view ag-grid-container"
            rowData={reportData.movements}
            columnDefs={columnDefs as any}
            paginationPageSize={20}
            paginationPageSizeSelector={[10, 20, 50, 100]}
          />
          <div className="mobile-inventory-movement-list">
            {reportData.movements.map((movement, index) => (
              <div key={`${movement.id || movement.item_code}-${index}`} className="inventory-movement-card"
                onClick={() => handleCardClick(movement)} role="button" tabIndex={0}
                onKeyDown={(e: React.KeyboardEvent) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); handleCardClick(movement); } }}>
                <div className="inventory-movement-card-content">
                  <h3 className="movement-item-name">{movement.item_name}</h3>
                  <span className={`movement-item-qty ${movement.movement_type?.toLowerCase().includes('in') ? 'in' : 'out'}`}>
                    {movement.movement_type?.toLowerCase().includes('in') ? '+' : '-'}{movement.quantity} {movement.unit_of_measure}
                  </span>
                </div>
              </div>
            ))}
          </div>
        </> : <div className="no-data"><Package size={48} /><h3>No inventory movement data found</h3><p>Try adjusting your filters to see inventory movement data.</p></div>}
      </div>
      {showDetailModal && selectedMovement && (
        <div className="movement-modal-overlay" onClick={() => setShowDetailModal(false)} role="dialog" aria-modal="true">
          <div className="movement-modal" onClick={(e: React.MouseEvent) => e.stopPropagation()}>
            <div className="movement-modal-header">
              <h2 className="movement-modal-title">{selectedMovement.item_name}</h2>
              <button type="button" className="movement-modal-close" onClick={() => setShowDetailModal(false)}><X size={24} /></button>
            </div>
            <div className="movement-modal-content">
              <div className="movement-detail-section">
                <div className="movement-details-grid">
                  <div className="movement-detail-item"><span className="movement-detail-label"><Tag size={14} /> Item Code</span><span className="movement-detail-value">{selectedMovement.item_code || '-'}</span></div>
                  <div className="movement-detail-item"><span className="movement-detail-label"><Package size={14} /> Category</span><span className="movement-detail-value">{selectedMovement.item_category || '-'}</span></div>
                  <div className="movement-detail-item"><span className="movement-detail-label"><Hash size={14} /> UOM</span><span className="movement-detail-value">{selectedMovement.unit_of_measure || '-'}</span></div>
                  <div className="movement-detail-item"><span className="movement-detail-label"><ArrowRight size={14} /> Movement Type</span><span className="movement-detail-value">{selectedMovement.movement_type || '-'}</span></div>
                  <div className="movement-detail-item"><span className="movement-detail-label"><Hash size={14} /> Quantity</span><span className="movement-detail-value">{selectedMovement.quantity} {selectedMovement.unit_of_measure}</span></div>
                  <div className="movement-detail-item"><span className="movement-detail-label"><MapPin size={14} /> Warehouse</span><span className="movement-detail-value">{selectedMovement.warehouse_name || '-'}</span></div>
                  <div className="movement-detail-item"><span className="movement-detail-label"><Calendar size={14} /> Date</span><span className="movement-detail-value">{selectedMovement.movement_date ? new Date(selectedMovement.movement_date).toLocaleDateString() : '-'}</span></div>
                  <div className="movement-detail-item"><span className="movement-detail-label">Reference</span><span className="movement-detail-value">{selectedMovement.reference || '-'}</span></div>
                </div>
              </div>
            </div>
            <div className="movement-modal-actions">
              <button type="button" className="movement-action-btn movement-action-secondary" onClick={() => setShowDetailModal(false)}>Close</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
