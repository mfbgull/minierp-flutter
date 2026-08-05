import { useState, useEffect, lazy, Suspense } from 'react';
import { Toaster } from 'react-hot-toast';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';

import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

import { KeyboardShortcutsHelp } from './components/common/KeyboardShortcutsHelp';
import PageLoader from './components/common/PageLoader';
import SearchModal from './components/common/SearchModal';
import ErrorBoundary from './components/ErrorBoundary';
import FloatingActionButton from './components/layout/FloatingActionButton';
import ShortcutBar from './components/layout/ShortcutBar';
import Sidebar from './components/layout/Sidebar';
import TopMenu from './components/layout/TopMenu';
import { AuthProvider, useAuth } from './context/AuthContext';
import { InvoiceProvider } from './context/InvoiceContext';
import { KeyboardShortcutsProvider } from './context/KeyboardShortcutsContext';
import { SettingsProvider } from './context/SettingsContext';
import { ThemeProvider } from './context/ThemeContext';
import Dashboard from './pages/Dashboard';
import LoginPage from './pages/LoginPage';

// Lazy loaded - Inventory module
const ItemsPage = lazy(() => import('./pages/inventory/ItemsPage'));
const WarehousesPage = lazy(() => import('./pages/inventory/WarehousesPage'));
const StockMovementPage = lazy(() => import('./pages/inventory/StockMovementPage'));
const StockByWarehousePage = lazy(() => import('./pages/inventory/StockByWarehousePage'));
const PhysicalCountsPage = lazy(() => import('./pages/inventory/PhysicalCountsPage'));

// Lazy loaded - Purchase module
const PurchasesPage = lazy(() => import('./pages/purchases/PurchasesPage'));
const PurchaseReturnHistory = lazy(() => import('./pages/purchases/PurchaseReturnHistory'));
const PurchaseOrdersPage = lazy(() => import('./pages/purchase-orders/PurchaseOrdersPage'));
const PurchaseOrderFormPage = lazy(() => import('./pages/purchase-orders/PurchaseOrderFormPage'));
const PurchaseOrderDetailPage = lazy(() => import('./pages/purchase-orders/PurchaseOrderDetailPage'));

// Lazy loaded - Suppliers module
const SuppliersPage = lazy(() => import('./pages/suppliers/SuppliersPage'));
const SupplierFormPage = lazy(() => import('./pages/suppliers/SupplierFormPage'));
const SupplierDetailPage = lazy(() => import('./pages/suppliers/SupplierDetailPage'));
const SupplierStatement = lazy(() => import('./pages/suppliers/SupplierStatement'));

// Lazy loaded - BOM & Production
const BOMPage = lazy(() => import('./pages/bom/BOMPage'));
const ProductionPage = lazy(() => import('./pages/production/ProductionPage'));

// Lazy loaded - Sales module
const SalesPage = lazy(() => import('./pages/sales/SalesPage'));
const SalesInvoicePage = lazy(() => import('./pages/sales/SalesInvoicePage'));
const InvoiceViewPage = lazy(() => import('./pages/sales/InvoiceViewPage'));
const InvoiceReturnHistory = lazy(() => import('./pages/sales/InvoiceReturnHistory'));
const InvoiceRouter = lazy(() => import('./components/invoice/InvoiceRouter'));
const InvoiceWizardPage = lazy(() => import('./pages/invoice/InvoiceWizardPage'));
const SalesInvoiceV2Page = lazy(() => import('./pages/sales/SalesInvoiceV2Page'));

// Quotations & Sales Orders
const QuotationsPage = lazy(() => import('./pages/quotations/QuotationsPage'));
const QuotationFormPage = lazy(() => import('./pages/quotations/QuotationFormPage'));
const QuotationViewPage = lazy(() => import('./pages/quotations/QuotationViewPage'));
const SalesOrdersPage = lazy(() => import('./pages/sales-orders/SalesOrdersPage'));
const SalesOrderFormPage = lazy(() => import('./pages/sales-orders/SalesOrderFormPage'));

// Lazy loaded - Customers module
const CustomersPage = lazy(() => import('./pages/customers/CustomersPage'));
const CustomerDetailPage = lazy(() => import('./pages/customers/CustomerDetailPage'));
const CustomerStatement = lazy(() => import('./pages/customers/CustomerStatement'));

