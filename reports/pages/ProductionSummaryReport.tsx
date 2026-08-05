import { useState, useEffect } from 'react';
import { useQuery } from '@tanstack/react-query';
import MiniERPGrid from '../../components/common/MiniERPGrid';
import {
  Factory,
  Package,
  TrendingUp,
  FileText,
  DollarSign,
  Calendar,
  Download,
  Filter,
  BarChart3,
  CheckCircle,
  XCircle,
  X
} from 'lucide-react';

import Button from '../../components/common/Button';
import DateRangePicker from '../../components/common/DateRangePicker';
import StatCard, { StatsGrid } from '../../components/common/StatCard';
import type { DateRangeFilter } from '../../types';
import { useSettings } from '../../context/SettingsContext';
import api from '../../utils/api';
import { exportToPDF, exportToExcel } from '../../utils/exportUtils';
import './ProductionSummaryReport.css';
import '../../styles/ag-grid-status-cells.css';
import { getStatusCellClass } from '../../utils/statusCellUtils';

interface ProductionRecord {
  work_order_id?: number;
  work_order_number?: string;
  production_date?: string;
  production_order_number?: string;
  output_item_name?: string;
  item_name?: string;
  output_quantity?: number;
  completed_quantity?: number;
  scrapped_quantity?: number;
  planned_quantity?: number;
  status?: string;
}

interface ProductionSummaryData {
  production?: ProductionRecord[];
  summary?: {
    totalProductionOrders?: number;
    totalOutput?: number;
    totalCompleted?: number;
    totalScrapped?: number;
  };
}

