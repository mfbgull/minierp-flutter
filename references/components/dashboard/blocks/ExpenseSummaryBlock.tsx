import { useQuery } from '@tanstack/react-query';
import { CreditCard, TrendingDown } from 'lucide-react';
import api from '../../../utils/api';
import { useSettings } from '../../../context/SettingsContext';
import type { DashboardBlockComponentProps } from './BlockComponentProps';

interface ExpenseSummaryData {
  period_total: number;
  count: number;
}

export default function ExpenseSummaryBlock({ blockId, apiEndpoint, config }: DashboardBlockComponentProps) {
  const { formatCurrency } = useSettings();
  const period = (config.period as string) || 'month';

  const { data, isLoading, error, refetch } = useQuery<ExpenseSummaryData>({
    queryKey: ['dashboard-block', blockId, 'expense_summary', period],
    queryFn: async () => {
      const res = await api.get(`${apiEndpoint || '/dashboard/expense-summary'}?period=${period}`);
      return res.data.data as ExpenseSummaryData;
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
        <p>Failed to load expenses</p>
        <button onClick={() => refetch()} className="dashboard-block-retry-btn">Retry</button>
      </div>
    );
  }

  const periodLabel = period === 'week' ? 'This Week' : 'This Month';

  return (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column', justifyContent: 'center', alignItems: 'center', gap: 8, padding: '8px 0' }}>
      <CreditCard size={28} style={{ color: '#f97316' }} />
      <div style={{ fontSize: '0.75rem', color: 'var(--neutral-500)', textTransform: 'uppercase', letterSpacing: 0.5 }}>
        Expenses — {periodLabel}
      </div>
      <div style={{ fontSize: '1.5rem', fontWeight: 700, color: 'var(--neutral-900)' }}>
        {formatCurrency(data.period_total)}
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 4, fontSize: '0.8rem', color: 'var(--neutral-500)' }}>
        <TrendingDown size={14} color="#f97316" />
        {data.count} expenses
      </div>
    </div>
  );
}