// Lazy loaded - POS
const POSPage = lazy(() => import('./pages/pos/POSPage'));

// Lazy loaded - Reports module (heavy)
const ReportsDashboard = lazy(() => import('./pages/reports/ReportsDashboard'));
const ARReportsPage = lazy(() => import('./pages/reports/ARReportsPage'));
const SalesSummaryReport = lazy(() => import('./pages/reports/SalesSummaryReport'));
const SalesByCustomerReport = lazy(() => import('./pages/reports/SalesByCustomerReport'));
const SalesByItemReport = lazy(() => import('./pages/reports/SalesByItemReport'));
const StockLevelReport = lazy(() => import('./pages/reports/StockLevelReport'));
const StockValuationReport = lazy(() => import('./pages/reports/StockValuationReport'));
const InventoryMovementReport = lazy(() => import('./pages/reports/InventoryMovementReport'));
const LowStockReport = lazy(() => import('./pages/reports/LowStockReport'));
const ProfitLossReport = lazy(() => import('./pages/reports/ProfitLossReport'));
const CashFlowReport = lazy(() => import('./pages/reports/CashFlowReport'));
const CustomerStatementsReport = lazy(() => import('./pages/reports/CustomerStatementsReport'));
const TopDebtorsReport = lazy(() => import('./pages/reports/TopDebtorsReport'));
const DSOReport = lazy(() => import('./pages/reports/DSOReport'));
const PurchaseSummaryReport = lazy(() => import('./pages/reports/PurchaseSummaryReport'));
const SupplierAnalysisReport = lazy(() => import('./pages/reports/SupplierAnalysisReport'));
const ProductionSummaryReport = lazy(() => import('./pages/reports/ProductionSummaryReport'));
const BOMUsageReport = lazy(() => import('./pages/reports/BOMUsageReport'));
const ExpensesReport = lazy(() => import('./pages/reports/ExpensesReport'));

// Lazy loaded - Other pages
const SettingsPage = lazy(() => import('./pages/SettingsPage'));
const UsersPage = lazy(() => import('./pages/users/UsersPage'));
const RolesPage = lazy(() => import('./pages/roles/RolesPage'));
const IntegrationsPage = lazy(() => import('./pages/integrations/IntegrationsPage'));
const ExpensesPage = lazy(() => import('./pages/expenses/ExpensesPage'));
const EmployeesPage = lazy(() => import('./pages/employees/EmployeesPage'));
const PaymentsPage = lazy(() => import('./pages/payments/PaymentsPage'));
const ActivityLogPage = lazy(() => import('./pages/ActivityLogPage'));
const ForecastDashboard = lazy(() => import('./pages/forecasts/ForecastDashboard'));
const DemandForecast = lazy(() => import('./pages/forecasts/DemandForecast'));
const ForecastTrends = lazy(() => import('./pages/forecasts/ForecastTrends'));
const ForecastAccuracy = lazy(() => import('./pages/forecasts/ForecastAccuracy'));
const EcosystemView = lazy(() => import('./pages/EcosystemView'));
const CustomReportsPage = lazy(() => import('./pages/reports/CustomReportsPage'));
const ReportBuilder = lazy(() => import('./pages/reports/ReportBuilder'));

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      refetchOnWindowFocus: false,
      staleTime: 5 * 60 * 1000, // 5 minutes - data stays fresh for 5 min before refetching
      gcTime: 10 * 60 * 1000, // 10 minutes - keep data in cache for 10 min
      retry: 1
    }
  }
});

interface ProtectedRouteProps {
  children: React.ReactNode;
}

function ProtectedRoute({ children }: ProtectedRouteProps) {
  const { isAuthenticated, loading } = useAuth();

  if (loading) {
    return (
      <div className="loading">
        <div className="spinner"></div>
      </div>
    );
  }

  return isAuthenticated ? <>{children}</> : <Navigate to="/login" />;
}

