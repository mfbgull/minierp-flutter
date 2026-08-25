import { useMemo } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Doughnut } from 'react-chartjs-2';
import { Chart as ChartJS, ArcElement, Tooltip, Legend } from 'chart.js';
import api from '../../../utils/api';
import type { DashboardBlockComponentProps } from './BlockComponentProps';

ChartJS.register(ArcElement, Tooltip, Legend);

interface CategoryStock {
  category: string;
  total_stock: number;
}

interface SummaryData {
  stockByCategory: CategoryStock[];
}

const COLORS = [
  'rgba(54, 162, 235, 0.6)', 'rgba(255, 99, 132, 0.6)', 'rgba(255, 206, 86, 0.6)',
  'rgba(75, 192, 192, 0.6)', 'rgba(153, 102, 255, 0.6)', 'rgba(255, 159, 64, 0.6)',
];
const BORDERS = [
  'rgba(54, 162, 235, 1)', 'rgba(255, 99, 132, 1)', 'rgba(255, 206, 86, 1)',
  'rgba(75, 192, 192, 1)', 'rgba(153, 102, 255, 1)', 'rgba(255, 159, 64, 1)',
];

export default function StockByCategoryBlock({ blockId, apiEndpoint, config }: DashboardBlockComponentProps) {
  const { data, isLoading, error, refetch } = useQuery<SummaryData>({
    queryKey: ['dashboard-block', blockId, 'stock_by_category'],
    queryFn: async () => {
      const res = await api.get(apiEndpoint || '/dashboard/summary');
      return res.data.data as SummaryData;
    },
    refetchInterval: ((config.refreshInterval as number) || 0) * 1000,
    staleTime: 30_000,
  });

  const chartData = useMemo(
    () => ({
      labels: (data?.stockByCategory || []).map((c) => c.category),
      datasets: [
        {
          data: (data?.stockByCategory || []).map((c) => c.total_stock),
          backgroundColor: COLORS.slice(0, (data?.stockByCategory || []).length),
          borderColor: BORDERS.slice(0, (data?.stockByCategory || []).length),
          borderWidth: 1,
        },
      ],
    }),
    [data],
  );

  if (isLoading) {
    return <div className="dashboard-block-shimmer" style={{ height: '100%', borderRadius: 8 }} />;
  }

  if (error || !data) {
    return (
      <div className="dashboard-block-error">
        <p>Failed to load chart data</p>
        <button onClick={() => refetch()} className="dashboard-block-retry-btn">Retry</button>
      </div>
    );
  }

  return (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column' }}>
      <h4 style={{ margin: '0 0 8px 0', fontSize: '0.95rem', color: 'var(--neutral-700)' }}>Stock by Category</h4>
      <div style={{ flex: 1, minHeight: 0, position: 'relative' }}>
        <Doughnut
          data={chartData}
          options={{
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
              legend: { position: 'bottom', labels: { boxWidth: 12, padding: 12, font: { size: 11 } } },
            },
          }}
        />
      </div>
    </div>
  );
}
