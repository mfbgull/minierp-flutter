import { useState, useMemo, useRef, useEffect } from 'react';

import { useQuery } from '@tanstack/react-query';
import {
  TrendingUp, TrendingDown, Minus, AlertTriangle, RefreshCw
} from 'lucide-react';
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  BarElement,
  Title,
  Tooltip as ChartTooltip,
  Legend as ChartLegend,
} from 'chart.js';
import { Line, Bar } from 'react-chartjs-2';

import SearchableSelect from '../../components/common/SearchableSelect';
import { useTranslation } from '../../hooks/useTranslation';
import api from '../../utils/api';
import './ForecastTrends.css';

ChartJS.register(
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  BarElement,
  Title,
  ChartTooltip,
  ChartLegend,
);

interface TrendMonth {
  month: string;
  actual: number | null;
  predicted: number | null;
  movingAvg?: number | null;
}

interface BreakdownItem {
  itemName: string;
  totalSold: number;
  trend: 'growing' | 'stable' | 'declining';
}

interface TrendDataResponse {
  historicalTrends: TrendMonth[];
  itemBreakdown: BreakdownItem[];
}

interface InventoryItem {
  id: number;
  item_name: string;
  is_finished_good: number | boolean;
  [key: string]: unknown;
}

function SkeletonCard() {
  return (
    <div className="chart-card skeleton-pulse">
      <div className="skeleton-line medium" style={{ marginBottom: 16 }} />
      <div className="skeleton-chart" />
    </div>
  );
}

export default function ForecastTrends() {
  const { t } = useTranslation();
  const [selectedItem, setSelectedItem] = useState('');

  const { data: items = [] } = useQuery<InventoryItem[]>({
    queryKey: ['items-all'],
    queryFn: async () => {
      const response = await api.get('/inventory/items');
      return response.data.data || [];
    }
  });

  const finishedGoods = useMemo(() =>
    items.filter(i => i.is_finished_good === 1 || i.is_finished_good === true),
    [items]
  );

  const { data: trendData, isLoading, error, refetch } = useQuery<TrendDataResponse>({
    queryKey: ['forecasts', 'trends', selectedItem],
    queryFn: async () => {
      const params = selectedItem ? `?itemId=${selectedItem}` : '';
      const response = await api.get(`/forecasts/trends${params}`);
      return response.data.data;
    }
  });

  const historicalTrends: TrendMonth[] = trendData?.historicalTrends || [];
  const itemBreakdown: BreakdownItem[] = trendData?.itemBreakdown || [];

  const actualColor = '#3b82f6';
  const movingAvgColor = '#8b5cf6';
  const forecastColor = '#10b981';

  const lineChartData = {
    labels: historicalTrends.map(d => d.month),
    datasets: [
      {
        label: t('forecasts.actualSales'),
        data: historicalTrends.map(d => d.actual),
        borderColor: actualColor,
        backgroundColor: actualColor,
        borderWidth: 2,
        pointRadius: 4,
        pointBackgroundColor: actualColor,
        tension: 0,
        spanGaps: false,
      },
      {
        label: t('forecasts.trendLine'),
        data: historicalTrends.map(d => d.movingAvg),
        borderColor: movingAvgColor,
        borderWidth: 2,
        borderDash: [4, 4],
        pointRadius: 0,
        tension: 0,
        spanGaps: true,
      },
      {
        label: t('forecasts.forecast'),
        data: historicalTrends.map(d => d.predicted),
        borderColor: forecastColor,
        borderWidth: 2,
        borderDash: [8, 4],
        pointRadius: 6,
        pointBackgroundColor: forecastColor,
        pointBorderColor: forecastColor,
        tension: 0,
        spanGaps: true,
      },
    ],
  };

  const lineChartOptions = {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: { position: 'bottom' as const },
    },
    scales: {
      x: { ticks: { font: { size: 12 } } },
      y: { ticks: { font: { size: 12 } } },
    },
  };

  const topItems = itemBreakdown.slice(0, 10);
  const barChartData = {
    labels: topItems.map(d => d.itemName.length > 15 ? d.itemName.substring(0, 15) + '...' : d.itemName),
    datasets: [
      {
        label: t('forecasts.totalSold'),
        data: topItems.map(d => d.totalSold),
        backgroundColor: actualColor,
      },
    ],
  };

  const barChartOptions = {
    responsive: true,
    maintainAspectRatio: false,
    indexAxis: 'y' as const,
    plugins: {
      legend: { display: false },
    },
    scales: {
      x: { ticks: { font: { size: 12 } } },
      y: { ticks: { font: { size: 11 } } },
    },
  };

  if (error) {
    return (
      <div className="forecast-trends-page">
        <div className="page-header">
          <h1>{t('forecasts.forecastTrends')}</h1>
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
    <div className="forecast-trends-page">
      <div className="page-header">
        <h1>{t('forecasts.forecastTrends')}</h1>
        <div className="item-filter">
          <SearchableSelect
            name="itemId"
            value={selectedItem}
            onChange={(e) => setSelectedItem(String(e.target.value))}
            options={finishedGoods.map((i: InventoryItem) => ({ value: String(i.id), label: i.item_name }))}
            placeholder={t('forecasts.selectItem')}
          />
        </div>
      </div>

      {isLoading ? (
        <div className="charts-grid">
          <SkeletonCard />
          <SkeletonCard />
        </div>
      ) : historicalTrends.length === 0 ? (
        <div className="empty-state">
          <p>{t('forecasts.noTrendData')}</p>
        </div>
      ) : (
        <>
          <div className="charts-grid">
            <div className="chart-card">
              <h3>{t('forecasts.monthlyTrend')}</h3>
              <div className="chart-container">
                <Line data={lineChartData} options={lineChartOptions} />
              </div>
            </div>

            <div className="chart-card">
              <h3>{t('forecasts.topItemsByVolume')}</h3>
              <div className="chart-container">
                <Bar data={barChartData} options={barChartOptions} />
              </div>
            </div>
          </div>

          <div className="breakdown-table">
            <h3>{t('forecasts.itemBreakdown')}</h3>
            <table>
              <thead>
                <tr>
                  <th>{t('common.item')}</th>
                  <th>{t('forecasts.totalSold12mo')}</th>
                  <th>{t('forecasts.trendLabel')}</th>
                </tr>
              </thead>
              <tbody>
                {itemBreakdown.length === 0 ? (
                  <tr>
                    <td colSpan={3} className="empty-cell">{t('forecasts.noTrendData')}</td>
                  </tr>
                ) : (
                  itemBreakdown.map((item, idx) => (
                    <tr key={idx}>
                      <td>{item.itemName}</td>
                      <td>{item.totalSold.toLocaleString()}</td>
                      <td>
                        <span className={`trend-badge ${item.trend}`}>
                          {item.trend === 'growing' && <><TrendingUp size={14} /> {t('forecasts.growing')}</>}
                          {item.trend === 'declining' && <><TrendingDown size={14} /> {t('forecasts.declining')}</>}
                          {item.trend === 'stable' && <><Minus size={14} /> {t('forecasts.stable')}</>}
                        </span>
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </>
      )}
    </div>
  );
}
