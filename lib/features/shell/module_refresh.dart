// Refresh-on-visit — one invalidation action per shell module.
//
// The shell is a `StatefulShellRoute.indexedStack` (PORTING.md §5), so
// every branch stays alive and its FutureProviders keep their cached
// results: a screen revisited after work done on other modules shows
// data from its first visit. The dashboard historically worked around
// this by invalidating its providers in `AppShell.onSelect`; this map
// generalizes that to every module, keyed by the rail destination's
// path. Clicking a rail item therefore behaves like the screen's own
// toolbar-refresh button — the watched providers refetch immediately,
// and unwatched ones (dialogs' picker options) are marked stale so the
// next dialog opens fresh.
//
// Adding a module? Extend the map with its list providers (the ones its
// screens/dialogs watch). autoDispose providers are omitted on purpose —
// they own their fetch per instance and refetch on every open anyway.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../activity_log/activity_log_providers.dart'
    show
        activityActionsProvider,
        activityEntityTypesProvider,
        activityLogsProvider,
        activityStatsProvider,
        activityUsersProvider;
import '../admin/admin_providers.dart' show rolesProvider, usersProvider;
import '../customers/customer_providers.dart' show customersProvider;
import '../dashboard/dashboard_providers.dart'
    show
        dashboardArSummaryProvider,
        dashboardCashOpeningBalancesProvider,
        dashboardCashPositionProvider,
        dashboardSummaryProvider,
        dashboardTopCustomersProvider,
        invalidateDashboardKpiCards;
import '../employees/employee_providers.dart' show employeesProvider;
import '../employees/loan_providers.dart' show dashboardActiveLoansProvider2;
import '../expenses/expense_providers.dart'
    show
        expenseCategoriesProvider,
        expensePaymentMethodsProvider,
        expensesProvider,
        expenseStatusOptionsProvider;
import '../forecasts/forecast_providers.dart'
    show
        filteredForecastDemandProvider,
        forecastAccuracyProvider,
        forecastDashboardProvider,
        forecastDemandProvider,
        forecastTrendsProvider;
import '../integrations/integrations_providers.dart'
    show integrationsStatusProvider;
import '../inventory/inventory_providers.dart'
    show
        allItemsProvider,
        itemsProvider,
        physicalCountsProvider,
        stockBalancesProvider,
        stockMovementsProvider,
        warehousesProvider;
import '../payments/payments_providers.dart'
    show paymentCustomerOptionsProvider, paymentsProvider;
import '../production/production_providers.dart'
    show
        bomsProvider,
        filteredBomsProvider,
        filteredProductionsProvider,
        productionAllItemsProvider,
        productionBomOptionsProvider,
        productionOutputItemsProvider,
        productionWarehousesProvider,
        productionsProvider;
import '../purchase_orders/purchase_order_providers.dart'
    show poItemsProvider, poSupplierOptionsProvider, purchaseOrdersProvider;
import '../purchases/purchase_providers.dart' show purchasesProvider;
import '../purchases/purchase_return_providers.dart'
    show filteredPurchaseReturnsProvider, purchaseReturnsProvider;
import '../quotations/quotation_providers.dart'
    show filteredQuotationsProvider, quotationsProvider;
import '../reports/report_providers.dart'
    show
        apAgingProvider,
        arAgingProvider,
        arSummaryProvider,
        balanceSheetProvider,
        batchTraceabilityProvider,
        cashFlowReportProvider,
        cashReconciliationProvider,
        customerStatementsReportProvider,
        customersForReportProvider,
        dsoReportProvider,
        generalLedgerProvider,
        incomeStatementProvider,
        profitLossReportProvider,
        taxSummaryProvider,
        topDebtorsReportProvider,
        trialBalanceProvider;
import '../sales/invoice_providers.dart'
    show
        filteredInvoicesProvider,
        invoiceCustomersProvider,
        invoiceItemsProvider,
        invoicesProvider;
import '../sales/invoice_return_providers.dart'
    show
        filteredInvoiceReturnsProvider,
        invoiceReturnPickerProvider,
        invoiceReturnsProvider;
import '../sales_orders/sales_order_providers.dart'
    show
        filteredSalesOrdersProvider,
        salesOrderCustomerOptionsProvider,
        salesOrdersProvider,
        soItemsProvider;
import '../owner_equity/owner_equity_providers.dart'
    show
        allOwnerCapitalProvider,
        allOwnerWithdrawalsProvider,
        equitySummaryProvider,
        ownerCapitalProvider,
        ownerWithdrawalsProvider;
