import { useQuery } from '@tanstack/react-query';
import { Factory, CheckCircle, XCircle, Clock } from 'lucide-react';
import api from '../../../utils/api';
import type { DashboardBlockComponentProps } from './BlockComponentProps';

interface ProductionStatusData {
  total: number;
  active: number;
  completed: number;
  cancelled: number;
}

export default function ProductionStatusBlock({ blockId, apiEndpoint, config }: DashboardBlockComponentProps) {
  const { data, isLoading, error, refetch } = useQuery<ProductionStatusData>({
    queryKey: ['dashboard-block', blockId, 'production_status'],
    queryFn: async () => {
      const res = await api.get(apiEndpoint || '/dashboard/production-status');
      return res.data.data as ProductionStatusData;
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
        <p>Failed to load production status</p>
        <button onClick={() => refetch()} className="dashboard-block-retry-btn">Retry</button>
      </div>
    );
  }

  const stats = [
    { icon: Clock, label: 'Active', value: data.active, color: '#3b82f6' },
    { icon: CheckCircle, label: 'Completed', value: data.completed, color: '#22c55e' },
    { icon: XCircle, label: 'Cancelled', value: data.cancelled, color: '#ef4444' },
  ];

  return (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column', gap: 8 }}>
      <h4 style={{ margin: 0, fontSize: '0.95rem', color: 'var(--neutral-700)', display: 'flex', alignItems: 'center', gap: 6 }}>
        <Factory size={16} />
        Production Status
      </h4>
      <div style={{ fontSize: '0.9rem', color: 'var(--neutral-500)', marginBottom: 4 }}>
        Total: <strong style={{ color: 'var(--neutral-800)' }}>{data.total}</strong> production runs
      </div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
        {stats.map((s) => (
          <div key={s.label} style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <s.icon size={16} style={{ color: s.color, flexShrink: 0 }} />
            <span style={{ flex: 1, fontSize: '0.85rem', color: 'var(--neutral-600)' }}>{s.label}</span>
            <span style={{ fontWeight: 700, fontSize: '1rem', color: 'var(--neutral-800)' }}>{s.value}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
