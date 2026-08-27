import { useState, useMemo } from 'react';

import { useQuery } from '@tanstack/react-query';
import MiniERPGrid from '../../components/common/MiniERPGrid';
import {
  TrendingUp, TrendingDown, Minus, Package,
  AlertTriangle, RefreshCw
} from 'lucide-react';

import SearchableSelect from '../../components/common/SearchableSelect';
import { useSettings } from '../../context/SettingsContext';
import { useMobileDetection } from '../../hooks/useMobileDetection';
import { useTranslation } from '../../hooks/useTranslation';
import api from '../../utils/api';
import { getStockCellClass, getForecastRecommendationClass } from '../../utils/statusCellUtils';
import './DemandForecast.css';
import '../../styles/ag-grid-status-cells.css';

interface ForecastItem {
  itemId: number;
  itemCode: string;
  itemName: string;
  category: string;
  currentStock: number;
  predictedDemand: {
    nextWeek: number;
    nextMonth: number;
    nextQuarter: number;
  };
  trend: 'growing' | 'stable' | 'declining';
  trendPercentage: number;
  confidence: number;
  recommendation: 'order_now' | 'order_soon' | 'monitor' | 'adequate';
  lastUpdated: string;
}

interface InventoryItem {
  category?: string;
  [key: string]: unknown;
}

interface CellStyleParams {
  data: ForecastItem;
  value: number;
}

function TrendCellRenderer(props: { data: ForecastItem }) {
  const { trend, trendPercentage } = props.data;
  if (trend === 'growing') {
    return <span className="trend-cell growing"><TrendingUp size={14} /> {trendPercentage}%</span>;
  }
  if (trend === 'declining') {
    return <span className="trend-cell declining"><TrendingDown size={14} /> {trendPercentage}%</span>;
  }
  return <span className="trend-cell stable"><Minus size={14} /> 0%</span>;
}

function ConfidenceCellRenderer(props: { data: ForecastItem }) {
  const confidence = props.data.confidence;
  const color = confidence >= 80 ? '#22c55e' : confidence >= 60 ? '#eab308' : '#ef4444';
  return (
    <div className="confidence-cell">
      <div className="confidence-bar">
        <div className="confidence-fill" style={{ width: `${confidence}%`, background: color }} />
      </div>
      <span>{confidence}%</span>
    </div>
  );
}

function RecommendationCellRenderer(props: { data: ForecastItem }) {
  const { recommendation } = props.data;
  const labels: Record<string, { text: string }> = {
    order_now: { text: 'Order Now' },
    order_soon: { text: 'Order Soon' },
    monitor: { text: 'Monitor' },
    adequate: { text: 'Adequate' }
  };
  const label = labels[recommendation] || labels.monitor;
  return <span>{label.text}</span>;
}

function CompactForecastCard({ item, formatCurrency }: { item: ForecastItem; formatCurrency: (v: number) => string }) {
  const trendIcon = item.trend === 'growing' ? <TrendingUp size={16} className="trend-icon growing" /> :
    item.trend === 'declining' ? <TrendingDown size={16} className="trend-icon declining" /> :
    <Minus size={16} className="trend-icon stable" />;

  const stockRatio = item.predictedDemand.nextMonth > 0
    ? item.currentStock / item.predictedDemand.nextMonth
    : 1;

  const stockColor = stockRatio < 0.3 ? '#dc2626' : stockRatio < 0.5 ? '#d97706' : '#16a34a';

  return (
    <div className="compact-forecast-card">
      <div className="card-header">
        <div className="card-title-group">
          <span className="card-item-name">{item.itemName}</span>
          <span className="card-item-code">{item.itemCode}</span>
        </div>
        {trendIcon}
      </div>
      <div className="card-body">
        <div className="card-stat">
          <span className="card-stat-label">Stock</span>
          <span className="card-stat-value" style={{ color: stockColor }}>{item.currentStock}</span>
        </div>
        <div className="card-stat">
          <span className="card-stat-label">Predicted (Mo)</span>
          <span className="card-stat-value">{item.predictedDemand.nextMonth}</span>
        </div>
        <div className="card-stat">
          <span className="card-stat-label">Confidence</span>
          <span className="card-stat-value">{item.confidence}%</span>
        </div>
      </div>
      <div className="card-footer">
        <span className={`compact-rec-badge ${item.recommendation}`}>
          {item.recommendation === 'order_now' ? 'Order Now' :
           item.recommendation === 'order_soon' ? 'Order Soon' :
           item.recommendation === 'monitor' ? 'Monitor' : 'Adequate'}
        </span>
        <span className="card-category">{item.category}</span>
      </div>
    </div>
  );
}

function GridSkeleton() {
  return (
    <div className="ag-grid-placeholder">
      <div className="ag-grid-skeleton">
        <div className="skeleton-header" />
        {Array.from({ length: 6 }).map((_, i) => (
          <div className="skeleton-row" key={i}>
            <div className="skeleton-cell" />
            <div className="skeleton-cell" />
            <div className="skeleton-cell" />
          </div>
        ))}
      </div>
    </div>
  );
}

