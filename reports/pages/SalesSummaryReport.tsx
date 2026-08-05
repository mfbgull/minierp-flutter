import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import MiniERPGrid from '../../components/common/MiniERPGrid';
import {
  TrendingUp,
  FileText,
  Package,
  Download,
  Filter,
  BarChart3,
  DollarSign
} from 'lucide-react';

import Button from '../../components/common/Button';
import CompactSalesSummaryCardView from '../../components/common/CompactSalesSummaryCard';
import DateRangePicker from '../../components/common/DateRangePicker';
import SearchableSelect from '../../components/common/SearchableSelect';
import StatCard, { StatsGrid } from '../../components/common/StatCard';
import type { DateRangeFilter } from '../../types';
import { useSettings } from '../../context/SettingsContext';
import { useMobileDetection } from '../../hooks/useMobileDetection';
import api from '../../utils/api';
import { exportToPDF, exportToExcel } from '../../utils/exportUtils';
import './SalesReports.css';
import '../../styles/ag-grid-status-cells.css';
import { getStatusCellClass } from '../../utils/statusCellUtils';

interface Customer {
  id: number;
  customer_name: string;
}

interface InventoryItem {
  id: number;
  item_name: string;
  is_finished_good?: boolean | number;
}

interface SalesSummaryData {
  sales?: Record<string, unknown>[];
  summary?: {
    totalInvoices?: number;
    totalSales?: number;
    totalItemsSold?: number;
    averageInvoiceValue?: number;
  };
}

