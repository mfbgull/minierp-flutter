import { Link } from 'react-router-dom';

import { useQuery } from '@tanstack/react-query';
import {
  TrendingUp, Package, AlertTriangle, CheckCircle,
  ArrowRight, RefreshCw
} from 'lucide-react';

import StatCard, { StatsGrid } from '../../components/common/StatCard';
import { useTranslation } from '../../hooks/useTranslation';
import api from '../../utils/api';
import './ForecastDashboard.css';

interface ForecastResult {
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

interface ForecastAlertData {
  itemId: number;
  itemName: string;
  currentStock: number;
  predictedDemand: number;
  alertLevel: 'critical' | 'warning' | 'monitor' | 'adequate';
  recommendation: string;
}

interface DashboardData {
  summary: {
    totalItems: number;
    itemsNeedingRestock: number;
    avgConfidence: number;
    criticalAlerts: number;
  };
  alerts: ForecastAlertData[];
  topGrowing: ForecastResult[];
  topDeclining: ForecastResult[];
}

function AlertCard({ alert }: { alert: ForecastAlertData }) {
  const levelColors: Record<string, string> = {
    critical: 'alert-critical',
    warning: 'alert-warning',
    monitor: 'alert-monitor',
    adequate: 'alert-adequate'
  };

  return (
    <div className={`forecast-alert-card ${levelColors[alert.alertLevel] || ''}`}>
      <div className="alert-info">
        <span className="alert-item-name">{alert.itemName}</span>
        <span className="alert-stock">
          Stock: {alert.currentStock} | Predicted: {alert.predictedDemand}
        </span>
      </div>
      <span className={`alert-badge ${alert.alertLevel}`}>
        {alert.alertLevel === 'critical' ? 'Critical' :
         alert.alertLevel === 'warning' ? 'Warning' : 'OK'}
      </span>
    </div>
  );
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

function AlertSkeleton() {
  return (
    <div className="forecast-alert-card skeleton-pulse">
      <div className="alert-info">
        <div className="skeleton-line medium" />
        <div className="skeleton-line short" style={{ marginTop: 4 }} />
      </div>
      <div className="skeleton-badge" />
    </div>
  );
}

export default function ForecastDashboard() {
  const { t } = useTranslation();
  const { data, isLoading, error, refetch, isFetching } = useQuery<DashboardData>({
    queryKey: ['forecasts', 'dashboard'],
    queryFn: async () => {
      const response = await api.get('/forecasts/dashboard');
      return response.data.data;
    }
  });

  if (error) {
    return (
      <div className="forecast-dashboard">
        <div className="forecast-header">
          <h1>{t('forecasts.dashboard')}</h1>
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

  if (isLoading) {
    return (
      <div className="forecast-dashboard">
        <div className="forecast-header">
          <h1>{t('forecasts.dashboard')}</h1>
        </div>
        <StatsGrid className="compact">
          <SkeletonCard />
          <SkeletonCard />
          <SkeletonCard />
          <SkeletonCard />
        </StatsGrid>
        <div className="forecast-section">
          <div className="section-header">
            <h2>{t('forecasts.alerts')}</h2>
          </div>
          <div className="forecast-alerts-list">
            {Array.from({ length: 4 }).map((_, i) => (
              <AlertSkeleton key={i} />
            ))}
          </div>
        </div>
      </div>
    );
  }

  const { summary, alerts, topGrowing, topDeclining } = data || {
    summary: { totalItems: 0, itemsNeedingRestock: 0, avgConfidence: 0, criticalAlerts: 0 },
    alerts: [],
    topGrowing: [],
    topDeclining: []
  };

  return (
    <div className="forecast-dashboard">
      <div className="forecast-header">
        <h1>{t('forecasts.dashboard')}</h1>
        <button
          className="btn-refresh"
          onClick={() => refetch()}
          disabled={isFetching}
        >
          <RefreshCw size={16} className={isFetching ? 'spinning' : ''} />
          {isFetching ? t('forecasts.refreshing') : t('forecasts.refresh')}
        </button>
      </div>

      <StatsGrid className="compact">
        <StatCard icon={Package} label={t('forecasts.trackedItems')} value={summary.totalItems} />
        <StatCard icon={AlertTriangle} label={t('forecasts.needRestock')} value={summary.itemsNeedingRestock} alert={summary.itemsNeedingRestock > 0} />
        <StatCard icon={TrendingUp} label={t('forecasts.avgConfidence')} value={`${summary.avgConfidence}%`} />
        <StatCard icon={CheckCircle} label={t('forecasts.criticalAlerts')} value={summary.criticalAlerts} alert={summary.criticalAlerts > 0} />
      </StatsGrid>

      <div className="forecast-section">
        <div className="section-header">
          <h2>{t('forecasts.alerts')}</h2>
          <Link to="/forecasts/demand" className="view-all">
            {t('forecasts.viewAll')} <ArrowRight size={16} />
          </Link>
        </div>

        {alerts.length === 0 ? (
          <div className="empty-state">{t('forecasts.noAlerts')}</div>
        ) : (
          <div className="forecast-alerts-list">
            {alerts.slice(0, 10).map(alert => (
              <AlertCard key={alert.itemId} alert={alert} />
            ))}
          </div>
        )}
      </div>

      <div className="forecast-section">
        <div className="section-header">
          <h2>{t('forecasts.topGrowing')}</h2>
          <Link to="/forecasts/trends" className="view-all">
            {t('forecasts.viewTrends')} <ArrowRight size={16} />
          </Link>
        </div>

        {topGrowing.length === 0 ? (
          <div className="empty-state">{t('forecasts.noTrendData')}</div>
        ) : (
          <div className="trend-list">
            {topGrowing.map(item => (
              <div key={item.itemId} className="trend-item growing">
                <span className="trend-name">{item.itemName}</span>
                <span className="trend-badge growing">{item.trendPercentage}%</span>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