function AppLayout() {
  const [isDesktop, setIsDesktop] = useState(() => {
    return window.innerWidth > 768;
  });
  const [isSearchOpen, setIsSearchOpen] = useState(false);
  const [navMode, setNavMode] = useState<'topmenu' | 'sidebar'>(() => {
    const saved = localStorage.getItem('navMode');
    return (saved === 'topmenu' || saved === 'sidebar') ? saved : 'topmenu';
  });

  useEffect(() => {
    const handleResize = () => {
      setIsDesktop(window.innerWidth > 768);
    };
    
    window.addEventListener('resize', handleResize);
    return () => window.removeEventListener('resize', handleResize);
  }, []);

  const toggleNavMode = () => {
    const newMode = navMode === 'topmenu' ? 'sidebar' : 'topmenu';
    setNavMode(newMode);
    localStorage.setItem('navMode', newMode);
  };

  const isMobile = !isDesktop;
  const showSidebar = isMobile || navMode === 'sidebar';
  const showTopMenu = isDesktop && navMode === 'topmenu';

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if ((e.ctrlKey || e.metaKey) && e.key === 'k') {
        e.preventDefault();
        setIsSearchOpen(true);
      }
    };

    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, []);

  return (
    <SettingsProvider>
      <div className="app-container">
        {/* Navigation: TopMenu or Sidebar based on mode */}
        {showSidebar && <Sidebar onToggleNav={toggleNavMode} isCompact={isDesktop} />}
        {showTopMenu && <TopMenu onToggleNav={toggleNavMode} />}
        <div className={`main-content ${showTopMenu ? 'topmenu-active' : ''} ${showSidebar && isDesktop ? 'sidebar-active' : ''}`}>
          <div className="content">
            <ErrorBoundary>
              <Suspense fallback={<PageLoader />}>
                <Routes>
              <Route path="/" element={<Dashboard />} />
              <Route path="/inventory/items" element={<ItemsPage />} />
              <Route path="/inventory/warehouses" element={<WarehousesPage />} />
              <Route path="/inventory/stock-movements" element={<StockMovementPage />} />
              <Route path="/inventory/stock-by-warehouse" element={<StockByWarehousePage />} />
              <Route path="/inventory/physical-counts" element={<PhysicalCountsPage />} />
              <Route path="/purchases" element={<PurchasesPage />} />
              <Route path="/purchases/returns" element={<PurchaseReturnHistory />} />
              <Route path="/suppliers" element={<SuppliersPage />} />
              <Route path="/suppliers/create" element={<SupplierFormPage mode="create" />} />
              <Route path="/suppliers/:id" element={<SupplierDetailPage />} />
              <Route path="/suppliers/:id/statement" element={<SupplierStatement />} />
              <Route path="/suppliers/:id/edit" element={<SupplierFormPage mode="edit" />} />
              <Route path="/purchase-orders" element={<PurchaseOrdersPage />} />
              <Route path="/purchase-orders/create" element={<PurchaseOrderFormPage mode="create" />} />
              <Route path="/purchase-orders/:id" element={<PurchaseOrderDetailPage />} />
              <Route path="/purchase-orders/:id/edit" element={<PurchaseOrderFormPage mode="edit" />} />
              <Route path="/bom" element={<BOMPage />} />
              <Route path="/production" element={<ProductionPage />} />
              <Route path="/customers" element={<CustomersPage />} />
              <Route path="/customers/:id" element={<CustomerDetailPage />} />
              <Route path="/customers/:id/statement" element={<CustomerStatement />} />
              <Route path="/reports" element={<ReportsDashboard />} />
              <Route path="/reports/accounts-receivable" element={<ARReportsPage />} />
              <Route path="/reports/sales-summary" element={<SalesSummaryReport />} />
              <Route path="/reports/sales-by-customer" element={<SalesByCustomerReport />} />
              <Route path="/reports/sales-by-item" element={<SalesByItemReport />} />
              <Route path="/reports/stock-level" element={<StockLevelReport />} />
              <Route path="/reports/stock-valuation" element={<StockValuationReport />} />
              <Route path="/reports/inventory-movement" element={<InventoryMovementReport />} />
              <Route path="/reports/profit-loss" element={<ProfitLossReport />} />
              <Route path="/reports/cash-flow" element={<CashFlowReport />} />
              <Route path="/reports/low-stock" element={<LowStockReport />} />
              <Route path="/reports/customer-statements" element={<CustomerStatementsReport />} />
              <Route path="/reports/top-debtors" element={<TopDebtorsReport />} />
              <Route path="/reports/dso" element={<DSOReport />} />
              <Route path="/reports/purchase-summary" element={<PurchaseSummaryReport />} />
              <Route path="/reports/supplier-analysis" element={<SupplierAnalysisReport />} />
              <Route path="/reports/production-summary" element={<ProductionSummaryReport />} />
              <Route path="/reports/bom-usage" element={<BOMUsageReport />} />
              <Route path="/reports/expenses" element={<ExpensesReport />} />
              <Route path="/expenses" element={<ExpensesPage />} />
              <Route path="/employees" element={<EmployeesPage />} />
              <Route path="/payments" element={<PaymentsPage />} />
<Route path="/sales" element={<SalesPage />} />
              <Route path="/quotations" element={<QuotationsPage />} />
              <Route path="/quotations/create" element={<QuotationFormPage mode="create" />} />
              <Route path="/quotations/:id" element={<QuotationViewPage />} />
              <Route path="/quotations/:id/edit" element={<QuotationFormPage mode="edit" />} />
              <Route path="/sales-orders" element={<SalesOrdersPage />} />
              <Route path="/sales-orders/create" element={<SalesOrderFormPage mode="create" />} />
              <Route path="/sales-orders/:id" element={<SalesOrderFormPage mode="view" />} />
              <Route path="/sales-orders/:id/edit" element={<SalesOrderFormPage mode="edit" />} />
              <Route path="/sales/invoice" element={<SalesInvoicePage />} />
              <Route path="/sales/invoice/:id" element={<InvoiceRouter />} />
              <Route path="/sales/invoice/:id/view" element={<InvoiceViewPage />} />
              <Route path="/sales/invoice/:id/edit" element={<InvoiceRouter defaultMode="edit" />} />
              <Route path="/sales/invoice-v2" element={<SalesInvoiceV2Page />} />
              <Route path="/sales/returns" element={<InvoiceReturnHistory />} />
              <Route path="/invoices/create" element={<InvoiceWizardPage />} />
              <Route path="/pos" element={<POSPage />} />
              <Route path="/settings" element={<SettingsPage />} />
              <Route path="/users" element={<UsersPage />} />
              <Route path="/roles" element={<RolesPage />} />
              <Route path="/integrations" element={<IntegrationsPage />} />
              <Route path="/activity-log" element={<ActivityLogPage />} />
              <Route path="/forecasts" element={<ForecastDashboard />} />
              <Route path="/forecasts/demand" element={<DemandForecast />} />
              <Route path="/forecasts/trends" element={<ForecastTrends />} />
              <Route path="/forecasts/accuracy" element={<ForecastAccuracy />} />
              <Route path="/ecosystem" element={<EcosystemView />} />
              <Route path="/reports/custom" element={<CustomReportsPage />} />
              <Route path="/reports/custom/:id/edit" element={<ReportBuilder />} />
              <Route path="*" element={<Navigate to="/" />} />
                </Routes>
              </Suspense>
            </ErrorBoundary>
            <FloatingActionButton />
          </div>
          <ShortcutBar />
        </div>
        <SearchModal isOpen={isSearchOpen} onClose={() => setIsSearchOpen(false)} />
      </div>
    </SettingsProvider>
  );
}

