import { useState, useEffect } from 'react';
import { useQuery } from '@tanstack/react-query';
import MiniERPGrid from '../../components/common/MiniERPGrid';
import {
  ShoppingCart,
  TrendingUp,
  FileText,
  DollarSign,
  Calendar,
  Download,
  Filter,
  BarChart3,
  Package,
  X
} from 'lucide-react';

import Button from '../../components/common/Button';
import DateRangePicker from '../../components/common/DateRangePicker';
import StatCard, { StatsGrid } from '../../components/common/StatCard';
import type { DateRangeFilter } from '../../types';
import { useSettings } from '../../context/SettingsContext';
import api from '../../utils/api';
import { exportToPDF, exportToExcel } from '../../utils/exportUtils';
import './PurchaseSummaryReport.css';
import '../../styles/ag-grid-status-cells.css';
import { getStatusCellClass } from '../../utils/statusCellUtils';

interface Supplier {
  id: number;
  supplier_name: string;
}

interface InventoryItem {
  id: number;
  item_name: string;
}

interface PurchaseRecord {
  po_id?: number;
  po_number?: string;
  purchase_date?: string;
  purchase_order_number?: string;
  supplier_name?: string;
  total_cost?: number;
  total_items?: number;
  received_amount?: number;
  balance_amount?: number;
  status?: string;
  total?: number;
  items_count?: number;
  po_date?: string;
}

interface PurchaseSummaryData {
  purchases?: PurchaseRecord[];
  summary?: {
    totalOrders?: number;
    totalCost?: number;
    totalItems?: number;
    averageOrderValue?: number;
    returnCount?: number;
    returnQuantity?: number;
    returnValue?: number;
  };
}

