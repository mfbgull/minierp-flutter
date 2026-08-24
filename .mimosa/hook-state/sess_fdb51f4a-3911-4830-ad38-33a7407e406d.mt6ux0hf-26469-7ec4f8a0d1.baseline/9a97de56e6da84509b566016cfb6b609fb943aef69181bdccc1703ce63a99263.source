import { useMemo } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Line } from 'react-chartjs-2';
import { Chart as ChartJS, CategoryScale, LinearScale, PointElement, LineElement, Title, Tooltip, Legend } from 'chart.js';
import api from '../../../utils/api';
import type { DashboardBlockComponentProps } from './BlockComponentProps';

ChartJS.register(CategoryScale, LinearScale, PointElement, LineElement, Title, Tooltip, Legend);

interface DayTotal {
  date: string;
  total: number;
}

interface SummaryData {
  salesByDay: DayTotal[];
  purchasesByDay: DayTotal[];
}

const getLast7Days = (): string[] => {
  const days: string[] = [];
  for (let i = 6; i >= 0; i--) {
    const date = new Date();
    date.setDate(date.getDate() - i);
    days.push(date.toISOString().split('T')[0]);
  }
  return days;
};

export default function SalesPurchasesChartBlock({ blockId, apiEndpoint, config }: DashboardBlockComponentProps) {
  const { data, isLoading, error, refetch } = useQuery<SummaryData>({
    queryKey: ['dashboard-block', blockId, 'sales_vs_purchases'],
    queryFn: async () => {
      const res = await api.get(apiEndpoint || '/dashboard/summary');
      return res.data.data as SummaryData;
    },
    refetchInterval: ((config.refreshInterval as number) || 0) * 1000,
    staleTime: 30_000,
  });

  const chartData = useMemo(() => {
    const last7Days = getLast7Days();
    const salesMap = Object.fromEntries((data?.salesByDay || []).map((d) => [d.date, d.total]));
    const purchasesMap = Object.fromEntries((data?.purchasesByDay || []).map((d) => [d.date, d.total]));

    return {
      labels: last7Days.map((date) =>
        new Date(date).toLocaleDateString('en-US', { month: 'short', day: 'numeric' } as Intl.DateTimeFormatOptions)
      ),
      datasets: [
        {
          label: 'Sales',
          data: last7Days.map((d) => salesMap[d] || 0),
          borderColor: 'rgb(75, 192, 192)',
          backgroundColor: 'rgba(75, 192, 192, 0.2)',
          tension: 0.4,
        },
        {
          label: 'Purchases',
          data: last7Days.map((d) => purchasesMap[d] || 0),
          borderColor: 'rgb(255, 99, 132)',
          backgroundColor: 'rgba(255, 99, 132, 0.2)',
          tension: 0.4,
        },
      ],
    };
  }, [data]);

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
      <h4 style={{ margin: '0 0 8px 0', fontSize: '0.95rem', color: 'var(--neutral-700)' }}>Sales vs Purchases (7 days)</h4>
      <div style={{ flex: 1, minHeight: 0, position: 'relative' }}>
        <Line
          data={chartData}
          options={{
            responsive: true,
            maintainAspectRatio: false,
            plugins: { legend: { position: 'top', labels: { boxWidth: 12, padding: 12 } } },
            scales: { y: { beginAtZero: true, ticks: { maxTicksLimit: 5 } } },
          }}
        />
      </div>
    </div>
  );
}
