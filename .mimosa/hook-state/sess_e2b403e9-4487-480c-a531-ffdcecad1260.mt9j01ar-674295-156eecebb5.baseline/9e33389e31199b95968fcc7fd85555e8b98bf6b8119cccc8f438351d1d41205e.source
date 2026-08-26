import { useState, useEffect } from 'react';
import { useQuery } from '@tanstack/react-query';
import MiniERPGrid from '../../components/common/MiniERPGrid';
import {
  Package,
  FileText,
  Calendar,
  Download,
  Filter,
  BarChart3,
  List,
  X,
  CheckCircle,
  Hash,
  Layers
} from 'lucide-react';

import Button from '../../components/common/Button';
import DateRangePicker from '../../components/common/DateRangePicker';
import type { DateRangeFilter } from '../../types';
import { useSettings } from '../../context/SettingsContext';
import api from '../../utils/api';
import { exportToPDF, exportToExcel } from '../../utils/exportUtils';
import './BOMUsageReport.css';

interface InventoryItem {
  id: number;
  item_name: string;
}

interface BOMRecord {
  bom_id?: number;
  bom_name: string;
  parent_item_name?: string;
  usage_count?: number;
  last_used_date?: string;
  total_components?: number;
  status?: string;
}

interface BOMUsageData {
  usage?: BOMRecord[];
}