export default function SalesSummaryReport() {
  const [dateRange, setDateRange] = useState<DateRangeFilter>({
    fromDate: new Date(new Date().setMonth(new Date().getMonth() - 1)).toISOString().split('T')[0],
    toDate: new Date().toISOString().split('T')[0]
  });
  const [customerIds, setCustomerIds] = useState<number[]>([]);
  const [itemIds, setItemIds] = useState<number[]>([]);
  const [showFilters, setShowFilters] = useState(false);
  const { formatCurrency } = useSettings();
  const { isMobile } = useMobileDetection();

  const { data: customers = [] } = useQuery<Customer[]>({
    queryKey: ['customers'],
    queryFn: async () => {
      const response = await api.get('/customers');
      return response.data.data || [];
    }
  });

  const { data: allItems = [], isLoading: itemsLoading } = useQuery<InventoryItem[]>({
    queryKey: ['items-all'],
    queryFn: async () => {
      const response = await api.get('/inventory/items');
      return response.data.data || [];
    }
  });

  const items = allItems.filter(item => item.is_finished_good === 1 || item.is_finished_good === true);

  const { data: reportData, isLoading, refetch } = useQuery<SalesSummaryData>({
    queryKey: ['salesSummary', dateRange, customerIds, itemIds],
    queryFn: async () => {
      const params = new URLSearchParams();
      params.append('fromDate', dateRange.fromDate);
      params.append('toDate', dateRange.toDate);
      if (customerIds.length > 0) {
        customerIds.forEach(id => params.append('customerIds', String(id)));
      }
      if (itemIds.length > 0) {
        itemIds.forEach(id => params.append('itemIds', String(id)));
      }

      const response = await api.get(`/reports/sales-summary?${params}`);
      return response.data.data;
    }
  });

  const handleFilterSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    refetch();
  };

  const handleExport = (format: string = 'pdf') => {
    if (!reportData?.sales) {
      console.error('No data to export');
      return;
    }

    const exportColumns = [
      { headerName: 'Invoice Date', field: 'invoice_date', valueFormatter: (params: { value: string }) => params.value ? new Date(params.value).toLocaleDateString() : '' },
      { headerName: 'Invoice No', field: 'invoice_no' },
      { headerName: 'Customer', field: 'customer_name' },
      { headerName: 'Total Sales', field: 'total_sales', valueFormatter: (params: { value: number }) => formatCurrency(params.value || 0) },
      { headerName: 'Items', field: 'total_items' },
      { headerName: 'Paid Amount', field: 'paid_amount', valueFormatter: (params: { value: number }) => formatCurrency(params.value || 0) },
      { headerName: 'Balance', field: 'balance_amount', valueFormatter: (params: { value: number }) => formatCurrency(params.value || 0) },
      { headerName: 'Status', field: 'status' }
    ];

    if (format === 'pdf') {
      exportToPDF(reportData.sales as unknown as Record< string,unknown >[], exportColumns, 'Sales Summary Report', `sales-summary-${new Date().toISOString().split('T')[0]}.pdf`);
    } else if (format === 'excel') {
      exportToExcel(reportData.sales as unknown as Record< string,unknown >[], exportColumns, 'Sales Summary Report', `sales-summary-${new Date().toISOString().split('T')[0]}.csv`);
    }
  };

  const columnDefs = [
    { headerName: 'Invoice Date', field: 'invoice_date', filter: 'agDateColumnFilter', width: 120, valueFormatter: (params: { value: string }) => params.value ? new Date(params.value).toLocaleDateString() : '' },
    { headerName: 'Invoice No', field: 'invoice_no', filter: true, width: 120 },
    { headerName: 'Customer', field: 'customer_name', filter: true, flex: 1 },
    { headerName: 'Total Sales', field: 'total_sales', filter: 'agNumberColumnFilter', width: 140, valueFormatter: (params: { value: number }) => formatCurrency(params.value || 0), cellClass: 'amount-cell' },
    { headerName: 'Items', field: 'total_items', filter: 'agNumberColumnFilter', width: 100, cellClass: 'number-cell' },
    { headerName: 'Paid Amount', field: 'paid_amount', filter: 'agNumberColumnFilter', width: 140, valueFormatter: (params: { value: number }) => formatCurrency(params.value || 0), cellClass: 'amount-cell' },
    { headerName: 'Balance', field: 'balance_amount', filter: 'agNumberColumnFilter', width: 140, valueFormatter: (params: { value: number }) => formatCurrency(params.value || 0), cellClass: 'amount-cell' },
    { headerName: 'Status', field: 'status', filter: true, width: 120, cellClass: (params: { value: string }) => getStatusCellClass(params.value) }
  ];

  return (
    <div className="sales-summary-report">
      <div className="page-header">
        <div>
          <h1>Sales Summary Report</h1>
          <p className="page-subtitle">Comprehensive analysis of sales performance</p>
        </div>
      </div>

      <div className="report-controls">
        <Button variant="secondary" onClick={() => setShowFilters(!showFilters)} className="filter-toggle" type="button">
          <Filter size={18} />
          {showFilters ? 'Hide Filters' : 'Show Filters'}
        </Button>
        <div className="export-buttons">
          <Button variant="secondary" onClick={() => handleExport('pdf')} className="export-btn" type="button"><Download size={18} /> Export PDF</Button>
          <Button variant="secondary" onClick={() => handleExport('excel')} className="export-btn" type="button"><Download size={18} /> Export Excel</Button>
        </div>
      </div>

      {showFilters && (
        <form onSubmit={handleFilterSubmit} className="report-filters">
          <div className="filter-row">
            <DateRangePicker fromDate={dateRange.fromDate} toDate={dateRange.toDate}
              onFromDateChange={(date: string) => setDateRange(prev => ({ ...prev, fromDate: date }))}
              onToDateChange={(date: string) => setDateRange(prev => ({ ...prev, toDate: date }))} />
            <SearchableSelect label="Customer" name="customer" value={customerIds}
              onChange={(value: any) => setCustomerIds(value as number[])}
              options={customers.map(c => ({ value: c.id, label: c.customer_name }))}
              placeholder="Search customers..." multiple={true} loading={customers.length === 0} />
            <SearchableSelect label="Item" name="item" value={itemIds}
              onChange={(value: any) => setItemIds(value as number[])}
              options={items.map(i => ({ value: i.id, label: i.item_name }))}
              placeholder="Search items..." multiple={true} loading={itemsLoading} />
            <Button type="submit" variant="primary" className="apply-filters-btn">Apply Filters</Button>
          </div>
        </form>
      )}

      {reportData?.summary && (
        <StatsGrid className="compact">
          <StatCard icon={FileText} label="Total Invoices" value={reportData.summary.totalInvoices} />
          <StatCard icon={DollarSign} label="Total Sales" value={formatCurrency(reportData.summary.totalSales)} />
          <StatCard icon={Package} label="Items Sold" value={reportData.summary.totalItemsSold} />
          <StatCard icon={TrendingUp} label="Avg. Invoice Value" value={formatCurrency(reportData.summary.averageInvoiceValue)} />
        </StatsGrid>
      )}

      <div className="report-content">
        {isLoading ? (
          <div className="loading"><div className="spinner"></div></div>
        ) : reportData?.sales && reportData.sales.length > 0 ? (
          isMobile ? (
            <CompactSalesSummaryCardView sales={reportData.sales as any} />
          ) : (
            <MiniERPGrid
              containerStyle={{ height: 600, width: '100%' }}
              rowData={reportData.sales as any || []}
              columnDefs={columnDefs as any}
              paginationPageSize={20}
              paginationPageSizeSelector={[10, 20, 50, 100]}
            />
          )
        ) : (
          <div className="no-data">
            <BarChart3 size={48} />
            <h3>No sales data found</h3>
            <p>Try adjusting your filters to see sales data.</p>
          </div>
        )}
      </div>
    </div>
  );
}
