import { useState, useMemo, useCallback } from 'react';

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  TrendingUp, TrendingDown, Minus, AlertTriangle, RefreshCw,
  BarChart3, CheckCircle2, Calculator, Target, LineChart
} from 'lucide-react';
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip as ChartTooltip,
  Legend as ChartLegend,
  Filler,
} from 'chart.js';
import { Line } from 'react-chartjs-2';

import StatCard, { StatsGrid } from '../../components/common/StatCard';
import { useTranslation } from '../../hooks/useTranslation';
import api from '../../utils/api';
import './ForecastAccuracy.css';

ChartJS.register(
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  ChartTooltip,
  ChartLegend,
  Filler,
);

interface ItemAccuracy {
  itemId: number;
  itemName: string;
  itemCode: string;
  mape: number | null;
  mae: number | null;
  smape: number | null;
  sampleSize: number;
  modelType: string;
  trend: 'growing' | 'stable' | 'declining' | null;
}

interface AccuracyDataPoint {
  forecastDate: string;
  period: string;
  predicted: number;
  actual: number | null;
  mape: number | null;
  mae: number | null;
}

type SortField = 'mape' | 'mae' | 'smape' | 'itemName' | 'sampleSize' | 'trend';
type SortDir = 'asc' | 'desc';

// ----- Helpers -----

function getMapeClass(mape: number | null): string {
  if (mape === null) return '';
  if (mape < 15) return 'mape-good';
  if (mape < 30) return 'mape-fair';
  return 'mape-poor';
}

function formatModelType(model: string): string {
  return model.replace(/_/g, ' ');
}

function TrendBadgeSm({ trend }: { trend: string | null }) {
  if (trend === 'growing') {
    return <span className="trend-badge-sm growing"><TrendingUp size={12} /> Growing</span>;
  }
  if (trend === 'declining') {
    return <span className="trend-badge-sm declining"><TrendingDown size={12} /> Declining</span>;
  }
  return <span className="trend-badge-sm stable"><Minus size={12} /> Stable</span>;
}

function SkeletonCard() {
  return (
    <div className="stat-card skeleton-pulse">
      <div className="skeleton-icon" />
      <div className="skeleton-text">
        <div className="skeleton-line short" />
        <div className="skeleton-line long" />
      </div>
    </div>
  );
}

// ----- Main Component -----