export default function BOMUsageReport() {
  const [dateRange, setDateRange] = useState<DateRangeFilter>({
    fromDate: new Date(new Date().setMonth(new Date().getMonth() - 1)).toISOString().split('T')[0],
    toDate: new Date().toISOString().split('T')[0]
  });
  const [itemId, setItemId] = useState('');
  const [showFilters, setShowFilters] = useState(false);
  const [selectedBOM, setSelectedBOM] = useState<BOMRecord | null>(null);
  const [showDetailModal, setShowDetailModal] = useState(false);
  const { formatCurrency } = useSettings();

  useEffect(() => {
    const handleEsc = (event: KeyboardEvent) => { if (event.key === 'Escape') setShowDetailModal(false); };
    if (showDetailModal) document.addEventListener('keydown', handleEsc);
    return () => document.removeEventListener('keydown', handleEsc);
  }, [showDetailModal]);

  const handleCardClick = (bom: BOMRecord) => { setSelectedBOM(bom); setShowDetailModal(true); };

  const { data: items = [] } = useQuery<InventoryItem[]>({
    queryKey: ['items'], queryFn: async () => { const r = await api.get('/inventory/items'); return r.data.data || []; }
  });

  const { data: reportData, isLoading, refetch } = useQuery<BOMUsageData>({
    queryKey: ['bomUsage', dateRange, itemId],
    queryFn: async () => {
      const params = new URLSearchParams();
      params.append('fromDate', dateRange.fromDate); params.append('toDate', dateRange.toDate);
      if (itemId) params.append('itemId', itemId);
      const r = await api.get(`/reports/bom-usage?${params}`); return r.data.data;
    }
  });

  const handleFilterSubmit = (e: React.FormEvent) => { e.preventDefault(); refetch(); };

  const handleExport = (format = 'pdf') => {
    if (!reportData?.usage) return;
    const cols = [
      { headerName: 'BOM Name', field: 'bom_name' },
      { headerName: 'Parent Item', field: 'parent_item_name' },
      { headerName: 'Usage Count', field: 'usage_count' },
      { headerName: 'Last Used', field: 'last_used_date', valueFormatter: (p: { value: string }) => p.value ? new Date(p.value).toLocaleDateString() : '' },
      { headerName: 'Total Components', field: 'total_components' },
      { headerName: 'Status', field: 'status' }
    ];
    if (format === 'pdf') exportToPDF(reportData.usage as unknown as Record< string,unknown >[], cols, 'BOM Usage Report', `bom-usage-${new Date().toISOString().split('T')[0]}.pdf`);
    else exportToExcel(reportData.usage as unknown as Record< string,unknown >[], cols, 'BOM Usage Report', `bom-usage-${new Date().toISOString().split('T')[0]}.csv`);
  };

  const columnDefs = [
    { headerName: 'BOM Name', field: 'bom_name', filter: true, flex: 1 },
    { headerName: 'Parent Item', field: 'parent_item_name', filter: true, width: 180 },
    { headerName: 'Usage Count', field: 'usage_count', filter: 'agNumberColumnFilter', width: 120, cellClass: 'number-cell' },
    { headerName: 'Last Used', field: 'last_used_date', filter: 'agDateColumnFilter', width: 140, valueFormatter: (p: { value: string }) => p.value ? new Date(p.value).toLocaleDateString() : '' },
    { headerName: 'Total Components', field: 'total_components', filter: 'agNumberColumnFilter', width: 140, cellClass: 'number-cell' },
    { headerName: 'Status', field: 'status', filter: true, width: 120 }
  ];

  return (
    <div className="bom-usage-report">
      <div className="page-header">
        <div><h1>BOM Usage Report</h1><p className="page-subtitle">Track usage of Bill of Materials in production</p></div>
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
            <div className="filter-group"><label>Parent Item</label>
              <select value={itemId} onChange={(e: React.ChangeEvent<HTMLSelectElement>) => setItemId(e.target.value)} className="filter-select">
                <option value="">All Items</option>
                {items.map(i => <option key={i.id} value={i.id}>{i.item_name}</option>)}
              </select>
            </div>
            <Button type="submit" variant="primary" className="apply-filters-btn">Apply Filters</Button>
          </div>
        </form>
      )}
      <div className="report-content">
        {isLoading ? <div className="loading"><div className="spinner"></div></div>
        : reportData?.usage && reportData.usage.length > 0 ? <>
          <MiniERPGrid
            wrapperClassName="desktop-view ag-grid-container"
            rowData={reportData.usage}
            columnDefs={columnDefs as any}
            paginationPageSize={20}
            paginationPageSizeSelector={[10, 20, 50, 100]}
          />
          <div className="mobile-bom-usage-list">
            {reportData.usage.map((bom, index) => (
              <div key={`${bom.bom_id || bom.bom_name}-${index}`} className="bom-usage-card"
                onClick={() => handleCardClick(bom)} role="button" tabIndex={0}
                onKeyDown={(e: React.KeyboardEvent) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); handleCardClick(bom); } }}>
                <div className="bom-usage-card-content">
                  <h3 className="bom-usage-name">{bom.bom_name}</h3>
                  <span className="bom-usage-count">{bom.usage_count} uses</span>
                </div>
              </div>
            ))}
          </div>
        </> : <div className="no-data"><List size={48} /><h3>No BOM usage data found</h3><p>Try adjusting your filters to see BOM usage data.</p></div>}
      </div>
      {showDetailModal && selectedBOM && (
        <div className="bom-modal-overlay" onClick={() => setShowDetailModal(false)} role="dialog" aria-modal="true">
          <div className="bom-modal" onClick={(e: React.MouseEvent) => e.stopPropagation()}>
            <div className="bom-modal-header">
              <h2 className="bom-modal-title">{selectedBOM.bom_name}</h2>
              <button type="button" className="bom-modal-close" onClick={() => setShowDetailModal(false)}><X size={24} /></button>
            </div>
            <div className="bom-modal-content">
              <div className="bom-detail-section">
                <div className="bom-details-grid">
                  <div className="bom-detail-item"><span className="bom-detail-label"><Package size={14} /> Parent Item</span><span className="bom-detail-value">{selectedBOM.parent_item_name || '-'}</span></div>
                  <div className="bom-detail-item"><span className="bom-detail-label"><Hash size={14} /> Usage Count</span><span className="bom-detail-value">{selectedBOM.usage_count}</span></div>
                  <div className="bom-detail-item"><span className="bom-detail-label"><Calendar size={14} /> Last Used</span><span className="bom-detail-value">{selectedBOM.last_used_date ? new Date(selectedBOM.last_used_date).toLocaleDateString() : '-'}</span></div>
                  <div className="bom-detail-item"><span className="bom-detail-label"><Layers size={14} /> Total Components</span><span className="bom-detail-value">{selectedBOM.total_components}</span></div>
                  <div className="bom-detail-item"><span className="bom-detail-label"><CheckCircle size={14} /> Status</span><span className="bom-detail-value">{selectedBOM.status || '-'}</span></div>
                </div>
              </div>
            </div>
            <div className="bom-modal-actions">
              <button type="button" className="bom-action-btn bom-action-secondary" onClick={() => setShowDetailModal(false)}>Close</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
