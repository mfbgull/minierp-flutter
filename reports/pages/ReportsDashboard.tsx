import { Link } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import {
  TrendingUp,
  Package,
  ShoppingCart,
  Users,
  FileText,
  BarChart3,
  Factory,
  CreditCard,
  DollarSign,
  AlertTriangle,
  Clock,
  PieChart,
  Wallet,
  Target,
  TrendingDown,
  Bell,
  Gem,
  ClipboardList,
  Banknote
} from 'lucide-react';

import StatCard, { StatsGrid } from '../../components/common/StatCard';
import { useSettings } from '../../context/SettingsContext';
import api from '../../utils/api';
import './ReportsDashboard.css';

interface ReportLink {
  name: string;
  description: string;
  path: string;
  icon: React.ComponentType<{ size?: number }>;
}

interface ReportCategory {
  title: string;
  icon: React.ComponentType<{ size?: number }>;
  color: string;
  reports: ReportLink[];
}

interface SalesSummaryData {
  data?: {
    summary?: {
      totalSales?: number;
    };
  };
}

interface StockLevelData {
  data?: {
    summary?: {
      totalItems?: number;
      lowStock?: number;
    };
  };
}

interface StockValuationData {
  data?: {
    summary?: {
      totalValue?: number;
    };
  };
}

interface ARAgingData {
  data?: {
    totalOutstanding?: number;
    overdue?: {
      amount?: number;
    };
  };
}

