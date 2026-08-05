import { useState } from 'react';
import { Bar } from 'react-chartjs-2';
import { useQuery } from '@tanstack/react-query';
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  BarElement,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Legend,
} from 'chart.js';
import {
  TrendingUp,
  TrendingDown,
  DollarSign,
  Calendar,
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

ChartJS.register(CategoryScale, LinearScale, BarElement, PointElement, LineElement, Title, Tooltip, Legend);

interface CashFlowData {
  totalInflow: number;
  totalOutflow: number;
  netCashFlow: number;
}

export default function CashFlowReport() {
  const [dateRange, setDateRange] = useState<DateRangeFilter>({
    fromDate: new Date(new Date().setMonth(new Date().getMonth() - 1)).toISOString().split('T')[0],
    toDate: new Date().toISOString().split('T')[0]
  });
  const [showFilters, setShowFilters] = useState(false);
  const { formatCurrency } = useSettings();

  const { data: reportData, isLoading, refetch } = useQuery<CashFlowData>({
    queryKey: ['cashFlow', dateRange],
    queryFn: async () => {
      const params = new URLSearchParams();
      params.append('fromDate', dateRange.fromDate); params.append('toDate', dateRange.toDate);
      const r = await api.get(`/reports/cash-flow?${params}`); return r.data.data;
    }
  });

  const handleFilterSubmit = (e: React.FormEvent) => { e.preventDefault(); refetch(); };

  const handleExport = (format = 'pdf') => {
    if (!reportData) return;
    const d = [
      { metric: 'Total Cash Inflow', value: reportData.totalInflow },
      { metric: 'Total Cash Outflow', value: reportData.totalOutflow },
      { metric: 'Net Cash Flow', value: reportData.netCashFlow }
    ];
    const cols = [{ headerName: 'Metric', field: 'metric' }, { headerName: 'Value', field: 'value', valueFormatter: (p: { value: number }) => formatCurrency(p.value) }];
    if (format === 'pdf') exportToPDF(d, cols, 'Cash Flow Report', `cash-flow-${new Date().toISOString().split('T')[0]}.pdf`);
    else exportToExcel(d, cols, 'Cash Flow Report', `cash-flow-${new Date().toISOString().split('T')[0]}.csv`);
  };

  const chartData = {
    labels: ['Cash Inflow', 'Cash Outflow', 'Net Cash Flow'],
    datasets: [{
      label: 'Amount',
      data: [reportData?.totalInflow || 0, -(reportData?.totalOutflow || 0), reportData?.netCashFlow || 0],
      backgroundColor: ['rgba(54, 162, 235, 0.5)', 'rgba(255, 99, 132, 0.5)', 'rgba(75, 192, 192, 0.5)'],
      borderColor: ['rgb(54, 162, 235)', 'rgb(255, 99, 132)', 'rgb(75, 192, 192)'],
      borderWidth: 2,
    }],
  };

  const chartOptions = {
    responsive: true,
    plugins: { legend: { position: 'top' as const }, title: { display: true, text: 'Cash Flow Analysis' } },
    scales: { y: { beginAtZero: true, ticks: { callback: function(this: unknown, value: number) { return formatCurrency(value); } } } }
  };

  return (
    <div className="cash-flow-report">
      <div className="page-header">
        <div><h1>Cash Flow Report</h1><p className="page-subtitle">Cash inflow and outflow analysis for the selected period</p></div>
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
        <StatsGrid className="compact">
          <StatCard icon={DollarSign} label="Total Cash Inflow" value={formatCurrency(reportData.totalInflow)} />
          <StatCard icon={TrendingDown} label="Total Cash Outflow" value={formatCurrency(reportData.totalOutflow)} />
          <StatCard icon={TrendingUp} label="Net Cash Flow" value={formatCurrency(reportData.netCashFlow)} />
        </StatsGrid>
        <div className="chart-container"><Bar key="cashflow-chart" data={chartData} options={chartOptions} /></div>
        <div className="cash-flow-analysis">
          <h3>Cash Flow Analysis</h3>
          <p>Net cash flow represents the difference between cash inflows and outflows during the selected period.</p>
          <p>Outflows include payments for purchases and business expenses.</p>
          {reportData.netCashFlow > 0
            ? <p className="positive-analysis"><TrendingUp size={16} /> This period shows a positive cash flow, indicating good liquidity.</p>
            : <p className="negative-analysis"><TrendingDown size={16} /> This period shows a negative cash flow, consider reviewing expenses and cash outflows.</p>}
        </div>
      </div> : <div className="no-data"><TrendingUp size={48} /><h3>No cash flow data found</h3><p>Try adjusting your filters to see cash flow data.</p></div>}
    </div>
  );
}
