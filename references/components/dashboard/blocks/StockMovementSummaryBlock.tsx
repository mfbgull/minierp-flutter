import { useQuery } from '@tanstack/react-query';
import { ArrowUpDown, ArrowDown, ArrowUp, Activity } from 'lucide-react';
import api from '../../../utils/api';
import type { DashboardBlockComponentProps } from './BlockComponentProps';

interface StockMovementData {
  inbound_qty: number;
  outbound_qty: number;
  net: number;
}

export default function StockMovementSummaryBlock({ blockId, apiEndpoint, config }: DashboardBlockComponentProps) {
  const days = (config.days as number) || 7;

  const { data, isLoading, error, refetch } = useQuery<StockMovementData>({
    queryKey: ['dashboard-block', blockId, 'stock_movement', days],
    queryFn: async () => {
      const res = await api.get(`${apiEndpoint || '/dashboard/stock-movement-summary'}?days=${days}`);
      return res.data.data as StockMovementData;
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
        <p>Failed to load stock movements</p>
        <button onClick={() => refetch()} className="dashboard-block-retry-btn">Retry</button>
      </div>
    );
  }

  const items = [
    { icon: ArrowDown, label: 'Inbound', value: data.inbound_qty, color: '#22c55e' },
    { icon: ArrowUp, label: 'Outbound', value: data.outbound_qty, color: '#ef4444' },
    { icon: Activity, label: 'Net', value: data.net, color: data.net >= 0 ? '#22c55e' : '#ef4444' },
  ];

  return (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column', gap: 8 }}>
      <h4 style={{ margin: 0, fontSize: '0.95rem', color: 'var(--neutral-700)', display: 'flex', alignItems: 'center', gap: 6 }}>
        <ArrowUpDown size={16} />
        Stock Movements ({days}d)
      </h4>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
        {items.map((item) => (
          <div key={item.label} style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '6px 8px', background: 'var(--neutral-50)', borderRadius: 6 }}>
            <div style={{ width: 32, height: 32, borderRadius: 8, background: `${item.color}15`, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <item.icon size={16} style={{ color: item.color }} />
            </div>
            <span style={{ flex: 1, fontSize: '0.85rem', color: 'var(--neutral-600)' }}>{item.label}</span>
            <span style={{ fontWeight: 700, fontSize: '1.1rem', color: item.color }}>{item.value}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