function AppRoutesOuter() {
  const { isAuthenticated } = useAuth();

  return (
    <Routes>
      <Route
        path="/login"
        element={isAuthenticated ? <Navigate to="/" /> : <LoginPage />}
      />

      <Route
        path="/*"
        element={
          <ProtectedRoute>
            <AppLayout />
          </ProtectedRoute>
        }
      />

      <Route path="*" element={<Navigate to="/" />} />
    </Routes>
  );
}

export default function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <BrowserRouter>
        <AuthProvider>
          <ThemeProvider>
            <KeyboardShortcutsProvider>
              <InvoiceProvider>
                <AppRoutesOuter />
              </InvoiceProvider>
              <KeyboardShortcutsHelp />
              <Toaster
                position="top-right"
                toastOptions={{
                  duration: 3000,
                  style: {
                    background: '#363636',
                    color: '#fff'
                  },
                  success: {
                    iconTheme: {
                      primary: 'var(--success)',
                      secondary: '#fff'
                    }
                  },
                  error: {
                    iconTheme: {
                      primary: 'var(--error)',
                      secondary: '#fff'
                    }
                  }
                }}
              />
            </KeyboardShortcutsProvider>
          </ThemeProvider>
        </AuthProvider>
      </BrowserRouter>
    </QueryClientProvider>
  );
}