import '../settings/settings_providers.dart' show settingsProvider;
import '../suppliers/supplier_providers.dart' show suppliersProvider;

/// Invalidates the providers a module's screens/dialogs watch, so the
/// data refetches on the next watch.
typedef ModuleRefresh = void Function(WidgetRef ref);

/// Rail destination path → refresh action. Invoked on every rail click
/// (re-clicking the current module refreshes it too), mirroring the
/// screen toolbar's refresh button.
final Map<String, ModuleRefresh> moduleRefreshOnVisit = {
  '/': (ref) {
    // KPI strip cards fetch per-card values and need their own
    // invalidation (a new sale / invoice stays stale otherwise).
    invalidateDashboardKpiCards(ref);
    ref
      ..invalidate(dashboardSummaryProvider)
      ..invalidate(dashboardArSummaryProvider)
      ..invalidate(dashboardCashPositionProvider)
      ..invalidate(dashboardCashOpeningBalancesProvider)
      ..invalidate(dashboardTopCustomersProvider)
      ..invalidate(dashboardActiveLoansProvider2);
  },
  '/inventory': (ref) => ref
    ..invalidate(itemsProvider)
    ..invalidate(allItemsProvider)
    ..invalidate(warehousesProvider)
    ..invalidate(stockMovementsProvider)
    ..invalidate(stockBalancesProvider)
    ..invalidate(physicalCountsProvider),
  '/customers': (ref) => ref.invalidate(customersProvider),
  '/sales': (ref) => ref
    ..invalidate(invoicesProvider)
    ..invalidate(filteredInvoicesProvider)
    ..invalidate(invoiceCustomersProvider)
    ..invalidate(invoiceItemsProvider)
    ..invalidate(salesOrdersProvider)
    ..invalidate(filteredSalesOrdersProvider)
    ..invalidate(salesOrderCustomerOptionsProvider)
    ..invalidate(soItemsProvider)
    ..invalidate(quotationsProvider)
    ..invalidate(filteredQuotationsProvider)
    ..invalidate(invoiceReturnsProvider)
    ..invalidate(filteredInvoiceReturnsProvider)
    ..invalidate(invoiceReturnPickerProvider),
  '/purchasing': (ref) => ref
    ..invalidate(purchaseOrdersProvider)
    ..invalidate(poSupplierOptionsProvider)
    ..invalidate(poItemsProvider)
    ..invalidate(purchasesProvider)
    ..invalidate(purchaseReturnsProvider)
    ..invalidate(filteredPurchaseReturnsProvider),
  '/owners-equity': (ref) => ref
    ..invalidate(ownerCapitalProvider)
    ..invalidate(allOwnerCapitalProvider)
    ..invalidate(ownerWithdrawalsProvider)
    ..invalidate(allOwnerWithdrawalsProvider)
    ..invalidate(equitySummaryProvider),
  '/suppliers': (ref) => ref.invalidate(suppliersProvider),
  '/production': (ref) => ref
    ..invalidate(productionsProvider)
    ..invalidate(filteredProductionsProvider)
    ..invalidate(bomsProvider)
    ..invalidate(filteredBomsProvider)
    ..invalidate(productionBomOptionsProvider)
    ..invalidate(productionOutputItemsProvider)
    ..invalidate(productionAllItemsProvider)
    ..invalidate(productionWarehousesProvider),
  '/payments': (ref) => ref
    ..invalidate(paymentsProvider)
    ..invalidate(paymentCustomerOptionsProvider),
  '/expenses': (ref) => ref
    ..invalidate(expensesProvider)
    ..invalidate(expenseCategoriesProvider)
    ..invalidate(expenseStatusOptionsProvider)
    ..invalidate(expensePaymentMethodsProvider),
  '/hr': (ref) => ref.invalidate(employeesProvider),
  // Report screens are sub-routes under the hub; none of these providers
  // is watched by the hub itself, so this costs nothing at click time —
  // it only marks them stale so the next report opened is fresh.
  '/reports': (ref) => ref
    ..invalidate(arSummaryProvider)
    ..invalidate(arAgingProvider)
    ..invalidate(apAgingProvider)
    ..invalidate(dsoReportProvider)
    ..invalidate(cashFlowReportProvider)
    ..invalidate(cashReconciliationProvider)
    ..invalidate(profitLossReportProvider)
    ..invalidate(balanceSheetProvider)
    ..invalidate(trialBalanceProvider)
    ..invalidate(generalLedgerProvider)
    ..invalidate(incomeStatementProvider)
    ..invalidate(taxSummaryProvider)
    ..invalidate(batchTraceabilityProvider)
    ..invalidate(topDebtorsReportProvider)
    ..invalidate(customerStatementsReportProvider)
    ..invalidate(customersForReportProvider),
  '/forecasts': (ref) => ref
    ..invalidate(forecastDashboardProvider)
    ..invalidate(forecastDemandProvider)
    ..invalidate(filteredForecastDemandProvider)
    ..invalidate(forecastTrendsProvider)
    ..invalidate(forecastAccuracyProvider),
  '/activity-log': (ref) => ref
    ..invalidate(activityLogsProvider)
    ..invalidate(activityStatsProvider)
    ..invalidate(activityEntityTypesProvider)
    ..invalidate(activityActionsProvider)
    ..invalidate(activityUsersProvider),
  '/admin': (ref) => ref
    ..invalidate(usersProvider)
    ..invalidate(rolesProvider),
  '/integrations': (ref) => ref.invalidate(integrationsStatusProvider),
  '/settings': (ref) => ref.invalidate(settingsProvider),
};

