import { useQuery } from '@tanstack/react-query';
import { DollarSign, TrendingUp } from 'lucide-react';
import api from '../../../utils/api';
import { useSettings } from '../../../context/SettingsContext';
import type { DashboardBlockComponentProps } from './BlockComponentProps';

interface SalesSummaryData {
  period_total: number;
  count: number;
}

export default function SalesSummaryBlock({ blockId, apiEndpoint, config }: DashboardBlockComponentProps) {
  const { formatCurrency } = useSettings();
  const period = (config.period as string) || 'today';

  const { data, isLoading, error, refetch } = useQuery<SalesSummaryData>({
    queryKey: ['dashboard-block', blockId, 'sales_summary', period],
    queryFn: async () => {
      const res = await api.get(`${apiEndpoint || '/dashboard/sales-summary'}?period=${period}`);
      return res.data.data as SalesSummaryData;
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
        <p>Failed to load sales</p>
        <button onClick={() => refetch()} className="dashboard-block-retry-btn">Retry</button>
      </div>
    );
  }

  const periodLabel = period === 'today' ? 'Today' : period === 'week' ? 'This Week' : 'This Month';

  return (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column', justifyContent: 'center', alignItems: 'center', gap: 8, padding: '8px 0' }}>
      <DollarSign size={28} style={{ color: '#22c55e' }} />
      <div style={{ fontSize: '0.75rem', color: 'var(--neutral-500)', textTransform: 'uppercase', letterSpacing: 0.5 }}>
        Sales — {periodLabel}
      </div>
      <div style={{ fontSize: '1.5rem', fontWeight: 700, color: 'var(--neutral-900)' }}>
        {formatCurrency(data.period_total)}
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 4, fontSize: '0.8rem', color: 'var(--neutral-500)' }}>
        <TrendingUp size={14} color="#22c55e" />
        {data.count} transactions
      </div>
    </div>
  );
}
