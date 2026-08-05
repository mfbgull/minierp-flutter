import { useQuery } from '@tanstack/react-query';
import { Gauge } from 'lucide-react';
import api from '../../../utils/api';
import { useSettings } from '../../../context/SettingsContext';
import type { DashboardBlockComponentProps } from './BlockComponentProps';

interface KPIResult {
  metric: string;
  value: number;
  unit: string;
  label: string;
}

function getGaugeColor(pct: number): string {
  if (pct >= 80) return '#22c55e';
  if (pct >= 50) return '#eab308';
  if (pct >= 30) return '#f97316';
  return '#ef4444';
}

function formatKPIValue(value: number, unit: string, formatCurrency: (v: number) => string): string {
  if (unit === 'currency') return formatCurrency(value);
  if (unit === '%') return `${value}%`;
  if (unit === 'days') return `${value}d`;
  if (unit === 'ratio') return value.toFixed(2);
  return String(value);
}

export default function KPIGaugeBlock({ blockId, apiEndpoint, config }: DashboardBlockComponentProps) {
  const { formatCurrency } = useSettings();
  const metric = (config.metric as string) || 'stock_health';

  const { data, isLoading, error, refetch } = useQuery<KPIResult>({
    queryKey: ['dashboard-block', blockId, 'kpi_gauge', metric],
    queryFn: async () => {
      const res = await api.get(`${apiEndpoint || '/dashboard/kpi'}?metric=${metric}`);
      return res.data.data as KPIResult;
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
        <p>Failed to load KPI</p>
        <button onClick={() => refetch()} className="dashboard-block-retry-btn">Retry</button>
      </div>
    );
  }

  const displayValue = formatKPIValue(data.value, data.unit, formatCurrency);

  // Compute percentage for gauge (0-100 range approximation for color)
  const pct = data.unit === '%' ? data.value : Math.min((data.value / 100000) * 100, 100);
  const color = getGaugeColor(pct);

  // Simple SVG arc gauge
  const radius = 50;
  const circumference = 2 * Math.PI * radius;
  const offset = circumference - (Math.min(pct, 100) / 100) * circumference;

  return (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 4, padding: '4px 0' }}>
      <Gauge size={20} style={{ color }} />
      <div style={{ fontSize: '0.7rem', fontWeight: 600, color: 'var(--neutral-500)', textTransform: 'uppercase', letterSpacing: 0.5, textAlign: 'center' }}>
        {data.label}
      </div>
      <svg width="80" height="50" viewBox="0 0 120 70" style={{ margin: '2px 0' }}>
        <path
          d="M 10 60 A 50 50 0 1 1 110 60"
          fill="none"
          stroke="var(--neutral-100)"
          strokeWidth="8"
          strokeLinecap="round"
        />
        <path
          d="M 10 60 A 50 50 0 1 1 110 60"
          fill="none"
          stroke={color}
          strokeWidth="8"
          strokeLinecap="round"
          strokeDasharray={circumference}
          strokeDashoffset={offset}
          style={{ transition: 'stroke-dashoffset 0.8s ease' }}
        />
      </svg>
      <div style={{ fontSize: '1.2rem', fontWeight: 700, color: 'var(--neutral-900)' }}>
        {displayValue}
      </div>
      <div style={{ fontSize: '0.7rem', color: 'var(--neutral-500)' }}>
        {data.unit === 'currency' ? '' : data.unit}
      </div>
    </div>
  );
}
