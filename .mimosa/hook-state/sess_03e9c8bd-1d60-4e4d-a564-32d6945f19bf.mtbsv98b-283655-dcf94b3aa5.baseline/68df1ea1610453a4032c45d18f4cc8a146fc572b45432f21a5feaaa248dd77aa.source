import { useQuery } from '@tanstack/react-query';
import { Package, DollarSign, ShoppingCart, Factory } from 'lucide-react';
import api from '../../../utils/api';
import StatCard, { StatsGrid } from '../../common/StatCard';
import { useSettings } from '../../../context/SettingsContext';
import type { DashboardBlockComponentProps } from './BlockComponentProps';

interface SummaryData {
  totalItems: number;
  totalStockValue: number;
  totalSalesRevenue: number;
  totalPurchases: number;
  warehouseStockCount: number;
  recentProductions: number;
}

export default function StatCardsBlock({ blockId, apiEndpoint, config }: DashboardBlockComponentProps) {
  const { formatCurrency } = useSettings();

  const { data, isLoading, error, refetch } = useQuery<SummaryData>({
    queryKey: ['dashboard-block', blockId, 'stat_cards'],
    queryFn: async () => {
      const res = await api.get(apiEndpoint || '/dashboard/summary');
      return res.data.data as SummaryData;
    },
    refetchInterval: ((config.refreshInterval as number) || 0) * 1000,
    staleTime: 30_000,
  });

  if (isLoading) {
    return (
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 12, opacity: 0.6 }}>
        {[1, 2, 3, 4].map((i) => (
          <div key={i} className="dashboard-block-shimmer" style={{ height: 80, borderRadius: 8 }} />
        ))}
      </div>
    );
  }

  if (error || !data) {
    return (
      <div className="dashboard-block-error">
        <p>Failed to load stats</p>
        <button onClick={() => refetch()} className="dashboard-block-retry-btn">Retry</button>
      </div>
    );
  }

  return (
    <StatsGrid className="compact">
      <StatCard icon={Package} label="Total Items" value={data.totalItems} subtitle={`${data.warehouseStockCount} warehouse stocks`} />
      <StatCard icon={DollarSign} label="Stock Value" value={formatCurrency(data.totalStockValue)} subtitle="Current inventory worth" />
      <StatCard icon={ShoppingCart} label="Sales Revenue" value={formatCurrency(data.totalSalesRevenue)} subtitle="Total sales" />
      <StatCard icon={Factory} label="Production" value={data.recentProductions} subtitle="Runs in last 30 days" />
    </StatsGrid>
  );
}