export default function DemandForecast() {
  const { formatCurrency } = useSettings();
  const { t } = useTranslation();
  const { isMobile } = useMobileDetection();
  const [filters, setFilters] = useState({
    category: '',
    trend: '',
    recommendation: ''
  });

  const { data: items = [] } = useQuery<InventoryItem[]>({
    queryKey: ['items-all'],
    queryFn: async () => {
      const response = await api.get('/inventory/items');
      return response.data.data || [];
    }
  });

  const categories = useMemo(() =>
    [...new Set(items.map(i => i.category).filter(Boolean))],
    [items]
  );

  const { data: forecasts = [], isLoading, error, refetch } = useQuery<ForecastItem[]>({
    queryKey: ['forecasts', 'demand', filters],
    queryFn: async () => {
      const params = new URLSearchParams();
      if (filters.category) params.append('category', filters.category);
      if (filters.trend) params.append('trend', filters.trend);
      if (filters.recommendation) params.append('recommendation', filters.recommendation);
      const response = await api.get(`/forecasts/demand?${params}`);
      return response.data.data || [];
    }
  });

  const columns = useMemo(() => [
    { field: 'itemCode', headerName: 'Code', width: 100 },
    { field: 'itemName', headerName: 'Item Name', flex: 1, minWidth: 150 },
    { field: 'category', headerName: 'Category', width: 130 },
    {
      field: 'currentStock',
      headerName: 'Stock',
      width: 90,
      cellClass: (params: CellStyleParams) => {
        const predicted = params.data?.predictedDemand?.nextMonth || 0;
        return getStockCellClass(params.value, predicted > 0 ? predicted : 0);
      }
    },
    { field: 'predictedDemand.nextWeek', headerName: 'Predicted (Week)', width: 130 },
    { field: 'predictedDemand.nextMonth', headerName: 'Predicted (Month)', width: 140 },
    { field: 'predictedDemand.nextQuarter', headerName: 'Predicted (Quarter)', width: 140 },
    {
      field: 'trend',
      headerName: 'Trend',
      width: 120,
      cellRenderer: TrendCellRenderer as any
    },
    {
      field: 'confidence',
      headerName: 'Confidence',
      width: 120,
      cellRenderer: ConfidenceCellRenderer as any
    },
    {
      field: 'recommendation',
      headerName: 'Recommendation',
      width: 140,
      cellRenderer: RecommendationCellRenderer as any,
      cellClass: (params: any) => getForecastRecommendationClass(params.value)
    }
  ] as any, []);

  if (error) {
    return (
      <div className="demand-forecast-page">
        <div className="page-header">
          <h1>{t('forecasts.demandTitle')}</h1>
        </div>
        <div className="error-state">
          <AlertTriangle size={32} />
          <p>{t('forecasts.loadError')}</p>
          <button className="btn-refresh" onClick={() => refetch()}>
            <RefreshCw size={16} /> {t('forecasts.retry')}
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="demand-forecast-page">
      <div className="page-header">
        <h1>{t('forecasts.demandTitle')}</h1>
      </div>

      <div className="filters-bar">
        <div className="filter-group">
          <label>{t('forecasts.category')}</label>
          <SearchableSelect
            name="category"
            value={filters.category}
            onChange={(e) => setFilters(f => ({ ...f, category: String(e.target.value) }))}
            options={categories.map((c: string) => ({ value: c, label: c }))}
            placeholder={t('forecasts.allCategories')}
          />
        </div>

        <div className="filter-group">
          <label>{t('forecasts.trendLabel')}</label>
          <SearchableSelect
            name="trend"
            value={filters.trend}
            onChange={(e) => setFilters(f => ({ ...f, trend: String(e.target.value) }))}
            options={[
              { value: 'growing', label: 'Growing' },
              { value: 'stable', label: 'Stable' },
              { value: 'declining', label: 'Declining' }
            ]}
            placeholder={t('forecasts.allTrends')}
          />
        </div>

        <div className="filter-group">
          <label>{t('forecasts.status')}</label>
          <SearchableSelect
            name="recommendation"
            value={filters.recommendation}
            onChange={(e) => setFilters(f => ({ ...f, recommendation: String(e.target.value) }))}
            options={[
              { value: 'order_now', label: 'Order Now' },
              { value: 'order_soon', label: 'Order Soon' },
              { value: 'monitor', label: 'Monitor' },
              { value: 'adequate', label: 'Adequate' }
            ]}
            placeholder={t('forecasts.allStatus')}
          />
        </div>
      </div>

      {isMobile ? (
        isLoading ? (
          <div className="compact-list">
            {Array.from({ length: 6 }).map((_, i) => (
              <div key={i} className="compact-forecast-card skeleton-pulse">
                <div className="card-header">
                  <div className="skeleton-line medium" />
                </div>
                <div className="card-body">
                  <div className="skeleton-line short" />
                  <div className="skeleton-line short" />
                </div>
              </div>
            ))}
          </div>
        ) : forecasts.length === 0 ? (
          <div className="empty-state">
            <Package size={40} />
            <p>{t('forecasts.noForecasts')}</p>
          </div>
        ) : (
          <div className="compact-list">
            {forecasts.map(item => (
              <CompactForecastCard
                key={item.itemId}
                item={item}
                formatCurrency={formatCurrency}
              />
            ))}
          </div>
        )
      ) : isLoading ? (
        <GridSkeleton />
      ) : (
        <MiniERPGrid
          wrapperClassName="forecast-grid"
          rowData={forecasts}
          columnDefs={columns}
          paginationPageSize={20}
        />
      )}
    </div>
  );
}
