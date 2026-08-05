import { useQuery } from '@tanstack/react-query';
import { Award } from 'lucide-react';
import api from '../../../utils/api';
import { useSettings } from '../../../context/SettingsContext';
import type { DashboardBlockComponentProps } from './BlockComponentProps';

interface TopCustomer {
  customer_name: string;
  total_revenue: number;
  invoice_count: number;
}

export default function TopCustomersBlock({ blockId, apiEndpoint, config }: DashboardBlockComponentProps) {
  const { formatCurrency } = useSettings();
  const limit = (config.limit as number) || 5;

  const { data, isLoading, error, refetch } = useQuery<TopCustomer[]>({
    queryKey: ['dashboard-block', blockId, 'top_customers'],
    queryFn: async () => {
      const res = await api.get(`${apiEndpoint || '/dashboard/top-customers'}?limit=${limit}`);
      return res.data.data as TopCustomer[];
    },
    refetchInterval: ((config.refreshInterval as number) || 0) * 1000,
    staleTime: 30_000,
  });

  if (isLoading) {
    return (
      <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
        {[1, 2, 3].map((i) => (
          <div key={i} className="dashboard-block-shimmer" style={{ height: 44, borderRadius: 6 }} />
        ))}
      </div>
    );
  }

  if (error || !data) {
    return (
      <div className="dashboard-block-error">
        <p>Failed to load top customers</p>
        <button onClick={() => refetch()} className="dashboard-block-retry-btn">Retry</button>
      </div>
    );
  }

  const maxRevenue = Math.max(...data.map((c) => c.total_revenue), 1);

  return (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
      <h4 style={{ margin: '0 0 8px 0', fontSize: '0.95rem', color: 'var(--neutral-700)', display: 'flex', alignItems: 'center', gap: 6 }}>
        <Award size={16} />
        Top Customers
      </h4>
      <div style={{ flex: 1, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 6 }}>
        {data.map((customer, idx) => (
          <div key={customer.customer_name} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '4px 0' }}>
            <span style={{
              width: 20, height: 20, borderRadius: '50%', background: idx === 0 ? 'var(--warning)' : 'var(--neutral-200)',
              color: idx === 0 ? 'white' : 'var(--neutral-600)', display: 'flex', alignItems: 'center',
              justifyContent: 'center', fontSize: '0.7rem', fontWeight: 700, flexShrink: 0,
            }}>
              {idx + 1}
            </span>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontSize: '0.85rem', fontWeight: 600, color: 'var(--neutral-800)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                {customer.customer_name}
              </div>
              <div style={{ height: 6, background: 'var(--neutral-100)', borderRadius: 3, marginTop: 2, overflow: 'hidden' }}>
                <div style={{
                  width: `${(customer.total_revenue / maxRevenue) * 100}%`, height: '100%',
                  background: 'linear-gradient(90deg, var(--primary), #6366f1)', borderRadius: 3,
                }} />
              </div>
            </div>
            <div style={{ textAlign: 'right', flexShrink: 0 }}>
              <div style={{ fontSize: '0.8rem', fontWeight: 600, color: 'var(--neutral-800)' }}>{formatCurrency(customer.total_revenue)}</div>
              <div style={{ fontSize: '0.7rem', color: 'var(--neutral-500)' }}>{customer.invoice_count} invoices</div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
