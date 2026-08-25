import { useQuery } from '@tanstack/react-query';
import { AlertTriangle, Package } from 'lucide-react';
import api from '../../../utils/api';
import type { DashboardBlockComponentProps } from './BlockComponentProps';

interface LowStockItem {
  id: number;
  item_code: string;
  item_name: string;
  current_stock: number;
  reorder_level: number;
  category: string;
}

interface SummaryData {
  lowStockItems: LowStockItem[];
}

export default function LowStockAlertsBlock({ blockId, apiEndpoint, config }: DashboardBlockComponentProps) {
  const limit = (config.limit as number) || 10;

  const { data, isLoading, error, refetch } = useQuery<SummaryData>({
    queryKey: ['dashboard-block', blockId, 'low_stock'],
    queryFn: async () => {
      const res = await api.get(apiEndpoint || '/dashboard/summary');
      return res.data.data as SummaryData;
    },
    refetchInterval: ((config.refreshInterval as number) || 0) * 1000,
    staleTime: 30_000,
  });

  const items = (data?.lowStockItems || []).slice(0, limit);

  if (isLoading) {
    return (
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
        {[1, 2, 3].map((i) => (
          <div key={i} className="dashboard-block-shimmer" style={{ height: 48, borderRadius: 6 }} />
        ))}
      </div>
    );
  }

  if (error || !data) {
    return (
      <div className="dashboard-block-error">
        <p>Failed to load low stock alerts</p>
        <button onClick={() => refetch()} className="dashboard-block-retry-btn">Retry</button>
      </div>
    );
  }

  return (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
      <h4 style={{ margin: '0 0 8px 0', fontSize: '0.95rem', color: 'var(--neutral-700)', display: 'flex', alignItems: 'center', gap: 6 }}>
        <AlertTriangle size={16} color="var(--warning)" />
        Low Stock Alerts
      </h4>
      {items.length === 0 ? (
        <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--neutral-500)', fontSize: '0.85rem' }}>
          <Package size={32} style={{ marginRight: 8, opacity: 0.4 }} />
          All items are well stocked!
        </div>
      ) : (
        <div style={{ flex: 1, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 4 }}>
          {items.map((item) => (
            <div
              key={item.id}
              style={{
                display: 'flex', justifyContent: 'space-between', alignItems: 'center',
                padding: '8px 10px', background: 'var(--neutral-50)', borderRadius: 6,
                borderLeft: '4px solid var(--warning)', fontSize: '0.85rem',
              }}
            >
              <div>
                <div style={{ fontWeight: 600, color: 'var(--neutral-800)' }}>{item.item_name}</div>
                <div style={{ fontSize: '0.8rem', color: 'var(--neutral-500)' }}>{item.item_code}</div>
              </div>
              <div style={{ textAlign: 'right' }}>
                <div style={{ fontWeight: 600, color: 'var(--warning)' }}>{item.current_stock}</div>
                <div style={{ fontSize: '0.75rem', color: 'var(--neutral-500)' }}>Reorder: {item.reorder_level}</div>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
