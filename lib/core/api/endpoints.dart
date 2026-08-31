/// API endpoint constants — mirrors the REST contract in docs/API.md
/// (~100 endpoints). Add each module's routes as it is ported.
abstract final class ApiEndpoints {
  // Auth (§3)
  static const login = '/auth/login';
  static const logout = '/auth/logout';
  static const me = '/auth/me';
  static const changePassword = '/auth/change-password';

  // Dashboard (§10)
  static const dashboardSummary = '/dashboard/summary';
  static const dashboardTopCustomers = '/dashboard/top-customers';
  static const dashboardSalesSummary = '/dashboard/sales-summary';
  static const dashboardExpenseSummary = '/dashboard/expense-summary';
  static const dashboardProductionStatus = '/dashboard/production-status';
  static const dashboardStockMovementSummary =
      '/dashboard/stock-movement-summary';
  static const dashboardKpi = '/dashboard/kpi';
  static const dashboardKpiBatch = '/dashboard/kpi-batch';
  static const dashboardArSummary = '/dashboard/ar-summary';
  static const dashboardCashPosition = '/dashboard/cash-position';
  static const dashboardCashOpeningBalances = '/dashboard/cash-opening-balances';

  // Layout persistence (§10)
  static const dashboardLayouts = '/dashboard/layouts';
  static const dashboardLayoutActive = '/dashboard/layout/active';
  static const dashboardLayout = '/dashboard/layout';

  // Inventory
  static const items = '/inventory/items';
  static const itemsCategories = '/inventory/items-categories';
  static const itemsLowStock = '/inventory/items-low-stock';
  static const itemsUom = '/inventory/items-uom';
  static const warehouses = '/inventory/warehouses';
  static const stockMovements = '/inventory/stock-movements';
  static const stockTransfers = '/inventory/stock-transfers';
  static const stockSummary = '/inventory/stock-summary';
  static const stockLedger = '/inventory/stock-ledger';
  static const stockBalances = '/inventory/stock-balances';
  static const physicalCounts = '/inventory/physical-counts';
  static const physicalCountComplete = '/inventory/physical-counts';
  static const physicalCountItems = '/inventory/physical-counts';
  static const stockBatches = '/inventory/stock-batches';

  // Sales
  static const invoices = '/invoices';
  static const sales = '/sales';
  static const quotations = '/quotations';
  static const salesOrders = '/sales-orders';
  static const pos = '/pos';

  // Purchasing
  static const purchases = '/purchases';
  static const suppliers = '/suppliers';
  static const purchaseOrders = '/purchase-orders';
  static const purchaseReturns = '/purchase-returns';

  // Reports (§11) — first batch; add each endpoint as its report screen
  // is ported. Declared-but-unrouted report endpoints were removed
  // (report-query-integrity): a client constant must resolve server-side.
  static const reportsBase = '/reports';
  static const reportArAging = '/reports/ar-aging';
  static const reportDso = '/reports/dso';
  static const reportCashFlow = '/reports/cash-flow';
  static const reportProfitLoss = '/reports/profit-loss';
  static const reportTopDebtors = '/reports/top-debtors';
  static const reportCustomerStatements = '/reports/customer-statements';
  static const reportArSummary = '/reports/ar-summary';
  static const reportCashReconciliation = '/reports/cash-reconciliation';
  static const reportApAging = '/reports/ap-aging';
  static const reportBalanceSheet = '/reports/balance-sheet';
  static const reportTrialBalance = '/reports/trial-balance';
  static const reportExpiry = '/reports/expiry';
  static const dashboardExpiryAlerts = '/dashboard/expiry-alerts';
  static const dashboardActiveLoans = '/dashboard/active-loans';
  static const reportGeneralLedger = '/reports/general-ledger';
  static const reportIncomeStatement = '/reports/income-statement';
  static const reportTaxSummary = '/reports/tax-summary';
  static const reportBatchTraceability = '/reports/batch-traceability';

  // Misc
  static const customers = '/customers';
  static const payments = '/payments';
  static const expenses = '/expenses';
  static const expensesCategories = '/expenses/categories';
  static const expensesStatusOptions = '/expenses/status-options';
  static const expensesPaymentMethodOptions =
      '/expenses/payment-method-options';
  static const expensesSummary = '/expenses/summary';
  static const ownerEquityCapital = '/owner-equity/capital';
  static const ownerEquityWithdrawals = '/owner-equity/withdrawals';
  static const ownerEquityWithdrawalsQuote =
      '/owner-equity/withdrawals/quote';
  static const ownerEquitySummary = '/owner-equity/summary';  static const ownerEquityPaymentMethodOptions = '/owner-equity/payment-method-options';
  // Owner personal loans (purely record-keeping, no GL impact)
  static const ownerPersonalLoans = '/owner-equity/personal-loans';
  static const ownerPersonalLoansSummary = '/owner-equity/personal-loans/summary';
  static const ownerBorrowers = '/owner-equity/borrowers';
  static const employees = '/employees';
  // Production (§Production) — note the BOM mount is `/api/boms`
  // (`app.use('/api/boms', bomRoutes)`) while productions live flat on
  // `/api/productions` (`app.use('/api', productionRoutes)`).
  static const boms = '/boms';
  static const productions = '/productions';
  static const settings = '/settings';
  static const preferences = '/preferences';
  static const activityLog = '/activity-logs';
  static const forecasts = '/forecasts';
  static const integrations = '/integrations';
  static const users = '/users';
  static const roles = '/roles';
  static const customReports = '/custom-reports';
  // Admin database backups (`server/src/routes/adminBackup.ts`).
  static const adminBackup = '/admin/backup';

  // Global search (command palette)
  static const search = '/search';
}
