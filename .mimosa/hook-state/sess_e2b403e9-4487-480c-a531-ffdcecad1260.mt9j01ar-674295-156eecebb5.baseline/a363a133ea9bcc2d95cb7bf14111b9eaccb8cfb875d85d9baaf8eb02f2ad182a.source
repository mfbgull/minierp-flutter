import { useState } from 'react';
import { Bar } from 'react-chartjs-2';
import { useQuery } from '@tanstack/react-query';
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  BarElement,
  Title,
  Tooltip,
  Legend,
} from 'chart.js';
import {
  TrendingUp,
  TrendingDown,
  DollarSign,
  Calculator,
  Download,
  Filter,
  BarChart3
} from 'lucide-react';

import Button from '../../components/common/Button';
import DateRangePicker from '../../components/common/DateRangePicker';
import StatCard, { StatsGrid } from '../../components/common/StatCard';
import type { DateRangeFilter } from '../../types';
import { useSettings } from '../../context/SettingsContext';
import api from '../../utils/api';
import { exportToPDF, exportToExcel } from '../../utils/exportUtils';
import './FinancialReports.css';

ChartJS.register(CategoryScale, LinearScale, BarElement, Title, Tooltip, Legend);

interface PnLData {
  totalRevenue: number;
  totalCogs: number;
  grossProfit: number;
  totalExpenses: number;
  netProfit: number;
  grossProfitMargin: number;
  netProfitMargin: number;
}