export default function ReportsDashboard() {
  const { formatCurrency } = useSettings();

  const { data: salesData } = useQuery<SalesSummaryData>({
    queryKey: ['reports', 'sales-summary'],
    queryFn: async () => {
      const response = await api.get('/reports/sales-summary');
      return response.data;
    }
  });

  const { data: inventoryStats } = useQuery<StockLevelData>({
    queryKey: ['reports', 'stock-level'],
    queryFn: async () => {
      const response = await api.get('/reports/stock-level');
      return response.data;
    }
  });

  const { data: stockValuation } = useQuery<StockValuationData>({
    queryKey: ['reports', 'stock-valuation'],
    queryFn: async () => {
      const response = await api.get('/reports/stock-valuation');
      return response.data;
    }
  });

  const { data: arAging } = useQuery<ARAgingData>({
    queryKey: ['reports', 'ar-summary'],
    queryFn: async () => {
      const response = await api.get('/reports/ar-summary');
      return response.data;
    }
  });

  const stats = {
    totalSales: (salesData as SalesSummaryData)?.data?.summary?.totalSales || 0,
    pendingPayments: (arAging as ARAgingData)?.data?.totalOutstanding || 0,
    overduePayments: (arAging as ARAgingData)?.data?.overdue?.amount || 0,
    totalItems: (inventoryStats as StockLevelData)?.data?.summary?.totalItems || 0,
    lowStockItems: (inventoryStats as StockLevelData)?.data?.summary?.lowStock || 0,
    inventoryValue: (stockValuation as StockValuationData)?.data?.summary?.totalValue || 0
  };

  const reportCategories: ReportCategory[] = [
    {
      title: 'Sales Reports',
      icon: TrendingUp,
      color: 'bg-blue-500',
      reports: [
        { name: 'Sales Summary', description: 'View sales performance and trends', path: '/reports/sales-summary', icon: TrendingUp },
        { name: 'Sales by Customer', description: 'Analyze sales by customer', path: '/reports/sales-by-customer', icon: Users },
        { name: 'Sales by Item', description: 'Track item-wise sales performance', path: '/reports/sales-by-item', icon: Package }
      ]
    },
    {
      title: 'Inventory Reports',
      icon: Package,
      color: 'bg-green-500',
      reports: [
        { name: 'Stock Levels', description: 'Current inventory levels', path: '/reports/stock-level', icon: Package },
        { name: 'Low Stock Alert', description: 'Items below minimum stock', path: '/reports/low-stock', icon: AlertTriangle },
        { name: 'Stock Valuation', description: 'Inventory value analysis', path: '/reports/stock-valuation', icon: DollarSign },
        { name: 'Inventory Movement', description: 'Track stock movements', path: '/reports/inventory-movement', icon: BarChart3 }
      ]
    },
    {
      title: 'Financial Reports',
      icon: DollarSign,
      color: 'bg-purple-500',
      reports: [
        { name: 'Profit & Loss', description: 'Revenue and expense analysis', path: '/reports/profit-loss', icon: TrendingUp },
        { name: 'Cash Flow', description: 'Cash inflow and outflow', path: '/reports/cash-flow', icon: Wallet },
        { name: 'Expenses', description: 'Business expenses analysis', path: '/reports/expenses', icon: CreditCard }
      ]
    },
    {
      title: 'Accounts Receivable',
      icon: CreditCard,
      color: 'bg-indigo-500',
      reports: [
        { name: 'AR Aging', description: 'Customer payment aging', path: '/reports/accounts-receivable', icon: Clock },
        { name: 'Customer Statements', description: 'Detailed customer statements', path: '/reports/customer-statements', icon: FileText },
        { name: 'Top Debtors', description: 'Customers with highest balances', path: '/reports/top-debtors', icon: Users },
        { name: 'DSO Analysis', description: 'Days Sales Outstanding', path: '/reports/dso', icon: Target }
      ]
    },
    {
      title: 'Purchase Reports',
      icon: ShoppingCart,
      color: 'bg-orange-500',
      reports: [
        { name: 'Purchase Summary', description: 'Overall purchase analysis', path: '/reports/purchase-summary', icon: ShoppingCart },
        { name: 'Supplier Analysis', description: 'Supplier performance analysis', path: '/reports/supplier-analysis', icon: Users }
      ]
    },
    {
      title: 'Production Reports',
      icon: Factory,
      color: 'bg-red-500',
      reports: [
        { name: 'Production Summary', description: 'Production order analysis', path: '/reports/production-summary', icon: Factory },
        { name: 'BOM Usage', description: 'Bill of Materials usage', path: '/reports/bom-usage', icon: BarChart3 }
      ]
    }
  ];

  return (
    <div className="reports-dashboard">
      <div className="page-header">
        <div>
          <h1>Reports Dashboard</h1>
          <p className="page-subtitle">Comprehensive business analytics and reporting</p>
        </div>
      </div>

      <StatsGrid className="compact">
        <StatCard icon={TrendingUp} label="Total Sales" value={formatCurrency(stats.totalSales)} subtitle="Revenue this period" />
        <StatCard icon={DollarSign} label="Outstanding" value={formatCurrency(stats.pendingPayments)} subtitle="Pending payments" style={{ borderColor: stats.pendingPayments > 0 ? '#f97316' : undefined }} />
        <StatCard icon={AlertTriangle} label="Overdue" value={formatCurrency(stats.overduePayments)} subtitle="Past due amount" alert />
        <StatCard icon={Package} label="Total Items" value={stats.totalItems} subtitle="In inventory" />
        <StatCard icon={Bell} label="Low Stock" value={stats.lowStockItems} subtitle="Need reorder" style={{ borderColor: stats.lowStockItems > 0 ? '#f59e0b' : undefined }} />
        <StatCard icon={Gem} label="Inventory Value" value={formatCurrency(stats.inventoryValue)} subtitle="Total stock worth" />
      </StatsGrid>

      <div className="quick-actions">
        <Link to="/reports/sales-summary" className="quick-action-btn" type="button">
          <BarChart3 className="action-icon" size={24} />
          <span className="action-text">Sales Summary</span>
        </Link>
        <Link to="/reports/accounts-receivable" className="quick-action-btn" type="button">
          <ClipboardList className="action-icon" size={24} />
          <span className="action-text">AR Aging</span>
        </Link>
        <Link to="/reports/low-stock" className="quick-action-btn" type="button">
          <AlertTriangle className="action-icon" size={24} />
          <span className="action-text">Low Stock</span>
        </Link>
        <Link to="/reports/profit-loss" className="quick-action-btn" type="button">
          <TrendingUp className="action-icon" size={24} />
          <span className="action-text">P&L Report</span>
        </Link>
        <Link to="/reports/stock-valuation" className="quick-action-btn" type="button">
          <DollarSign className="action-icon" size={24} />
          <span className="action-text">Stock Value</span>
        </Link>
        <Link to="/reports/cash-flow" className="quick-action-btn" type="button">
          <Banknote className="action-icon" size={24} />
          <span className="action-text">Cash Flow</span>
        </Link>
      </div>

      <div className="reports-grid">
        {reportCategories.map((category, index) => {
          const IconComponent = category.icon;
          return (
            <div key={index} className="report-category">
              <div className="category-header">
                <div className={`category-icon ${category.color}`}>
                  <IconComponent size={24} />
                </div>
                <h3 className="category-title">{category.title}</h3>
              </div>

              <div className="category-reports">
                {category.reports.map((report, reportIndex) => {
                  const ReportIcon = report.icon;
                  return (
                    <Link
                      key={reportIndex}
                      to={report.path}
                      className="report-card"
                    >
                      <div className="report-icon">
                        <ReportIcon size={20} />
                      </div>
                      <div className="report-info">
                        <h4 className="report-name">{report.name}</h4>
                        <p className="report-description">{report.description}</p>
                      </div>
                    </Link>
                  );
                })}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