/// Inner-tab refresh — module path → one invalidation action per tab,
/// aligned with the module shell's `NavigationBar` destination order
/// (inventory: items, warehouses, movements, balances, counts; sales:
/// invoices, orders, quotations, returns; …). Invoked when a tab is
/// clicked so that tab's data refetches: the shells host their tabs in
/// an `IndexedStack`, so without this a tab shows data cached at its
/// first build even though the module itself was refreshed on arrival.
final Map<String, List<ModuleRefresh>> moduleTabRefreshOnVisit = {
  '/inventory': [
    (ref) => ref
      ..invalidate(itemsProvider)
      ..invalidate(allItemsProvider),
    (ref) => ref.invalidate(warehousesProvider),
    (ref) => ref.invalidate(stockMovementsProvider),
    (ref) => ref.invalidate(stockBalancesProvider),
    (ref) => ref.invalidate(physicalCountsProvider),
  ],
  '/sales': [
    (ref) => ref
      ..invalidate(invoicesProvider)
      ..invalidate(filteredInvoicesProvider)
      ..invalidate(invoiceCustomersProvider)
      ..invalidate(invoiceItemsProvider),
    (ref) => ref
      ..invalidate(salesOrdersProvider)
      ..invalidate(filteredSalesOrdersProvider)
      ..invalidate(salesOrderCustomerOptionsProvider)
      ..invalidate(soItemsProvider),
    (ref) => ref
      ..invalidate(quotationsProvider)
      ..invalidate(filteredQuotationsProvider),
    (ref) => ref
      ..invalidate(invoiceReturnsProvider)
      ..invalidate(filteredInvoiceReturnsProvider)
      ..invalidate(invoiceReturnPickerProvider),
  ],
  '/owners-equity': [
    (ref) => ref
      ..invalidate(ownerCapitalProvider)
      ..invalidate(allOwnerCapitalProvider)
      ..invalidate(equitySummaryProvider),
    (ref) => ref
      ..invalidate(ownerWithdrawalsProvider)
      ..invalidate(allOwnerWithdrawalsProvider)
      ..invalidate(equitySummaryProvider),
  ],
  '/purchasing': [
    (ref) => ref
      ..invalidate(purchaseOrdersProvider)
      ..invalidate(poSupplierOptionsProvider)
      ..invalidate(poItemsProvider),
    (ref) => ref.invalidate(purchasesProvider),
    (ref) => ref
      ..invalidate(purchaseReturnsProvider)
      ..invalidate(filteredPurchaseReturnsProvider),
  ],
  '/production': [
    (ref) => ref
      ..invalidate(productionsProvider)
      ..invalidate(filteredProductionsProvider)
      ..invalidate(productionBomOptionsProvider)
      ..invalidate(productionOutputItemsProvider)
      ..invalidate(productionWarehousesProvider),
    (ref) => ref
      ..invalidate(bomsProvider)
      ..invalidate(filteredBomsProvider)
      ..invalidate(productionAllItemsProvider),
  ],
  '/forecasts': [
    (ref) => ref.invalidate(forecastDashboardProvider),
    (ref) => ref
      ..invalidate(forecastDemandProvider)
      ..invalidate(filteredForecastDemandProvider),
    (ref) => ref.invalidate(forecastTrendsProvider),
    (ref) => ref.invalidate(forecastAccuracyProvider),
  ],
  '/admin': [
    (ref) => ref.invalidate(usersProvider),
    (ref) => ref.invalidate(rolesProvider),
  ],
};
