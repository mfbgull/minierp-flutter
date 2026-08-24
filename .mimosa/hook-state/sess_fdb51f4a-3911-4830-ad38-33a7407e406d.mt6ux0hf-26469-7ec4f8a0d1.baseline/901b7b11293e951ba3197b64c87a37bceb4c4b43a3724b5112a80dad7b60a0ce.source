import { useQuery } from '@tanstack/react-query';
import { BarChart3, TrendingUp, AlertTriangle, Package } from 'lucide-react';
import api from '../../../utils/api';
import type { DashboardBlockComponentProps } from './BlockComponentProps';

interface ForecastDashboard {
  summary: {
    totalItems: number;
    itemsNeedingRestock: number;
    avgConfidence: number;
    criticalAlerts: number;
  };
}

export default function ForecastSnapshotBlock({ blockId, apiEndpoint, config }: DashboardBlockComponentProps) {
  const { data, isLoading, error, refetch } = useQuery<ForecastDashboard>({
    queryKey: ['dashboard-block', blockId, 'forecast_snapshot'],
    queryFn: async () => {
      const res = await api.get(apiEndpoint || '/forecasts/dashboard');
      return res.data.data as ForecastDashboard;
    },
    refetchInterval: ((config.refreshInterval as number) || 0) * 1000,
    staleTime: 30_000,
  });

  if (isLoading) {
    return <div className="dashboard-block-shimmer" style={{ height: '100%', borderRadius: 8 }} />;
  }

  if (error || !data) {
    return (
      <div className="dashboard-block-error">
        <p>Failed to load forecast</p>
        <button onClick={() => refetch()} className="dashboard-block-retry-btn">Retry</button>
      </div>
    );
  }

  const s = data.summary;
  const metrics = [
    { icon: Package, label: 'Tracked Items', value: s.totalItems, color: 'var(--primary)' },
    { icon: AlertTriangle, label: 'Need Restock', value: s.itemsNeedingRestock, color: 'var(--warning)' },
    { icon: TrendingUp, label: 'Avg Confidence', value: `${Math.round(s.avgConfidence)}%`, color: '#22c55e' },
    { icon: BarChart3, label: 'Critical', value: s.criticalAlerts, color: 'var(--danger)' },
  ];

  return (
    <div style={{ height: '100%', display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 6, alignContent: 'center' }}>
      {metrics.map((m) => (
        <div
          key={m.label}
          style={{
            display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center',
            gap: 4, padding: '8px 4px', background: 'var(--neutral-50)', borderRadius: 8,
          }}
        >
          <m.icon size={18} style={{ color: m.color }} />
          <span style={{ fontSize: '1.2rem', fontWeight: 700, color: 'var(--neutral-900)' }}>{m.value}</span>
          <span style={{ fontSize: '0.7rem', color: 'var(--neutral-500)', textAlign: 'center', lineHeight: 1.2 }}>{m.label}</span>
        </div>
      ))}
    </div>
  );
}
