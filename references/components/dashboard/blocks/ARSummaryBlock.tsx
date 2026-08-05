import { useQuery } from '@tanstack/react-query';
import { Wallet } from 'lucide-react';
import api from '../../../utils/api';
import { useSettings } from '../../../context/SettingsContext';
import type { DashboardBlockComponentProps } from './BlockComponentProps';

interface ARSummary {
  total_ar: number;
  current_amount: number;
  amount_1_30: number;
  amount_31_60: number;
  amount_61_90: number;
  amount_over_90: number;
  customer_count: number;
}

export default function ARSummaryBlock({ blockId, apiEndpoint, config }: DashboardBlockComponentProps) {
  const { formatCurrency } = useSettings();

  const { data, isLoading, error, refetch } = useQuery<ARSummary>({
    queryKey: ['dashboard-block', blockId, 'ar_summary'],
    queryFn: async () => {
      const res = await api.get(apiEndpoint || '/dashboard/ar-summary');
      return res.data.data as ARSummary;
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
        <p>Failed to load AR data</p>
        <button onClick={() => refetch()} className="dashboard-block-retry-btn">Retry</button>
      </div>
    );
  }

  const buckets = [
    { label: 'Current', amount: data.current_amount, color: '#22c55e' },
    { label: '1-30 days', amount: data.amount_1_30, color: '#eab308' },
    { label: '31-60 days', amount: data.amount_31_60, color: '#f97316' },
    { label: '61-90 days', amount: data.amount_61_90, color: '#ef4444' },
    { label: 'Over 90 days', amount: data.amount_over_90, color: '#dc2626' },
  ];

  const maxAmount = Math.max(...buckets.map((b) => b.amount), 1);

  return (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
      <h4 style={{ margin: '0 0 4px 0', fontSize: '0.95rem', color: 'var(--neutral-700)', display: 'flex', alignItems: 'center', gap: 6 }}>
        <Wallet size={16} />
        AR Summary
      </h4>
      <div style={{ fontSize: '1.3rem', fontWeight: 700, color: 'var(--neutral-900)', marginBottom: 8 }}>
        {formatCurrency(data.total_ar)}
        <span style={{ fontSize: '0.75rem', fontWeight: 400, color: 'var(--neutral-500)', marginLeft: 8 }}>
          {data.customer_count} customers
        </span>
      </div>
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 4, overflowY: 'auto' }}>
        {buckets.map((bucket) => (
          <div key={bucket.label} style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: '0.8rem' }}>
            <span style={{ width: 80, color: 'var(--neutral-600)', flexShrink: 0 }}>{bucket.label}</span>
            <div style={{ flex: 1, height: 10, background: 'var(--neutral-100)', borderRadius: 5, overflow: 'hidden' }}>
              <div
                style={{
                  width: `${(bucket.amount / maxAmount) * 100}%`,
                  height: '100%',
                  background: bucket.color,
                  borderRadius: 5,
                  transition: 'width 0.3s ease',
                }}
              />
            </div>
            <span style={{ width: 100, textAlign: 'right', fontWeight: 600, color: 'var(--neutral-800)' }}>
              {formatCurrency(bucket.amount)}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}