export default function ProfitLossReport() {
  const [dateRange, setDateRange] = useState<DateRangeFilter>({
    fromDate: new Date(new Date().setMonth(new Date().getMonth() - 1)).toISOString().split('T')[0],
    toDate: new Date().toISOString().split('T')[0]
  });
  const [showFilters, setShowFilters] = useState(false);
  const { formatCurrency } = useSettings();

  const { data: reportData, isLoading, refetch } = useQuery<PnLData>({
    queryKey: ['profitLoss', dateRange],
    queryFn: async () => {
      const params = new URLSearchParams();
      params.append('fromDate', dateRange.fromDate); params.append('toDate', dateRange.toDate);
      const r = await api.get(`/reports/profit-loss?${params}`); return r.data.data;
    }
  });

  const handleFilterSubmit = (e: React.FormEvent) => { e.preventDefault(); refetch(); };

  const handleExport = (format = 'pdf') => {
    if (!reportData) return;
    const d = [
      { metric: 'Total Revenue', value: reportData.totalRevenue },
      { metric: 'Cost of Goods Sold (COGS)', value: reportData.totalCogs },
      { metric: 'Gross Profit', value: reportData.grossProfit },
      { metric: 'Total Expenses', value: reportData.totalExpenses },
      { metric: 'Net Profit', value: reportData.netProfit },
      { metric: 'Gross Profit Margin (%)', value: reportData.grossProfitMargin },
      { metric: 'Net Profit Margin (%)', value: reportData.netProfitMargin }
    ];
    const cols = [
      { headerName: 'Metric', field: 'metric' },
      { headerName: 'Value', field: 'value', valueFormatter: (p: { value: number; row?: { metric?: string } }) => {
        if (['Total Revenue', 'Cost of Goods Sold (COGS)', 'Gross Profit', 'Total Expenses', 'Net Profit'].includes(p.row?.metric || '')) return formatCurrency(p.value);
        if ((p.row?.metric || '').includes('Margin')) return `${p.value}%`;
        return String(p.value);
      }}
    ];
    if (format === 'pdf') exportToPDF(d, cols, 'Profit & Loss Report', `profit-loss-${new Date().toISOString().split('T')[0]}.pdf`);
    else exportToExcel(d, cols, 'Profit & Loss Report', `profit-loss-${new Date().toISOString().split('T')[0]}.csv`);
  };

  const chartData = {
    labels: ['Revenue', 'COGS', 'Gross Profit', 'Expenses', 'Net Profit'],
    datasets: [{
      label: 'Amount',
      data: [reportData?.totalRevenue || 0, -(reportData?.totalCogs || 0), reportData?.grossProfit || 0, -(reportData?.totalExpenses || 0), reportData?.netProfit || 0],
      backgroundColor: ['rgba(54, 162, 235, 0.8)', 'rgba(255, 159, 64, 0.8)', 'rgba(75, 192, 192, 0.8)', 'rgba(255, 99, 132, 0.8)', 'rgba(75, 192, 192, 0.8)'],
      borderColor: ['rgba(54, 162, 235, 1)', 'rgba(255, 159, 64, 1)', 'rgba(75, 192, 192, 1)', 'rgba(255, 99, 132, 1)', 'rgba(75, 192, 192, 1)'],
      borderWidth: 1,
    }],
  };

  const chartOptions = {
    responsive: true,
    plugins: { legend: { position: 'top' as const }, title: { display: true, text: 'Profit & Loss Breakdown' } },
    scales: { y: { beginAtZero: true, ticks: { callback: function(this: unknown, value: number) { return formatCurrency(value); } } } }
  };

  return (
    <div className="profit-loss-report">
      <div className="page-header">
        <div><h1>Profit & Loss Report</h1><p className="page-subtitle">Financial performance analysis for the selected period</p></div>
      </div>
      <div className="report-controls">
        <Button variant="secondary" onClick={() => setShowFilters(!showFilters)} className="filter-toggle" type="button"><Filter size={18} />{showFilters ? 'Hide Filters' : 'Show Filters'}</Button>
        <div className="export-buttons">
          <Button variant="secondary" onClick={() => handleExport('pdf')} className="export-btn" type="button"><Download size={18} /> Export PDF</Button>
          <Button variant="secondary" onClick={() => handleExport('excel')} className="export-btn" type="button"><Download size={18} /> Export Excel</Button>
        </div>
      </div>
      {showFilters && (
        <form onSubmit={handleFilterSubmit} className="report-filters">
          <div className="filter-row">
            <DateRangePicker fromDate={dateRange.fromDate} toDate={dateRange.toDate}
              onFromDateChange={(d: string) => setDateRange(p => ({ ...p, fromDate: d }))}
              onToDateChange={(d: string) => setDateRange(p => ({ ...p, toDate: d }))} />
            <Button type="submit" variant="primary" className="apply-filters-btn">Apply Filters</Button>
          </div>
        </form>
      )}
      {isLoading ? <div className="loading"><div className="spinner"></div></div>
      : reportData ? <div className="report-content">
        <StatsGrid columns={4} className="compact">
          <StatCard icon={DollarSign} label="Total Revenue" value={formatCurrency(reportData.totalRevenue)} />
          <StatCard icon={TrendingDown} label="Cost of Goods Sold (COGS)" value={formatCurrency(reportData.totalCogs)} style={reportData.totalCogs > 0 ? { color: '#dc3545' } : undefined} />
          <StatCard icon={TrendingUp} label="Gross Profit" value={formatCurrency(reportData.grossProfit)} />
          <StatCard icon={Calculator} label="Total Expenses" value={formatCurrency(reportData.totalExpenses)} style={reportData.totalExpenses > 0 ? { color: '#dc3545' } : undefined} />
          <StatCard icon={DollarSign} label="Net Profit" value={formatCurrency(reportData.netProfit)} style={reportData.netProfit < 0 ? { color: '#dc3545' } : undefined} />
          <StatCard icon={TrendingUp} label="Gross Profit Margin" value={`${reportData.grossProfitMargin}%`} />
          <StatCard icon={BarChart3} label="Net Profit Margin" value={`${reportData.netProfitMargin}%`} />
        </StatsGrid>
        <div className="chart-container"><Bar key="profit-loss-chart" data={chartData} options={chartOptions} /></div>
      </div> : <div className="no-data"><Calculator size={48} /><h3>No financial data found</h3><p>Try adjusting your filters to see profit & loss data.</p></div>}
    </div>
  );
}
