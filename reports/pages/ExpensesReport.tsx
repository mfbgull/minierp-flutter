import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import MiniERPGrid from '../../components/common/MiniERPGrid';
import {
  FileText,
  DollarSign,
  Download,
  Filter,
  BarChart3,
  Package,
  X,
  CheckCircle
} from 'lucide-react';

import Button from '../../components/common/Button';
import DateRangePicker from '../../components/common/DateRangePicker';
import SearchableSelect from '../../components/common/SearchableSelect';
import StatCard, { StatsGrid } from '../../components/common/StatCard';
import type { DateRangeFilter } from '../../types';
import { useSettings } from '../../context/SettingsContext';
import api from '../../utils/api';
import { exportToPDF, exportToExcel } from '../../utils/exportUtils';
import './ExpensesReport.css';
import '../../styles/ag-grid-status-cells.css';
import { getStatusCellClass } from '../../utils/statusCellUtils';

interface ExpenseRecord {
  id: number;
  expense_no: string;
  expense_category: string;
  description?: string;
  amount: number;
  expense_date: string;
  payment_method?: string;
  reference_no?: string;
  vendor_name?: string;
  project?: string;
  status: string;
}

interface ExpenseCategory {
  category_name: string;
}

interface ExpensesReportData {
  expenses?: ExpenseRecord[];
  summary?: {
    totalAmount: number;
    totalExpenses: number;
    averageAmount: number;
  };
  categoryBreakdown?: Array<{
    expense_category: string;
    total_amount: number;
    count: number;
  }>;
}

interface ExpenseCardProps {
  expense: ExpenseRecord;
  formatCurrency: (amount: number | string | null | undefined) => string;
}

function ExpenseCard({ expense, formatCurrency }: ExpenseCardProps) {
  const [showDetails, setShowDetails] = useState(false);
  const statusClass = `expense-status status-${expense.status?.toLowerCase().replace(/\s+/g, '-')}`;

  return (
    <>
      <div className="compact-expense-card" onClick={() => setShowDetails(true)}>
        <div className="compact-expense-info">
          <p className="compact-expense-no">{expense.expense_no}</p>
          <span className="compact-expense-category">{expense.expense_category}</span>
        </div>
        <div className="compact-expense-right">
          <span className="compact-expense-amount">{formatCurrency(expense.amount)}</span>
          <span className={statusClass}>{expense.status}</span>
        </div>
      </div>
      {showDetails && (
        <div className="item-preview-overlay" onClick={() => setShowDetails(false)}>
          <div className="item-preview-container" onClick={(e: React.MouseEvent) => e.stopPropagation()}>
            <div className="swipe-indicator"></div>
            <div className="item-preview-header">
              <div className="item-preview-title-section">
                <h2 className="item-preview-title">{expense.expense_no}</h2>
                <span className="item-preview-code">{expense.expense_category}</span>
              </div>
              <button className="item-preview-close" onClick={() => setShowDetails(false)}><X size={24} /></button>
            </div>
            <div className="item-preview-content">
              <div className="item-preview-stats">
                <div className="preview-stat"><span className="preview-stat-label">Amount</span><span className="preview-stat-value expense-amount-highlight">{formatCurrency(expense.amount)}</span></div>
                <div className="preview-stat"><span className="preview-stat-label">Status</span><span className={statusClass}>{expense.status}</span></div>
                <div className="preview-stat"><span className="preview-stat-label">Date</span><span className="preview-stat-value">{new Date(expense.expense_date).toLocaleDateString()}</span></div>
              </div>
              <div className="preview-details-grid">
                {expense.description && <div className="preview-detail-item full-width"><span className="preview-detail-label">Description</span><span className="preview-detail-value">{expense.description}</span></div>}
                {expense.vendor_name && <div className="preview-detail-item"><span className="preview-detail-label">Vendor</span><span className="preview-detail-value">{expense.vendor_name}</span></div>}
                {expense.payment_method && <div className="preview-detail-item"><span className="preview-detail-label">Payment Method</span><span className="preview-detail-value">{expense.payment_method}</span></div>}
                {expense.reference_no && <div className="preview-detail-item"><span className="preview-detail-label">Reference No</span><span className="preview-detail-value">{expense.reference_no}</span></div>}
                {expense.project && <div className="preview-detail-item"><span className="preview-detail-label">Project</span><span className="preview-detail-value">{expense.project}</span></div>}
              </div>
            </div>
          </div>
        </div>
      )}
    </>
  );
}