export default function ProductionSummaryReport() {
  const [dateRange, setDateRange] = useState<DateRangeFilter>({
    fromDate: new Date(new Date().setMonth(new Date().getMonth() - 1)).toISOString().split('T')[0],
    toDate: new Date().toISOString().split('T')[0]
  });
  const [showFilters, setShowFilters] = useState(false);
  const [selectedProduction, setSelectedProduction] = useState<ProductionRecord | null>(null);
  const [showDetailModal, setShowDetailModal] = useState(false);
  const { formatCurrency } = useSettings();

  useEffect(() => {
    const handleEsc = (event: KeyboardEvent) => { if (event.key === 'Escape') setShowDetailModal(false); };
    if (showDetailModal) document.addEventListener('keydown', handleEsc);
    return () => document.removeEventListener('keydown', handleEsc);
  }, [showDetailModal]);

  const handleCardClick = (production: ProductionRecord) => { setSelectedProduction(production); setShowDetailModal(true); };

  const { data: reportData, isLoading, refetch } = useQuery<ProductionSummaryData>({
    queryKey: ['productionSummary', dateRange],
    queryFn: async () => {
      const params = new URLSearchParams();
      params.append('fromDate', dateRange.fromDate); params.append('toDate', dateRange.toDate);
      const r = await api.get(`/reports/production-summary?${params}`); return r.data.data;
    }
  });

  const handleFilterSubmit = (e: React.FormEvent) => { e.preventDefault(); refetch(); };

  const handleExport = (format = 'pdf') => {
    if (!reportData?.production) return;
    const cols = [
      { headerName: 'Production Date', field: 'production_date', valueFormatter: (p: { value: string }) => p.value ? new Date(p.value).toLocaleDateString() : '' },
      { headerName: 'Production Order', field: 'production_order_number' },
      { headerName: 'Output Item', field: 'output_item_name' },
      { headerName: 'Output Quantity', field: 'output_quantity' },
      { headerName: 'Completed Quantity', field: 'completed_quantity' },
      { headerName: 'Scrapped Quantity', field: 'scrapped_quantity' },
      { headerName: 'Status', field: 'status' }
    ];
    if (format === 'pdf') exportToPDF(reportData.production as unknown as Record< string,unknown >[], cols, 'Production Summary Report', `production-summary-${new Date().toISOString().split('T')[0]}.pdf`);
    else exportToExcel(reportData.production as unknown as Record< string,unknown >[], cols, 'Production Summary Report', `production-summary-${new Date().toISOString().split('T')[0]}.csv`);
  };

  const columnDefs = [
    { headerName: 'Production Date', field: 'production_date', filter: 'agDateColumnFilter', width: 120, valueFormatter: (p: { value: string }) => p.value ? new Date(p.value).toLocaleDateString() : '' },
    { headerName: 'Production Order', field: 'production_order_number', filter: true, width: 140 },
    { headerName: 'Output Item', field: 'output_item_name', filter: true, flex: 1 },
    { headerName: 'Output Quantity', field: 'output_quantity', filter: 'agNumberColumnFilter', width: 120, cellClass: 'number-cell' },
    { headerName: 'Completed Quantity', field: 'completed_quantity', filter: 'agNumberColumnFilter', width: 140, cellClass: 'number-cell' },
    { headerName: 'Scrapped Quantity', field: 'scrapped_quantity', filter: 'agNumberColumnFilter', width: 140, cellClass: 'number-cell' },
    { headerName: 'Status', field: 'status', filter: true, width: 120, cellClass: (p: { value: string }) => getStatusCellClass(p.value) }
  ];

  return (
    <div className="production-summary-report">
      <div className="page-header">
        <div><h1>Production Summary Report</h1><p className="page-subtitle">Comprehensive analysis of production performance</p></div>
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
      {reportData?.summary && (
        <StatsGrid className="compact">
          <StatCard icon={Factory} label="Total Production Orders" value={reportData.summary.totalProductionOrders} />
          <StatCard icon={Package} label="Total Output Quantity" value={reportData.summary.totalOutput} />
          <StatCard icon={CheckCircle} label="Completed Quantity" value={reportData.summary.totalCompleted} />
          <StatCard icon={XCircle} label="Scrapped Quantity" value={reportData.summary.totalScrapped} />
        </StatsGrid>
      )}
      <div className="report-content">
        {isLoading ? <div className="loading"><div className="spinner"></div></div>
        : reportData?.production && reportData.production.length > 0 ? <>
          <MiniERPGrid
            wrapperClassName="desktop-view ag-grid-container"
            rowData={reportData.production}
            columnDefs={columnDefs as any}
            paginationPageSize={20}
            paginationPageSizeSelector={[10, 20, 50, 100]}
          />
          <div className="mobile-sales-list">
            {reportData.production.map((production, index) => (
              <div key={production.work_order_id || production.work_order_number || `production-${index}`} className="production-card"
                onClick={() => handleCardClick(production)} role="button" tabIndex={0}
                onKeyDown={(e: React.KeyboardEvent) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); handleCardClick(production); } }}>
                <div className="production-card-content">
                  <h3 className="production-card-title">{production.work_order_number}</h3>
                  <span className={`production-card-status ${production.status?.toLowerCase().replace(' ', '-')}`}>{production.status}</span>
                </div>
              </div>
            ))}
          </div>
        </> : <div className="no-data"><Factory size={48} /><h3>No production data found</h3><p>Try adjusting your filters to see production data.</p></div>}
      </div>
      {showDetailModal && selectedProduction && (
        <div className="production-modal-overlay" onClick={() => setShowDetailModal(false)} role="dialog" aria-modal="true">
          <div className="production-modal" onClick={(e: React.MouseEvent) => e.stopPropagation()}>
            <div className="production-modal-header">
              <h2 className="production-modal-title">{selectedProduction.work_order_number}</h2>
              <button type="button" className="production-modal-close" onClick={() => setShowDetailModal(false)}><X size={24} /></button>
            </div>
            <div className="production-modal-content">
              <div className="production-detail-section">
                <div className="production-details-grid">
                  <div className="production-detail-item"><span className="production-detail-label">Item</span><span className="production-detail-value">{selectedProduction.item_name || '-'}</span></div>
                  <div className="production-detail-item"><span className="production-detail-label">Planned Quantity</span><span className="production-detail-value">{selectedProduction.planned_quantity}</span></div>
                  <div className="production-detail-item"><span className="production-detail-label">Completed Quantity</span><span className="production-detail-value">{selectedProduction.completed_quantity || 0}</span></div>
                  <div className="production-detail-item"><span className="production-detail-label">Scrapped Quantity</span><span className="production-detail-value">{selectedProduction.scrapped_quantity || 0}</span></div>
                  <div className="production-detail-item"><span className="production-detail-label">Status</span><span className="production-detail-value">{selectedProduction.status || '-'}</span></div>
                  <div className="production-detail-item"><span className="production-detail-label">Date</span><span className="production-detail-value">{selectedProduction.production_date ? new Date(selectedProduction.production_date).toLocaleDateString() : '-'}</span></div>
                </div>
              </div>
            </div>
            <div className="production-modal-actions">
              <button type="button" className="production-action-btn production-action-secondary" onClick={() => setShowDetailModal(false)}>Close</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