export default function ForecastAccuracy() {
  const { t } = useTranslation();
  const queryClient = useQueryClient();
  const [selectedItemId, setSelectedItemId] = useState<number | null>(null);
  const [sortField, setSortField] = useState<SortField>('mape');
  const [sortDir, setSortDir] = useState<SortDir>('asc');
  const [successMsg, setSuccessMsg] = useState<string | null>(null);
  const [searchTerm, setSearchTerm] = useState('');

  // Fetch accuracy summary for all items
  const {
    data: accuracyItems = [],
    isLoading,
    error,
    refetch,
    isFetching,
  } = useQuery<ItemAccuracy[]>({
    queryKey: ['forecasts', 'accuracy'],
    queryFn: async () => {
      const response = await api.get('/forecasts/accuracy');
      return response.data.data || [];
    },
  });

  // Fetch time series for selected item
  const { data: timeSeries = [] } = useQuery<AccuracyDataPoint[]>({
    queryKey: ['forecasts', 'accuracy', 'timeseries', selectedItemId],
    queryFn: async () => {
      if (!selectedItemId) return [];
      const response = await api.get(`/forecasts/accuracy/${selectedItemId}`);
      return response.data.data || [];
    },
    enabled: !!selectedItemId,
  });

  // Compute accuracy mutation
  const computeMutation = useMutation({
    mutationFn: async () => {
      const response = await api.post('/forecasts/compute-accuracy');
      return response.data;
    },
    onSuccess: (data) => {
      setSuccessMsg(data.message || 'Accuracy computed');
      queryClient.invalidateQueries({ queryKey: ['forecasts', 'accuracy'] });
      setTimeout(() => setSuccessMsg(null), 5000);
    },
  });

  // ---- Summary ----
  const summary = useMemo(() => {
    const total = accuracyItems.length;
    const withData = accuracyItems.filter(i => i.mape !== null).length;
    const avgMape = withData > 0
      ? accuracyItems
          .filter(i => i.mape !== null)
          .reduce((s, i) => s + (i.mape || 0), 0) / withData
      : null;

    // Best model by count
    const modelCounts: Record<string, number> = {};
    for (const item of accuracyItems) {
      const m = item.modelType || 'unknown';
      modelCounts[m] = (modelCounts[m] || 0) + 1;
    }
    const bestModel = Object.entries(modelCounts).sort((a, b) => b[1] - a[1])[0];

    return { total, withData, avgMape, bestModelName: bestModel?.[0] || null };
  }, [accuracyItems]);

  // ---- Sorted & Filtered Items ----
  const sortedItems = useMemo(() => {
    const filtered = searchTerm
      ? accuracyItems.filter(i =>
          i.itemName.toLowerCase().includes(searchTerm.toLowerCase()) ||
          i.itemCode.toLowerCase().includes(searchTerm.toLowerCase())
        )
      : [...accuracyItems];

    filtered.sort((a, b) => {
      let cmp = 0;
      const aVal = a[sortField];
      const bVal = b[sortField];

      if (aVal === null && bVal === null) cmp = 0;
      else if (aVal === null) cmp = 1;
      else if (bVal === null) cmp = -1;
      else if (typeof aVal === 'string' && typeof bVal === 'string') cmp = aVal.localeCompare(bVal);
      else cmp = (aVal as number) - (bVal as number);

      return sortDir === 'asc' ? cmp : -cmp;
    });

    return filtered;
  }, [accuracyItems, searchTerm, sortField, sortDir]);

  // ---- Time Series Chart Data ----
  const chartData = useMemo(() => {
    if (timeSeries.length === 0) return null;

    const labels = timeSeries.map(d => `${d.forecastDate} (${d.period.replace('next_', '')})`);

    return {
      labels,
      datasets: [
        {
          label: t('forecasts.mapeLabel'),
          data: timeSeries.map(d => d.mape),
          borderColor: '#3b82f6',
          backgroundColor: 'rgba(59, 130, 246, 0.1)',
          borderWidth: 2,
          pointRadius: 4,
          pointBackgroundColor: '#3b82f6',
          tension: 0.3,
          fill: true,
        },
        {
          label: t('forecasts.maeLabel'),
          data: timeSeries.map(d => d.mae),
          borderColor: '#8b5cf6',
          borderWidth: 2,
          borderDash: [4, 4],
          pointRadius: 3,
          pointBackgroundColor: '#8b5cf6',
          tension: 0.3,
          yAxisID: 'y1',
        },
      ],
    };
  }, [timeSeries, t]);

  const chartOptions = useMemo(() => ({
    responsive: true,
    maintainAspectRatio: false,
    interaction: {
      mode: 'index' as const,
      intersect: false,
    },
    plugins: {
      legend: { position: 'bottom' as const },
      tooltip: {
        callbacks: {
          label: (ctx: any) => {
            if (ctx.dataset.label === 'MAPE') return `MAPE: ${ctx.parsed.y?.toFixed(1)}%`;
            return `MAE: ${ctx.parsed.y?.toFixed(1)}`;
          },
        },
      },
    },
    scales: {
      x: { ticks: { font: { size: 11 } } },
      y: {
        beginAtZero: true,
        title: { display: true, text: 'MAPE (%)', font: { size: 12 } },
        ticks: { font: { size: 11 } },
      },
      y1: {
        beginAtZero: true,
        position: 'right' as const,
        title: { display: true, text: 'MAE', font: { size: 12 } },
        grid: { display: false },
        ticks: { font: { size: 11 } },
      },
    },
  }), []);

  const selectedItemName = useMemo(() => {
    if (!selectedItemId) return null;
    const item = accuracyItems.find(i => i.itemId === selectedItemId);
    return item ? `${item.itemName} (${item.itemCode})` : null;
  }, [selectedItemId, accuracyItems]);

  // ---- Handle sort toggle ----
  const handleSort = useCallback((field: SortField) => {
    setSortField(prev => {
      if (prev === field) {
        setSortDir(d => d === 'asc' ? 'desc' : 'asc');
        return prev;
      }
      setSortDir('asc');
      return field;
    });
  }, []);

  const sortIndicator = (field: SortField) => {
    if (sortField !== field) return '';
    return sortDir === 'asc' ? ' ▲' : ' ▼';
  };

  // ---- Render ----
  if (error) {
    return (
      <div className="forecast-accuracy-page">
        <div className="accuracy-header">
          <h1>{t('forecasts.accuracyTitle')}</h1>
        </div>
        <div className="error-state">
          <AlertTriangle size={32} />
          <p>{t('forecasts.loadError')}</p>
          <button className="btn-compute" onClick={() => refetch()}>
            <RefreshCw size={16} /> {t('forecasts.retry')}
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="forecast-accuracy-page">
      {/* Header */}
      <div className="accuracy-header">
        <div>
          <h1>{t('forecasts.accuracyTitle')}</h1>
          <p className="accuracy-subtitle">{t('forecasts.accuracySubtitle')}</p>
        </div>
        <div className="accuracy-actions">
          <button
            className="btn-compute"
            onClick={() => computeMutation.mutate()}
            disabled={computeMutation.isPending}
          >
            <Calculator size={16} className={computeMutation.isPending ? 'spinning' : ''} />
            {computeMutation.isPending ? t('forecasts.computing') : t('forecasts.computeAccuracy')}
          </button>
        </div>
      </div>

      {/* Success message */}
      {successMsg && (
        <div className="compute-success">
          <CheckCircle2 size={18} />
          {successMsg}
        </div>
      )}

      {/* Summary Cards */}
      {isLoading ? (
        <StatsGrid className="compact">
          <SkeletonCard />
          <SkeletonCard />
          <SkeletonCard />
          <SkeletonCard />
        </StatsGrid>
      ) : (
        <StatsGrid className="compact">
          <StatCard
            icon={Target}
            label={t('forecasts.avgMape')}
            value={summary.avgMape !== null ? `${summary.avgMape.toFixed(1)}%` : '—'}
          />
          <StatCard
            icon={BarChart3}
            label={t('forecasts.itemsWithAccuracy')}
            value={`${summary.withData} / ${summary.total}`}
            subtitle={`${summary.total - summary.withData} pending`}
          />
          <StatCard
            icon={TrendingUp}
            label={t('forecasts.bestModel')}
            value={summary.bestModelName ? formatModelType(summary.bestModelName) : '—'}
          />
          <StatCard
            icon={CheckCircle2}
            label={t('forecasts.avgMae')}
            value={
              accuracyItems.filter(i => i.mae !== null).length > 0
                ? (accuracyItems.filter(i => i.mae !== null).reduce((s, i) => s + (i.mae || 0), 0) / accuracyItems.filter(i => i.mae !== null).length).toFixed(1)
                : '—'
            }
          />
        </StatsGrid>
      )}

      {/* Accuracy Table */}
      <div className="accuracy-table-section">
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16, flexWrap: 'wrap', gap: 8 }}>
          <h2 style={{ margin: 0 }}>{t('forecasts.forecasts')}</h2>
          <input
            type="text"
            placeholder="Search items..."
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            style={{
              padding: '6px 12px',
              border: '1px solid var(--border-color, #e5e7eb)',
              borderRadius: 6,
              fontSize: 13,
              width: 220,
              background: 'var(--card-bg, #fff)',
              color: 'var(--text-primary, #111)',
            }}
          />
        </div>

        {isLoading ? (
          <div className="empty-state">
            <RefreshCw size={24} className="spinning" />
          </div>
        ) : sortedItems.length === 0 ? (
          <div className="empty-state">
            <LineChart size={40} />
            <p>{t('forecasts.noAccuracyData')}</p>
          </div>
        ) : (
          <div style={{ overflowX: 'auto' }}>
            <table className="accuracy-table">
              <thead>
                <tr>
                  <th onClick={() => handleSort('itemName')}>
                    {t('common.item')}{sortIndicator('itemName')}
                  </th>
                  <th>{t('inventory.itemCode')}</th>
                  <th onClick={() => handleSort('mape')}>
                    {t('forecasts.mapeLabel')}{sortIndicator('mape')}
                  </th>
                  <th onClick={() => handleSort('mae')}>
                    {t('forecasts.maeLabel')}{sortIndicator('mae')}
                  </th>
                  <th onClick={() => handleSort('smape')}>
                    {t('forecasts.smapeLabel')}{sortIndicator('smape')}
                  </th>
                  <th onClick={() => handleSort('sampleSize')}>
                    {t('forecasts.samples')}{sortIndicator('sampleSize')}
                  </th>
                  <th>{t('forecasts.model')}</th>
                  <th onClick={() => handleSort('trend')}>
                    {t('forecasts.trendLabel')}{sortIndicator('trend')}
                  </th>
                </tr>
              </thead>
              <tbody>
                {sortedItems.map(item => (
                  <tr
                    key={item.itemId}
                    className={selectedItemId === item.itemId ? 'selected' : ''}
                    onClick={() => setSelectedItemId(item.itemId)}
                  >
                    <td style={{ fontWeight: 500 }}>{item.itemName}</td>
                    <td className="item-code">{item.itemCode}</td>
                    <td className={`mape-cell ${getMapeClass(item.mape)}`}>
                      {item.mape !== null ? `${item.mape.toFixed(1)}%` : '—'}
                    </td>
                    <td>{item.mae !== null ? item.mae.toFixed(1) : '—'}</td>
                    <td>{item.smape !== null ? `${item.smape.toFixed(1)}%` : '—'}</td>
                    <td>{item.sampleSize}</td>
                    <td>
                      <span className="model-badge">{formatModelType(item.modelType)}</span>
                    </td>
                    <td><TrendBadgeSm trend={item.trend} /></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Accuracy Trend Chart */}
      <div className="accuracy-chart-section">
        <h2>
          {selectedItemName
            ? `${t('forecasts.accuracyTrend')}: ${selectedItemName}`
            : t('forecasts.accuracyTrend')}
        </h2>
        <p className="chart-subtitle">
          {selectedItemId
            ? t('forecasts.accuracyTrendDesc')
            : t('forecasts.selectItemForChart')}
        </p>

        {selectedItemId && chartData ? (
          <div className="chart-container-accuracy" style={{ height: 300 }}>
            <Line data={chartData} options={chartOptions} />
          </div>
        ) : selectedItemId ? (
          <div className="chart-empty-state">
            <RefreshCw size={24} className="spinning" />
          </div>
        ) : (
          <div className="chart-empty-state">
            <LineChart size={40} />
            <p>{t('forecasts.selectItemForChart')}</p>
          </div>
        )}
      </div>
    </div>
  );
}