export default function ExpensesReport() {
  const [dateRange, setDateRange] = useState<DateRangeFilter>({
    fromDate: new Date(new Date().setMonth(new Date().getMonth() - 1)).toISOString().split('T')[0],
    toDate: new Date().toISOString().split('T')[0]
  });
  const [filters, setFilters] = useState({ category: '', vendor: '' });
  const [showFilters, setShowFilters] = useState(false);
  const { formatCurrency } = useSettings();

  const { data: categories = [] } = useQuery<ExpenseCategory[]>({
    queryKey: ['expenseCategories'],
    queryFn: async () => { const r = await api.get('/expenses/categories'); return r.data.data; }
  });

  const { data: reportData, isLoading, refetch } = useQuery<ExpensesReportData>({
    queryKey: ['expensesReport', dateRange, filters],
    queryFn: async () => {
      const params = new URLSearchParams();
      params.append('from_date', dateRange.fromDate); params.append('to_date', dateRange.toDate);
      if (filters.category) params.append('category', filters.category);
      if (filters.vendor) params.append('vendor', filters.vendor);
      const r = await api.get(`/reports/expenses?${params}`); return r.data.data;
    }
  });

  const handleFilterSubmit = (e: React.FormEvent) => { e.preventDefault(); refetch(); };

  const handleExport = (format = 'pdf') => {
    if (!reportData?.expenses) return;
    const cols = [
      { headerName: 'Date', field: 'expense_date', valueFormatter: (p: { value: string }) => p.value ? new Date(p.value).toLocaleDateString() : '' },
      { headerName: 'Expense No', field: 'expense_no' },
      { headerName: 'Category', field: 'expense_category' },
      { headerName: 'Description', field: 'description' },
      { headerName: 'Vendor', field: 'vendor_name' },
      { headerName: 'Amount', field: 'amount', valueFormatter: (p: { value: number }) => formatCurrency(p.value || 0) },
      { headerName: 'Status', field: 'status' }
    ];
    if (format === 'pdf') exportToPDF(reportData.expenses as unknown as Record< string,unknown >[], cols, 'Expenses Report', `expenses-${new Date().toISOString().split('T')[0]}.pdf`);
    else exportToExcel(reportData.expenses as unknown as Record< string,unknown >[], cols, 'Expenses Report', `expenses-${new Date().toISOString().split('T')[0]}.csv`);
  };

  const columnDefs = [
    { headerName: 'Expense No', field: 'expense_no', filter: true, width: 140 },
    { headerName: 'Category', field: 'expense_category', filter: true, width: 140 },
    { headerName: 'Description', field: 'description', filter: true, flex: 1 },
    { headerName: 'Amount', field: 'amount', filter: 'agNumberColumnFilter', width: 120, valueFormatter: (p: { value: number }) => formatCurrency(p.value || 0), cellClass: 'amount-cell' },
    { headerName: 'Date', field: 'expense_date', filter: 'agDateColumnFilter', width: 120, valueFormatter: (p: { value: string }) => p.value ? new Date(p.value).toLocaleDateString() : '' },
    { headerName: 'Payment Method', field: 'payment_method', filter: true, width: 140 },
    { headerName: 'Reference No', field: 'reference_no', filter: true, width: 120 },
    { headerName: 'Vendor', field: 'vendor_name', filter: true, width: 140 },
    { headerName: 'Project', field: 'project', filter: true, width: 120 },
    { headerName: 'Status', field: 'status', filter: true, width: 120, cellClass: (p: { value: string }) => getStatusCellClass(p.value) }
  ];

  return (
    <div className="expenses-report">
      <div className="page-header">
        <div><h1>Expenses Report</h1><p className="page-subtitle">Detailed analysis of business expenses</p></div>
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
            <SearchableSelect label="Category" name="category" value={filters.category}
              onChange={(e: any) => setFilters(p => ({ ...p, category: e.target?.value || '' }))}
              options={[{ value: '', label: 'All Categories' }, ...categories.map(cat => ({ value: cat.category_name, label: cat.category_name }))]} />
            <div className="filter-group"><label>Vendor</label>
              <input type="text" value={filters.vendor} onChange={(e: React.ChangeEvent<HTMLInputElement>) => setFilters(p => ({ ...p, vendor: e.target.value }))} className="filter-select" placeholder="Search vendor..." />
            </div>
            <Button type="submit" variant="primary" className="apply-filters-btn">Apply Filters</Button>
          </div>
        </form>
      )}
      {reportData?.summary && (
        <StatsGrid className="compact">
          <StatCard icon={DollarSign} label="Total Expenses" value={formatCurrency(reportData.summary.totalAmount)} />
          <StatCard icon={FileText} label="Total Records" value={reportData.summary.totalExpenses} />
          <StatCard icon={CheckCircle} label="Average Expense" value={formatCurrency(reportData.summary.averageAmount)} />
        </StatsGrid>
      )}
      {reportData?.categoryBreakdown && reportData.categoryBreakdown.length > 0 && (
        <div className="report-section">
          <h3>Category Breakdown</h3>
          <div className="category-breakdown">
            {reportData.categoryBreakdown.map((category, index) => (
              <div key={index} className="category-item">
                <div className="category-name">{category.expense_category}</div>
                <div className="category-amount">{formatCurrency(category.total_amount)}</div>
                <div className="category-count">({category.count} expenses)</div>
              </div>
            ))}
          </div>
        </div>
      )}
      <div className="report-content">
        {isLoading ? <div className="loading"><div className="spinner"></div></div>
        : reportData?.expenses && reportData.expenses.length > 0 ? <>
          <MiniERPGrid
            wrapperClassName="desktop-view ag-grid-container"
            rowData={reportData.expenses}
            columnDefs={columnDefs as any}
            paginationPageSize={20}
            paginationPageSizeSelector={[10, 20, 50, 100]}
          />
          <div className="mobile-expenses-list">
            {reportData.expenses.map(expense => <ExpenseCard key={expense.id} expense={expense} formatCurrency={formatCurrency} />)}
          </div>
        </> : <div className="no-data"><FileText size={48} /><h3>No expenses data found</h3><p>Try adjusting your filters to see expenses data.</p></div>}
      </div>
    </div>
  );
}