export default function PurchaseSummaryReport() {
  const [dateRange, setDateRange] = useState<DateRangeFilter>({
    fromDate: new Date(new Date().setMonth(new Date().getMonth() - 3)).toISOString().split('T')[0],
    toDate: new Date().toISOString().split('T')[0]
  });
  const [supplierId, setSupplierId] = useState('');
  const [itemId, setItemId] = useState('');
  const [showFilters, setShowFilters] = useState(false);
  const [selectedPurchase, setSelectedPurchase] = useState<PurchaseRecord | null>(null);
  const [showDetailModal, setShowDetailModal] = useState(false);
  const { formatCurrency } = useSettings();

  useEffect(() => {
    const handleEsc = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setShowDetailModal(false);
    };
    if (showDetailModal) document.addEventListener('keydown', handleEsc);
    return () => document.removeEventListener('keydown', handleEsc);
  }, [showDetailModal]);

  const handleCardClick = (purchase: PurchaseRecord) => {
    setSelectedPurchase(purchase);
    setShowDetailModal(true);
  };

  const { data: suppliers = [] } = useQuery<Supplier[]>({
    queryKey: ['suppliers'],
    queryFn: async () => { const r = await api.get('/suppliers'); return r.data.data || []; }
  });

  const { data: items = [] } = useQuery<InventoryItem[]>({
    queryKey: ['items'],
    queryFn: async () => { const r = await api.get('/inventory/items'); return r.data.data || []; }
  });

  const { data: reportData, isLoading, refetch } = useQuery<PurchaseSummaryData>({
    queryKey: ['purchaseSummary', dateRange, supplierId, itemId],
    queryFn: async () => {
      const params = new URLSearchParams();
      params.append('fromDate', dateRange.fromDate); params.append('toDate', dateRange.toDate);
      if (supplierId) params.append('supplierId', supplierId);
      if (itemId) params.append('itemId', itemId);
      const r = await api.get(`/reports/purchase-summary?${params}`);
      return r.data.data;
    }
  });

  const handleFilterSubmit = (e: React.FormEvent) => { e.preventDefault(); refetch(); };

  const handleExport = (format = 'pdf') => {
    if (!reportData?.purchases) return;
    const cols = [
      { headerName: 'PO Date', field: 'purchase_date', valueFormatter: (p: { value: string }) => p.value ? new Date(p.value).toLocaleDateString() : '' },
      { headerName: 'PO Number', field: 'purchase_order_number' },
      { headerName: 'Supplier', field: 'supplier_name' },
      { headerName: 'Total Cost', field: 'total_cost', valueFormatter: (p: { value: number }) => formatCurrency(p.value || 0) },
      { headerName: 'Items', field: 'total_items' },
      { headerName: 'Received Amount', field: 'received_amount', valueFormatter: (p: { value: number }) => formatCurrency(p.value || 0) },
      { headerName: 'Balance', field: 'balance_amount', valueFormatter: (p: { value: number }) => formatCurrency(p.value || 0) },
      { headerName: 'Status', field: 'status' }
    ];
    if (format === 'pdf') exportToPDF(reportData.purchases as unknown as Record<string, unknown>[], cols, 'Purchase Summary Report', `purchase-summary-${new Date().toISOString().split('T')[0]}.pdf`);
    else exportToExcel(reportData.purchases as unknown as Record<string, unknown>[], cols, 'Purchase Summary Report', `purchase-summary-${new Date().toISOString().split('T')[0]}.csv`);
  };

  const columnDefs = [
    { headerName: 'PO Date', field: 'purchase_date', filter: 'agDateColumnFilter', width: 120, valueFormatter: (p: { value: string }) => p.value ? new Date(p.value).toLocaleDateString() : '' },
    { headerName: 'PO Number', field: 'purchase_order_number', filter: true, width: 140 },
    { headerName: 'Supplier', field: 'supplier_name', filter: true, flex: 1 },
    { headerName: 'Total Cost', field: 'total_cost', filter: 'agNumberColumnFilter', width: 140, valueFormatter: (p: { value: number }) => formatCurrency(p.value || 0), cellClass: 'amount-cell' },
    { headerName: 'Items', field: 'total_items', filter: 'agNumberColumnFilter', width: 100, cellClass: 'number-cell' },
    { headerName: 'Received Amount', field: 'received_amount', filter: 'agNumberColumnFilter', width: 140, valueFormatter: (p: { value: number }) => formatCurrency(p.value || 0), cellClass: 'amount-cell' },
    { headerName: 'Balance', field: 'balance_amount', filter: 'agNumberColumnFilter', width: 140, valueFormatter: (p: { value: number }) => formatCurrency(p.value || 0), cellClass: 'amount-cell' },
    { headerName: 'Status', field: 'status', filter: true, width: 120, cellClass: (p: { value: string }) => getStatusCellClass(p.value) }
  ];

  return (
    <div className="purchase-summary-report">
      <div className="page-header">
        <div><h1>Purchase Summary Report</h1><p className="page-subtitle">Comprehensive analysis of purchase performance</p></div>
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
            <div className="filter-group"><label>Supplier</label>
              <select value={supplierId} onChange={(e: React.ChangeEvent<HTMLSelectElement>) => setSupplierId(e.target.value)} className="filter-select">
                <option value="">All Suppliers</option>
                {suppliers.map(s => <option key={s.id} value={s.id}>{s.supplier_name}</option>)}
              </select>
            </div>
            <div className="filter-group"><label>Item</label>
              <select value={itemId} onChange={(e: React.ChangeEvent<HTMLSelectElement>) => setItemId(e.target.value)} className="filter-select">
                <option value="">All Items</option>
                {items.map(i => <option key={i.id} value={i.id}>{i.item_name}</option>)}
              </select>
            </div>
            <Button type="submit" variant="primary" className="apply-filters-btn">Apply Filters</Button>
          </div>
        </form>
      )}
      {reportData?.summary && (
        <StatsGrid className="compact">
          <StatCard icon={FileText} label="Total Orders" value={reportData.summary.totalOrders} />
          <StatCard icon={DollarSign} label="Total Purchase Cost" value={formatCurrency(reportData.summary.totalCost)} />
          <StatCard icon={Package} label="Items Purchased" value={reportData.summary.totalItems} />
          <StatCard icon={TrendingUp} label="Avg. Order Value" value={formatCurrency(reportData.summary.averageOrderValue)} />
          {reportData.summary.returnCount > 0 && (
            <StatCard icon={ShoppingCart} label="Returns" value={`${reportData.summary.returnCount} (${reportData.summary.returnQuantity?.toFixed(1)} qty)`}
              subtitle={`Value: ${formatCurrency(reportData.summary.returnValue)}`} style={{ borderColor: '#f59e0b' }} />
          )}
        </StatsGrid>
      )}
      <div className="report-content">
        {isLoading ? <div className="loading"><div className="spinner"></div></div>
        : reportData?.purchases && reportData.purchases.length > 0 ? <>
          <MiniERPGrid
            wrapperClassName="desktop-view ag-grid-container"
            rowData={reportData.purchases}
            columnDefs={columnDefs as any}
            paginationPageSize={20}
            paginationPageSizeSelector={[10, 20, 50, 100]}
          />
          <div className="mobile-sales-list">
            {reportData.purchases.map((purchase, index) => (
              <div key={purchase.po_id || purchase.po_number || `purchase-${index}`} className="purchase-card"
                onClick={() => handleCardClick(purchase)} role="button" tabIndex={0}
                onKeyDown={(e: React.KeyboardEvent) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); handleCardClick(purchase); } }}>
                <div className="purchase-card-content">
                  <h3 className="purchase-card-title">{purchase.po_number}</h3>
                  <span className="purchase-card-amount">{formatCurrency(purchase.total || 0)}</span>
                </div>
              </div>
            ))}
          </div>
        </> : <div className="no-data"><ShoppingCart size={48} /><h3>No purchase data found</h3><p>Try adjusting your filters to see purchase data.</p></div>}
      </div>
      {showDetailModal && selectedPurchase && (
        <div className="purchase-modal-overlay" onClick={() => setShowDetailModal(false)} role="dialog" aria-modal="true">
          <div className="purchase-modal" onClick={(e: React.MouseEvent) => e.stopPropagation()}>
            <div className="purchase-modal-header">
              <h2 className="purchase-modal-title">{selectedPurchase.po_number}</h2>
              <button type="button" className="purchase-modal-close" onClick={() => setShowDetailModal(false)}><X size={24} /></button>
            </div>
            <div className="purchase-modal-content">
              <div className="purchase-detail-section">
                <div className="purchase-details-grid">
                  <div className="purchase-detail-item"><span className="purchase-detail-label">Supplier</span><span className="purchase-detail-value">{selectedPurchase.supplier_name || '-'}</span></div>
                  <div className="purchase-detail-item"><span className="purchase-detail-label">Date</span><span className="purchase-detail-value">{selectedPurchase.po_date ? new Date(selectedPurchase.po_date).toLocaleDateString() : '-'}</span></div>
                  <div className="purchase-detail-item"><span className="purchase-detail-label">Status</span><span className="purchase-detail-value">{selectedPurchase.status || '-'}</span></div>
                  <div className="purchase-detail-item"><span className="purchase-detail-label">Total</span><span className="purchase-detail-value">{formatCurrency(selectedPurchase.total || 0)}</span></div>
                  <div className="purchase-detail-item"><span className="purchase-detail-label">Items</span><span className="purchase-detail-value">{selectedPurchase.items_count || 0}</span></div>
                </div>
              </div>
            </div>
            <div className="purchase-modal-actions">
              <button type="button" className="purchase-action-btn purchase-action-secondary" onClick={() => setShowDetailModal(false)}>Close</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
