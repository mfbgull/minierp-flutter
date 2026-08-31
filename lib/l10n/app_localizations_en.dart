// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get dashboardWelcome => 'Welcome back';

  @override
  String get dashboardTotalitems => 'Total Items';

  @override
  String get dashboardWarehousestocks => 'W.H Stock';

  @override
  String get dashboardAr => 'AR';

  @override
  String get dashboardArHint => 'Total receivables outstanding from customers';

  @override
  String get dashboardStockvalue => 'Stock Value';

  @override
  String get dashboardCurrentinventoryworth => 'Current inventory worth';

  @override
  String get dashboardSalesrevenue => 'Sales Revenue';

  @override
  String get dashboardTotalsales => 'Total sales';

  @override
  String get dashboardRunslast30days => 'Runs in last 30 days';

  @override
  String get dashboardSalesvspurchases => 'Sales vs Purchases (Last 7 Days)';

  @override
  String get dashboardStockbycategory => 'Stock by Category';

  @override
  String get dashboardLowstockalerts => 'Low Stock Alerts';

  @override
  String get dashboardWellstocked => 'All items are well stocked!';

  @override
  String get dashboardQuickactions => 'Quick Actions';

  @override
  String get dashboardNewitem => 'New Item';

  @override
  String get dashboardRecordsale => 'Record Sale';

  @override
  String get dashboardNewpurchase => 'New Purchase';

  @override
  String get dashboardStockmovement => 'Stock Movement';

  @override
  String get dashboardLivingecosystem => 'Living Ecosystem';

  @override
  String get dashboardcardTotalitems => 'Total Items';

  @override
  String get dashboardcardStockvalue => 'Stock Value';

  @override
  String get dashboardcardSalesrevenue => 'Sales Revenue';

  @override
  String get dashboardcardGrossprofit => 'Gross Profit';

  @override
  String get dashboardcardPurchases => 'PO\'s';

  @override
  String get dashboardcardWarehousestock => 'W.H Stock';

  @override
  String get dashboardcardAr => 'AR';

  @override
  String get dashboardcardInventoryturnover => 'Inventory Turnover';

  @override
  String get dashboardcardAvgtodayspay => 'Avg. Days to Pay';

  @override
  String get dashboardcardStockhealth => 'Stock Health';

  @override
  String get dashboardcardMonthlyrevenue => 'Monthly Revenue';

  @override
  String get dashboardcardNetprofit => 'Net Profit';

  @override
  String get dashboardcardExpenses => 'Expenses';

  @override
  String get dashboardcardPayables => 'Payables';

  @override
  String get dashboardcardCustomers => 'Customers';

  @override
  String get dashboardcardLowstockcount => 'Low Stock';

  @override
  String get dashboardcardPanelSalespurchases => 'Sales vs Purchases';

  @override
  String get dashboardcardPanelArAging => 'AR Aging';

  @override
  String get dashboardcardPanelStockbycategory => 'Stock by Category';

  @override
  String get dashboardcardPanelTopcustomers => 'Top Customers';

  @override
  String get dashboardcardPanelLowstock => 'Low Stock';

  @override
  String get dashboardcardPanelExpiryalerts => 'Expiring Soon';

  @override
  String get dashboardcardPanelActiveloans => 'Active Loans';

  @override
  String get dashboardcardOutstandingloans => 'Outstanding Loans';

  @override
  String get dashboardOutstandingloansHint =>
      'Total loan balance outstanding across all employees';

  @override
  String get dashboardActiveLoansCount => 'active';

  @override
  String get dashboardOverdueCount => 'overdue';

  @override
  String dashboardDaysUntilDue(Object days) {
    return 'Due in $days days';
  }

  @override
  String dashboardDaysOverdue(Object days) {
    return '$days days overdue';
  }

  @override
  String get loanAgingCurrent => 'Current';

  @override
  String get loanAgingDueSoon => 'Due Soon';

  @override
  String get loanAgingDueToday => 'Due Today';

  @override
  String get loanAgingOverdue1_30 => 'Overdue 1-30';

  @override
  String get loanAgingOverdue30Plus => 'Overdue 30+';

  @override
  String get dashboardcardCashstrip => 'Cash & Bank Position';

  @override
  String get dashboardcardsEmpty => 'No cards shown — customize to add';

  @override
  String get dashboardcardsSearch => 'Search cards…';

  @override
  String get dashboardcardsSelectall => 'Select All';

  @override
  String get dashboardcardsClearall => 'Clear All';

  @override
  String get dashboardcardsKpis => 'KPI Cards';

  @override
  String get dashboardcardsPanels => 'Panels';

  @override
  String get dashboardcardsCashbank => 'Cash & Bank';

  @override
  String get dashboardcustomizationCustomize => 'Customize';

  @override
  String get dashboardcustomizationDone => 'Done';

  @override
  String get dashboardcustomizationSave => 'Save Layout';

  @override
  String get dashboardcustomizationSaving => 'Saving...';

  @override
  String get dashboardcustomizationSaved => 'Saved';

  @override
  String get dashboardcustomizationUnsaved => 'Unsaved changes';

  @override
  String get dashboardcustomizationSavefailed => 'Save failed';

  @override
  String get dashboardcustomizationSaveretrying => 'Retrying...';

  @override
  String get dashboardcustomizationRevert => 'Revert to Default';

  @override
  String get dashboardcustomizationRevertconfirmtitle =>
      'Reset Dashboard Layout?';

  @override
  String get dashboardcustomizationRevertconfirmmsg =>
      'This will remove all your custom blocks and reset the dashboard to its default layout. This cannot be undone.';

  @override
  String get dashboardcustomizationReverted => 'Layout reverted to default';

  @override
  String get dashboardcustomizationBlockpalette => 'Block Palette';

  @override
  String get dashboardcustomizationAddblock => 'Add to Dashboard';

  @override
  String get dashboardcustomizationRemoveblock => 'Remove';

  @override
  String get dashboardcustomizationBlocksettings => 'Block Settings';

  @override
  String get dashboardcustomizationTitle => 'Block Title';

  @override
  String get dashboardcustomizationSize => 'Size';

  @override
  String get dashboardcustomizationSmall => 'Small';

  @override
  String get dashboardcustomizationMedium => 'Medium';

  @override
  String get dashboardcustomizationLarge => 'Large';

  @override
  String get dashboardcustomizationRefreshinterval => 'Refresh Interval';

  @override
  String get dashboardcustomizationNorefresh => 'None';

  @override
  String get dashboardcustomizationRefresh30s => 'Every 30s';

  @override
  String get dashboardcustomizationRefresh60s => 'Every 60s';

  @override
  String get dashboardcustomizationRefresh5m => 'Every 5 min';

  @override
  String get dashboardcustomizationRefresh15m => 'Every 15 min';

  @override
  String get dashboardcustomizationDeleteblock => 'Delete Block';

  @override
  String dashboardcustomizationDeleteconfirm(Object title) {
    return 'Delete \"$title\"?';
  }

  @override
  String get dashboardcustomizationDeleteconfirmmsg =>
      'This block will be removed from your dashboard.';

  @override
  String get dashboardcustomizationLayoutsaved => 'Layout saved';

  @override
  String get dashboardcustomizationBlockadded => 'Block added to dashboard';

  @override
  String get dashboardcustomizationBlockremoved => 'Block removed';

  @override
  String get dashboardcustomizationDraghint => 'Drag blocks to rearrange';

  @override
  String get dashboardcustomizationUndo => 'Undo';

  @override
  String get dashboardcustomizationRedo => 'Redo';

  @override
  String get dashboardcustomizationMobilepalettetitle => 'Add a Block';

  @override
  String get dashboardcustomizationMobilepalettedesc =>
      'Select a block type to add to your dashboard';

  @override
  String get dashboardcustomizationDeprecatedblock =>
      'This block type is no longer available';

  @override
  String get dashboardcustomizationDeprecatedremove => 'Remove';

  @override
  String get dashboardcustomizationEditshortcuts =>
      'Escape to exit, Delete to remove, Ctrl+Z to undo';

  @override
  String get dashboardcustomizationSyncedfromothertab =>
      'Dashboard updated from another tab';

  @override
  String get dashboardcustomizationBlockstatcards => 'Stat Cards';

  @override
  String get dashboardcustomizationBlocksalespurchases => 'Sales vs Purchases';

  @override
  String get dashboardcustomizationBlockstockbycategory => 'Stock by Category';

  @override
  String get dashboardcustomizationBlocklowstock => 'Low Stock Alerts';

  @override
  String get dashboardcustomizationBlockquickactions => 'Quick Actions';

  @override
  String get dashboardcustomizationBlockrecentactivity => 'Recent Activity';

  @override
  String get dashboardcustomizationBlockarsummary => 'AR Summary';

  @override
  String get dashboardcustomizationBlocktopcustomers => 'Top Customers';

  @override
  String get dashboardcustomizationBlockforecastsnapshot => 'Forecast Snapshot';

  @override
  String get dashboardcustomizationBlocksalessummary => 'Sales Summary';

  @override
  String get dashboardcustomizationBlockexpensesummary => 'Expense Summary';

  @override
  String get dashboardcustomizationBlockproductionstatus => 'Production Status';

  @override
  String get dashboardcustomizationBlockstockmovements =>
      'Stock Movement Summary';

  @override
  String get dashboardcustomizationBlockcustomtext => 'Text / Heading';

  @override
  String get dashboardcustomizationBlockkpigauge => 'KPI Gauge';

  @override
  String get dashboardcustomizationBlockstatcardsdesc =>
      'Total Items, Stock Value, Sales, Production';

  @override
  String get dashboardcustomizationBlocksalespurchasesdesc =>
      '7-day sales vs purchases line chart';

  @override
  String get dashboardcustomizationBlockstockbycategorydesc =>
      'Stock distribution by category';

  @override
  String get dashboardcustomizationBlocklowstockdesc =>
      'Items below reorder level';

  @override
  String get dashboardcustomizationBlockquickactionsdesc =>
      'Shortcuts to common pages';

  @override
  String get dashboardcustomizationBlockrecentactivitydesc =>
      'Latest system activity';

  @override
  String get dashboardcustomizationBlockarsummarydesc =>
      'Accounts receivable aging';

  @override
  String get dashboardcustomizationBlocktopcustomersdesc =>
      'Top customers by revenue';

  @override
  String get dashboardcustomizationBlockforecastsnapshotdesc =>
      'Forecast KPIs and metrics';

  @override
  String get dashboardcustomizationBlocksalessummarydesc =>
      'Today / Week / Month sales totals';

  @override
  String get dashboardcustomizationBlockexpensesummarydesc =>
      'Recent expenses and totals';

  @override
  String get dashboardcustomizationBlockproductionstatusdesc =>
      'Active production orders';

  @override
  String get dashboardcustomizationBlockstockmovementsdesc =>
      'Recent stock in/out movements';

  @override
  String get dashboardcustomizationBlockcustomtextdesc =>
      'Custom heading or notes';

  @override
  String get dashboardcustomizationBlockkpigaugedesc =>
      'Single configurable KPI gauge';

  @override
  String get customersCustomers => 'Customers';

  @override
  String get customersNewcustomer => 'New Customer';

  @override
  String get customersCustomername => 'Customer Name';

  @override
  String get customersPhone => 'Phone';

  @override
  String get customersEmail => 'Email';

  @override
  String get customersAddress => 'Address';

  @override
  String get customersActions => 'Actions';

  @override
  String get customersSave => 'Save';

  @override
  String get customersDelete => 'Delete';

  @override
  String get customersConfirmdelete => 'Are you sure you want to delete';

  @override
  String get customersCustomerdeleted => 'Customer deleted successfully!';

  @override
  String get suppliersSuppliers => 'Suppliers';

  @override
  String get suppliersNewsupplier => 'New Supplier';

  @override
  String get suppliersSuppliername => 'Supplier Name';

  @override
  String get suppliersPhone => 'Phone';

  @override
  String get suppliersEmail => 'Email';

  @override
  String get suppliersAddress => 'Address';

  @override
  String get suppliersActions => 'Actions';

  @override
  String get reportsReports => 'Reports';

  @override
  String get reportsReportsdashboard => 'Reports Dashboard';

  @override
  String get reportsProfitlossreport => 'Profit & Loss Report';

  @override
  String get reportsCashflowreport => 'Cash Flow Report';

  @override
  String get reportsTopdebtorsreport => 'Top Debtors Report';

  @override
  String get reportsCustomerstatementsreport => 'Customer Statements Report';

  @override
  String get reportsDsoreport => 'Days Sales Outstanding (DSO) Report';

  @override
  String get reportsAr_reports => 'Accounts Receivable Reports';

  @override
  String get reportsTabsAr_aging => 'AR Aging';

  @override
  String get reportsTabsReceivables_summary => 'Receivables Summary';

  @override
  String get reportsTabsTop_debtors => 'Top Debtors';

  @override
  String get reportsTabsDso => 'Days Sales Outstanding';

  @override
  String get reportsAccountsreceivablereports => 'Accounts Receivable Reports';

  @override
  String get quotationsQuotations => 'Quotations';

  @override
  String get quotationsNewquotation => 'New Quotation';

  @override
  String get quotationsQuotation => 'Quotation #';

  @override
  String get quotationsCustomer => 'Customer';

  @override
  String get quotationsAmount => 'Amount';

  @override
  String get quotationsDate => 'Date';

  @override
  String get quotationsExpiry => 'Expiry';

  @override
  String get quotationsStatus => 'Status';

  @override
  String get quotationsActions => 'Actions';

  @override
  String get quotationsDraft => 'Draft';

  @override
  String get quotationsSent => 'Sent';

  @override
  String get quotationsConverted => 'Converted';

  @override
  String get quotationsAccepted => 'Accepted';

  @override
  String get quotationsRejected => 'Rejected';

  @override
  String get quotationsExpired => 'Expired';

  @override
  String get quotationsViewdetails => 'View Details';

  @override
  String get quotationsEdit => 'Edit';

  @override
  String get quotationsConverttoso => 'Convert to SO';

  @override
  String get quotationsDelete => 'Delete';

  @override
  String get quotationsConfirmdelete =>
      'Are you sure you want to delete this quotation?';

  @override
  String get quotationsDeleted => 'Quotation deleted successfully';

  @override
  String get quotationsFailed => 'Failed to delete quotation';

  @override
  String get quotationsNoquotations => 'No quotations found';

  @override
  String get purchaseordersPurchaseorders => 'Purchase Orders';

  @override
  String get purchaseordersNewpurchaseorder => 'New Purchase Order';

  @override
  String get salesordersSalesorders => 'Sales Orders';

  @override
  String get salesordersNewsalesorder => 'New Sales Order';

  @override
  String get salesordersSono => 'SO #';

  @override
  String get salesordersCustomer => 'Customer';

  @override
  String get salesordersAmount => 'Amount';

  @override
  String get salesordersDate => 'Date';

  @override
  String get salesordersDelivery => 'Delivery';

  @override
  String get salesordersStatus => 'Status';

  @override
  String get salesordersActions => 'Actions';

  @override
  String get salesordersDraft => 'Draft';

  @override
  String get salesordersConfirmed => 'Confirmed';

  @override
  String get salesordersInvoiced => 'Invoiced';

  @override
  String get salesordersCompleted => 'Completed';

  @override
  String get salesordersCancelled => 'Cancelled';

  @override
  String get salesordersViewdetails => 'View Details';

  @override
  String get salesordersEdit => 'Edit';

  @override
  String get salesordersConverttoinvoice => 'Convert to Invoice';

  @override
  String get salesordersDelete => 'Delete';

  @override
  String get salesordersConfirmdelete =>
      'Are you sure you want to delete this sales order?';

  @override
  String get salesordersDeleted => 'Sales order deleted successfully';

  @override
  String get salesordersFailed => 'Failed to delete sales order';

  @override
  String get productionProduction => 'Production';

  @override
  String get productionProductions => 'Productions';

  @override
  String get productionNewproduction => 'New Production';

  @override
  String get warehousesWarehouses => 'Warehouses';

  @override
  String get warehousesNewwarehouse => 'New Warehouse';

  @override
  String get stockmovementsStockmovements => 'Stock Movements';

  @override
  String get inventoryItems => 'Items';

  @override
  String get stockbywarehouseBalances => 'Stock Balances';

  @override
  String get physicalcountsPhysicalcounts => 'Physical Counts';

  @override
  String get stockmovementsNewmovement => 'New Movement';

  @override
  String get stockmovementsTotalmovements => 'Total Movements';

  @override
  String get stockmovementsTotalquantity => 'Total Quantity';

  @override
  String get stockmovementsMostactivetype => 'Most Active Type';

  @override
  String get stockmovementsProduction => 'Production';

  @override
  String get stockmovementsTransfers => 'Transfers';

  @override
  String get stockmovementsAdjustments => 'Adjustments';

  @override
  String get stockmovementsStockadditions => 'Stock additions';

  @override
  String get stockmovementsStockreductions => 'Stock reductions';

  @override
  String get stockmovementsAggregatemoved => 'Aggregate moved';

  @override
  String get stockmovementsNomovements => 'No movements';

  @override
  String get stockmovementsCount => 'Count';

  @override
  String get stockmovementsStockin => 'Stock in';

  @override
  String get stockmovementsStockout => 'Stock out';

  @override
  String get stockmovementsCreated => 'Created';

  @override
  String get stockmovementsMovedbetween => 'Moved between warehouses';

  @override
  String get stockmovementsManualchanges => 'Manual changes';

  @override
  String get stockmovementsExportcsv => 'Export to CSV';

  @override
  String get stockmovementsMovementreport => 'Movement Report';

  @override
  String get stockmovementsStockvaluation => 'Stock Valuation';

  @override
  String get stockmovementsStockbywarehouse => 'Stock by Warehouse';

  @override
  String get stockmovementsTracktransactions => 'Track all stock transactions';

  @override
  String get stockmovementsNewadjustment => 'New Adjustment';

  @override
  String get stockmovementsAlltransactions => 'All transactions';

  @override
  String get stockmovementsSearchplaceholder => 'Search movements...';

  @override
  String get stockbywarehouseViewbywarehouse =>
      'View current stock levels for each item by warehouse';

  @override
  String get stockbywarehouseTotalitems => 'Total Items';

  @override
  String get stockbywarehouseItemswithstock => 'Items with stock';

  @override
  String get stockbywarehouseAggregateqty => 'Aggregate quantity';

  @override
  String get stockbywarehouseActivelocations => 'Active locations';

  @override
  String get stockbywarehouseLargeststock => 'Largest Stock';

  @override
  String get stockbywarehouseMultiwarehouseitems => 'Multi-Warehouse Items';

  @override
  String get stockbywarehouseMultiplelocations => 'In multiple locations';

  @override
  String get stockbywarehouseAverageqty => 'Average Qty';

  @override
  String get stockbywarehousePerstockline => 'Per stock line';

  @override
  String get stockbywarehouseExportcsv => 'Export to CSV';

  @override
  String get stockbywarehouseAllwarehouses => 'All Warehouses';

  @override
  String get stockbywarehouseQuantity => 'Quantity';

  @override
  String get stockbywarehouseAll => 'All';

  @override
  String get stockbywarehouseStock => 'Stock';

  @override
  String get stockbywarehouseZero => 'Zero';

  @override
  String get forecastsForecasts => 'Forecasts';

  @override
  String get forecastsDashboard => 'Demand Forecast';

  @override
  String get forecastsDemandtitle => 'Demand Forecast';

  @override
  String get forecastsDemand => 'Demand Forecasts';

  @override
  String get forecastsForecasttrends => 'Forecast Trends';

  @override
  String get forecastsTrackeditems => 'Tracked Items';

  @override
  String get forecastsNeedrestock => 'Need Restock';

  @override
  String get forecastsAvgconfidence => 'Avg Confidence';

  @override
  String get forecastsCriticalalerts => 'Critical Alerts';

  @override
  String get forecastsAlerts => 'Alerts';

  @override
  String get forecastsViewall => 'View All';

  @override
  String get forecastsNoalerts => 'No alerts — all items adequately stocked';

  @override
  String get forecastsTopgrowing => 'Top Growing Items';

  @override
  String get forecastsViewtrends => 'View Trends';

  @override
  String get forecastsNotrenddata => 'No trending data available';

  @override
  String get forecastsLoaderror => 'Failed to load forecast data';

  @override
  String get forecastsRetry => 'Retry';

  @override
  String get forecastsRefresh => 'Refresh';

  @override
  String get forecastsRefreshing => 'Refreshing...';

  @override
  String get forecastsCategory => 'Category';

  @override
  String get forecastsTrendlabel => 'Trend';

  @override
  String get forecastsStatus => 'Status';

  @override
  String get forecastsAllcategories => 'All Categories';

  @override
  String get forecastsAlltrends => 'All Trends';

  @override
  String get forecastsAllstatus => 'All Status';

  @override
  String get forecastsNoforecasts => 'No forecast data available';

  @override
  String get forecastsMonthlytrend => 'Monthly Sales & Forecast';

  @override
  String get forecastsActualsales => 'Actual Sales';

  @override
  String get forecastsTrendline => '3-Month Trend';

  @override
  String get forecastsForecast => 'Forecast';

  @override
  String get forecastsTopitemsbyvolume => 'Top Items by Volume';

  @override
  String get forecastsTotalsold => 'Total Sold';

  @override
  String get forecastsTotalsold12mo => 'Total Sold (12mo)';

  @override
  String get forecastsItembreakdown => 'Item Breakdown';

  @override
  String get forecastsSelectitem => 'Select Item (or all)';

  @override
  String get forecastsGrowing => 'Growing';

  @override
  String get forecastsDeclining => 'Declining';

  @override
  String get forecastsStable => 'Stable';

  @override
  String get forecastsAccuracy => 'Forecast Accuracy';

  @override
  String get forecastsAccuracytitle => 'Forecast Accuracy';

  @override
  String get forecastsAvgmape => 'Avg MAPE';

  @override
  String get forecastsAvgmae => 'Avg MAE';

  @override
  String get forecastsItemswithaccuracy => 'Items Tracked';

  @override
  String get forecastsBestmodel => 'Best Model';

  @override
  String get forecastsComputeaccuracy => 'Compute Accuracy';

  @override
  String get forecastsComputing => 'Computing...';

  @override
  String get forecastsAccuracysubtitle =>
      'Compare predicted vs actual demand to evaluate forecast quality';

  @override
  String get forecastsNoaccuracydata =>
      'No accuracy data. Click \'Compute Accuracy\' to backfill past predictions.';

  @override
  String forecastsAccuracycomputed(Object count) {
    return 'Accuracy computed for $count records';
  }

  @override
  String get forecastsMapelabel => 'MAPE';

  @override
  String get forecastsMaelabel => 'MAE';

  @override
  String get forecastsSmapelabel => 'sMAPE';

  @override
  String get forecastsSamples => 'Samples';

  @override
  String get forecastsAccuracytrend => 'Accuracy Trend';

  @override
  String get forecastsAccuracytrenddesc => 'MAPE over time for selected item';

  @override
  String get forecastsSelectitemforchart =>
      'Select an item from the table to see its accuracy trend';

  @override
  String get forecastsAccuracyvsactual => 'Predicted vs Actual';

  @override
  String get forecastsModel => 'Model';

  @override
  String get forecastsSortbymape => 'Best (lowest MAPE) first';

  @override
  String get bomBillofmaterials => 'Bill of Materials (BOM)';

  @override
  String get bomBoms => 'BOMs';

  @override
  String get bomNewbom => 'New BOM';

  @override
  String get settingsSettings => 'Settings';

  @override
  String get integrationsIntegrations => 'Integrations';

  @override
  String get usermanagementUsermanagement => 'User Management';

  @override
  String get usermanagementRolespermissions => 'Roles & Permissions';

  @override
  String get expensesExpenses => 'Expenses';

  @override
  String get expensesNewexpense => 'New Expense';

  @override
  String get expensesDescription => 'Description';

  @override
  String get employeesTitle => 'Employees';

  @override
  String get employeesSubtitle => 'Manage employee records and HR information';

  @override
  String get employeesAddnew => 'Add Employee';

  @override
  String get employeesEditemployee => 'Edit Employee';

  @override
  String get employeesFieldsFirst_name => 'First Name';

  @override
  String get employeesFieldsLast_name => 'Last Name';

  @override
  String get employeesFieldsEmail => 'Email';

  @override
  String get employeesFieldsPhone => 'Phone';

  @override
  String get employeesFieldsMobile => 'Mobile';

  @override
  String get employeesFieldsCnic_no => 'CNIC No';

  @override
  String get employeesFieldsAddress => 'Address';

  @override
  String get employeesFieldsCity => 'City';

  @override
  String get employeesFieldsState => 'State';

  @override
  String get employeesFieldsPostal_code => 'Postal Code';

  @override
  String get employeesFieldsCountry => 'Country';

  @override
  String get employeesFieldsDate_of_birth => 'Date of Birth';

  @override
  String get employeesFieldsGender => 'Gender';

  @override
  String get employeesFieldsDepartment => 'Department';

  @override
  String get employeesFieldsDesignation => 'Designation';

  @override
  String get employeesFieldsEmployment_type => 'Employment Type';

  @override
  String get employeesFieldsDate_of_joining => 'Date of Joining';

  @override
  String get employeesFieldsDate_of_leaving => 'Date of Leaving';

  @override
  String get employeesFieldsSalary => 'Salary';

  @override
  String get employeesFieldsBank_name => 'Bank Name';

  @override
  String get employeesFieldsBank_account_no => 'Bank Account No';

  @override
  String get employeesFieldsBank_iban => 'IBAN';

  @override
  String get employeesFieldsEmergency_contact_name => 'Emergency Contact Name';

  @override
  String get employeesFieldsEmergency_contact_phone =>
      'Emergency Contact Phone';

  @override
  String get employeesFieldsNotes => 'Notes';

  @override
  String get employeesFieldsIs_active => 'Active';

  @override
  String get employeesValidationFirstnamerequired => 'First name is required';

  @override
  String get employeesValidationLastnamerequired => 'Last name is required';

  @override
  String get employeesValidationInvalidemail => 'Invalid email format';

  @override
  String get employeesValidationInvalidphone => 'Invalid phone format';

  @override
  String get employeesMessagesCreated => 'Employee created successfully';

  @override
  String get employeesMessagesUpdated => 'Employee updated successfully';

  @override
  String get employeesMessagesDeleted => 'Employee deleted successfully';

  @override
  String get employeesDocumentsTitle => 'Documents';

  @override
  String get employeesDocumentsAdd => 'Add Document';

  @override
  String get employeesDocumentsName => 'Document Name';

  @override
  String get employeesDocumentsType => 'Document Type';

  @override
  String get employeesDocumentsNumber => 'Document Number';

  @override
  String get employeesDocumentsIssuedate => 'Issue Date';

  @override
  String get employeesDocumentsExpirydate => 'Expiry Date';

  @override
  String get employeesDocumentsNotes => 'Notes';

  @override
  String get employeesDocumentsNodocuments => 'No documents on file';

  @override
  String get employeesDocumentsNamerequired => 'Document name is required';

  @override
  String get employeesDocumentsCreated => 'Document added successfully';

  @override
  String get employeesDocumentsDeleted => 'Document deleted successfully';

  @override
  String get employeesDocumentsFiletoolarge => 'File size must be under 10MB';

  @override
  String get employeesDocumentsDrophere =>
      'Click or drag a file here to upload';

  @override
  String get employeesDocumentsFiletypes =>
      'PDF, Images, Word, Excel, TXT — max 10MB';

  @override
  String get employeesDocumentsUploading => 'Uploading...';

  @override
  String get employeesDocumentsProcessing => 'Processing...';

  @override
  String get employeesDocumentsPreview => 'Preview';

  @override
  String get employeesDocumentsPreviewnotsupported =>
      'Preview not available for this file type';

  @override
  String get employeesDocumentsFile => 'file';

  @override
  String get purchasesPurchases => 'Purchases';

  @override
  String get purchasesPurchaseReturns => 'Purchase Returns';

  @override
  String get purchasesNewpurchase => 'New Purchase';

  @override
  String get purchasesPurchaseno => 'Purchase No';

  @override
  String get purchasesSupplier => 'Supplier';

  @override
  String get purchasesConfirmdelete => 'Are you sure you want to delete';

  @override
  String get purchasesPurchasedeleted => 'Purchase deleted successfully!';

  @override
  String get purchasesPurchasesaved => 'Purchase saved successfully!';

  @override
  String get purchasesNopurchases => 'No purchases to export';

  @override
  String get purchasesTotalvalue => 'Total Value';

  @override
  String get purchasesTotalquantity => 'Total Quantity';

  @override
  String get purchasesUniquesuppliers => 'Unique Suppliers';

  @override
  String get purchasesUniqueitems => 'Unique Items';

  @override
  String get purchasesTotalpurchases => 'Total Purchases';

  @override
  String get purchasesSubtitle => 'Record direct purchases and track costs';

  @override
  String get purchasesRecordpurchase => 'Record Purchase';

  @override
  String get purchasesDocument => 'Document';

  @override
  String get purchasesSupplierrequiredforpayment =>
      'Select a supplier to record a payment';

  @override
  String get purchaseordersSubtitle =>
      'Order stock from suppliers and track the PO\'s payment status';

  @override
  String get purchasesTotalpurchasescard => 'Total Purchases';

  @override
  String get purchasesAlltransactions => 'All transactions';

  @override
  String get purchasesTotalvaluecard => 'Total Value';

  @override
  String get purchasesPurchasecost => 'Purchase cost';

  @override
  String get purchasesTotalquantitycard => 'Total Quantity';

  @override
  String get purchasesAggregateitems => 'Aggregate items';

  @override
  String get purchasesSupplierscard => 'Suppliers';

  @override
  String get purchasesUniquevendors => 'Unique vendors';

  @override
  String get purchasesItemscard => 'Items';

  @override
  String get purchasesProductspurchased => 'Products purchased';

  @override
  String get purchasesAveragevalue => 'Average Value';

  @override
  String get purchasesPerpurchase => 'Per purchase';

  @override
  String get purchasesLargestpurchase => 'Largest Purchase';

  @override
  String get purchasesNopurchasesyet => 'No purchases yet';

  @override
  String get purchasesRecent30days => 'Recent (30 Days)';

  @override
  String get purchasesLastmonth => 'Last month';

  @override
  String get purchasesExport => 'Export';

  @override
  String get purchasesSummary => 'Summary';

  @override
  String get purchasesValuation => 'Valuation';

  @override
  String get purchasesMovements => 'Movements';

  @override
  String get purchasesItemsaction => 'Items';

  @override
  String get purchasesPurchasenumber => 'Purchase #';

  @override
  String get purchasesDatecol => 'Date';

  @override
  String get purchasesItemcol => 'Item';

  @override
  String get purchasesQuantitycol => 'Quantity';

  @override
  String get purchasesUnitcost => 'Unit Cost';

  @override
  String get purchasesTotalcol => 'Total';

  @override
  String get purchasesSuppliercol => 'Supplier';

  @override
  String get purchasesWarehousecol => 'Warehouse';

  @override
  String get purchasesNopurchasesfound => 'No purchases found';

  @override
  String get purchasesLoading => 'Loading...';

  @override
  String get purchasesRecordnewpurchase => 'Record New Purchase';

  @override
  String get purchasesSearchitems => 'Search items...';

  @override
  String get purchasesSearchwarehouses => 'Search warehouses...';

  @override
  String get purchasesTotalcostlabel => 'Total Cost:';

  @override
  String get purchasesPurchasedate => 'Purchase Date';

  @override
  String get purchasesSuppliername => 'Supplier Name';

  @override
  String get purchasesSupplierplaceholder => 'e.g., ABC Suppliers';

  @override
  String get purchasesInvoicenumber => 'Invoice Number';

  @override
  String get purchasesInvoiceplaceholder => 'e.g., INV-2025-001';

  @override
  String get purchasesRemarks => 'Remarks';

  @override
  String get purchasesRemarksplaceholder =>
      'Additional notes about this purchase...';

  @override
  String get purchasesCancel => 'Cancel';

  @override
  String get purchasesReturn => 'Return to Supplier';

  @override
  String get purchasesReturntitle => 'Purchase Return';

  @override
  String get purchasesReturnsubtitle => 'Process a return for this purchase';

  @override
  String get purchasesReturnquantity => 'Return Quantity';

  @override
  String get purchasesReturnreason => 'Reason for Return';

  @override
  String get purchasesReturnreasonplaceholder => 'Enter reason for return...';

  @override
  String get purchasesProcessreturn => 'Process Return';

  @override
  String get purchasesReturnprocessed => 'Return processed successfully';

  @override
  String get purchasesReturnfailed => 'Failed to process return';

  @override
  String get purchasesReturnhistory => 'View Returns';

  @override
  String get purchasesReturnnoitems => 'No returns found';

  @override
  String get purchasesReturnloaderror => 'Failed to load returns';

  @override
  String get purchasesReturnvalue => 'Total Return Value';

  @override
  String get purchasesOriginalqty => 'Original Qty';

  @override
  String get purchasesReturnqty => 'Return Qty';

  @override
  String get purchasesReturndate => 'Return Date';

  @override
  String get purchasesReturntype => 'Type';

  @override
  String get purchasesPurchasereturn => 'Purchase Return';

  @override
  String get purchasesPoreturn => 'PO Return';

  @override
  String get purchasesNewreturn => 'New Return';

  @override
  String get purchasesReturnsourcepicker => 'Select Return Source';

  @override
  String get purchasesReturnsourcetype => 'Source Type';

  @override
  String get purchasesReturnsourcedirect => 'Direct Purchase';

  @override
  String get purchasesReturnsourcepo => 'Purchase Order';

  @override
  String get purchasesReturnsourcenone => 'No matching source documents';

  @override
  String get purchasesReturnwarehouse => 'Restock Warehouse';

  @override
  String get purchasesReturnitems => 'Items to Return';

  @override
  String get purchasesReturnempty =>
      'No items can be returned from this document';

  @override
  String get purchasesAlreadyreturned => 'Already Returned';

  @override
  String get purchasesAvailable => 'Available';

  @override
  String get purchasesVoid => 'Void';

  @override
  String get purchasesVoidreturn => 'Void Return';

  @override
  String get purchasesVoidreturnsure =>
      'This reverses the stock movement, GL entry and supplier credit note.';

  @override
  String get purchasesVoidreason => 'Void Reason';

  @override
  String get purchasesVoidreasonplaceholder => 'Enter reason for voiding...';

  @override
  String get purchasesShowvoided => 'Show Voided';

  @override
  String get purchasesReturnvoided => 'Return voided successfully';

  @override
  String get salesInvoices => 'Invoices';

  @override
  String get salesNewinvoice => 'New Invoice';

  @override
  String get salesEditinvoice => 'Edit Invoice';

  @override
  String get salesInvoiceno => 'Invoice No';

  @override
  String get salesDuedate => 'Due Date';

  @override
  String get salesBalance => 'Balance';

  @override
  String get salesConfirmdelete => 'Are you sure you want to delete';

  @override
  String get salesInvoicedeleted => 'Invoice deleted successfully!';

  @override
  String get salesInvoicesaved => 'Invoice saved successfully!';

  @override
  String get salesLoading => 'Loading...';

  @override
  String get salesNoinvoices => 'No invoices found';

  @override
  String get salesSearchplaceholder => 'Search invoices...';

  @override
  String get salesAllinvoices => 'All Invoices';

  @override
  String get salesPaidinvoices => 'Paid';

  @override
  String get salesUnpaidinvoices => 'Unpaid';

  @override
  String get salesPartialinvoices => 'Partial';

  @override
  String get salesOverdueinvoices => 'Overdue';

  @override
  String get salesTotalsales => 'Total Sales';

  @override
  String get salesTotalpaid => 'Total Paid';

  @override
  String get salesTotaldue => 'Total Due';

  @override
  String get salesRecordsale => 'Record Sale';

  @override
  String get salesCreateinvoice => 'Create Invoice';

  @override
  String get salesPos => 'POS';

  @override
  String get salesSalesreport => 'Sales Summary';

  @override
  String get salesStockvaluation => 'Stock Valuation';

  @override
  String get salesPrinta4 => 'Print A4';

  @override
  String get salesReceipt => 'Receipt';

  @override
  String get inventoryItemsin => 'Items in';

  @override
  String get inventoryBacktowarehouses => 'Back to Warehouses';

  @override
  String get inventoryStockvalue => 'Stock Value';

  @override
  String get inventoryCurrentinventoryworth => 'Current inventory worth';

  @override
  String get inventoryTotalstock => 'Total Stock';

  @override
  String get inventoryAggregateqty => 'Aggregate quantity';

  @override
  String get inventoryLowstock => 'Low Stock';

  @override
  String get inventoryBelowreorder => 'Below reorder level';

  @override
  String get inventoryOutofstock => 'Out of Stock';

  @override
  String get inventoryZerostock => 'Zero stock items';

  @override
  String get inventoryCategories => 'Categories';

  @override
  String get inventoryUniquecats => 'Unique categories';

  @override
  String get inventoryRawmaterials => 'Raw Materials';

  @override
  String get inventoryMaterialitems => 'Material items';

  @override
  String get inventoryFinishedgoods => 'Finished Goods';

  @override
  String get inventoryManufacturedproducts => 'Manufactured products';

  @override
  String get inventoryExportcsv => 'Export to CSV';

  @override
  String get inventoryImportitems => 'Import Items';

  @override
  String get inventoryLowstockreport => 'Low Stock Report';

  @override
  String get inventoryStockvaluation => 'Stock Valuation';

  @override
  String get inventorySearchplaceholder => 'Search items by name or code...';

  @override
  String get inventoryNoitemsfound => 'No items found';

  @override
  String get inventoryNoitemsmatch => 'No items match';

  @override
  String get inventoryNoitemswarehouse => 'No items in this warehouse';

  @override
  String get inventoryNoitemswarehouseyet =>
      'This warehouse doesn\'t have any items yet.';

  @override
  String get inventoryViewallitems => 'View All Items';

  @override
  String get inventoryClearsearch => 'Clear Search';

  @override
  String get inventoryLoading => 'Loading...';

  @override
  String get inventoryItemcode => 'Item Code';

  @override
  String get inventoryItemname => 'Item Name';

  @override
  String get inventoryCategory => 'Category';

  @override
  String get inventoryUom => 'UOM';

  @override
  String get inventoryStock => 'Stock';

  @override
  String get inventoryCost => 'Cost';

  @override
  String get inventoryPrice => 'Price';

  @override
  String get inventoryActions => 'Actions';

  @override
  String get inventoryEdit => 'Edit';

  @override
  String get inventoryDelete => 'Delete';

  @override
  String get inventoryDeleting => 'Deleting...';

  @override
  String get inventoryItemdeleted => 'Item deleted successfully!';

  @override
  String get inventoryConfirmdelete => 'Are you sure you want to delete item';

  @override
  String get inventoryItemsexported => 'Items exported successfully!';

  @override
  String get inventoryNoitemsexport => 'No items to export';

  @override
  String get inventoryImportcomplete => 'Import complete';

  @override
  String get inventoryFailed => 'failed';

  @override
  String get inventoryImporterror => 'Failed to import CSV file';

  @override
  String get inventoryCsvempty => 'CSV file is empty';

  @override
  String get inventoryNewitem => 'New Item';

  @override
  String get inventoryActiveitems => 'Active items in catalog';

  @override
  String get paymentsPayments => 'Payments';

  @override
  String get paymentsRecordpayment => 'Record Payment';

  @override
  String get paymentsSelectcustomer => 'Select Customer';

  @override
  String get paymentsDeleteconfirm => 'Are you sure you want to delete payment';

  @override
  String get paymentsDeleted => 'Payment deleted successfully!';

  @override
  String get paymentsNopayments => 'No payments found';

  @override
  String get paymentsNopaymentsmatch => 'No payments match';

  @override
  String get paymentsSearchplaceholder => 'Search payments...';

  @override
  String get paymentsSubtitle => 'Manage customer payments';

  @override
  String get navDashboard => 'Dashboard';

  @override
  String get navInventory => 'Inventory';

  @override
  String get navSales => 'Sales';

  @override
  String get navPurchases => 'Purchases';

  @override
  String get navCustomers => 'Customers';

  @override
  String get navSuppliers => 'Suppliers';

  @override
  String get navInvoices => 'Invoices';

  @override
  String get navReports => 'Reports';

  @override
  String get navSettings => 'Settings';

  @override
  String get navExpenses => 'Expenses';

  @override
  String get navProduction => 'Production';

  @override
  String get navBom => 'BOM';

  @override
  String get navPos => 'POS Terminal';

  @override
  String get navItems => 'Items';

  @override
  String get navWarehouses => 'Warehouses';

  @override
  String get navStockmovements => 'Stock Movements';

  @override
  String get navStockbywarehouse => 'Stock by Warehouse';

  @override
  String get navPhysicalcounts => 'Physical Counts';

  @override
  String get navQuotations => 'Quotations';

  @override
  String get navSalesorders => 'Sales Orders';

  @override
  String get navReportsdashboard => 'Reports Dashboard';

  @override
  String get navArreports => 'A/R Reports';

  @override
  String get navSalessummary => 'Sales Summary';

  @override
  String get navStocklevel => 'Stock Levels';

  @override
  String get navLowstock => 'Low Stock Alert';

  @override
  String get navProfitloss => 'Profit & Loss';

  @override
  String get navCashflow => 'Cash Flow';

  @override
  String get navExpensesreport => 'Expenses Report';

  @override
  String get navHr => 'HR';

  @override
  String get navEmployees => 'Employees';

  @override
  String get navForecasts => 'Forecasts';

  @override
  String get navForecastsdashboard => 'Dashboard';

  @override
  String get navDemand => 'Demand Forecast';

  @override
  String get navForecasttrends => 'Trends';

  @override
  String get navForecastaccuracy => 'Accuracy';

  @override
  String get navRoles => 'Roles';

  @override
  String get navUsers => 'Users';

  @override
  String get navPayments => 'Payments';

  @override
  String get navActivitylog => 'Activity Log';

  @override
  String get navIntegrations => 'Integrations';

  @override
  String get navAdministrator => 'Administrator';

  @override
  String get navPurchaseorders => 'Purchase Orders';

  @override
  String get navSupplieranalysis => 'Supplier Analysis';

  @override
  String get navStockvaluation => 'Stock Valuation';

  @override
  String get navInventorymovement => 'Inventory Movement';

  @override
  String get navManufacturing => 'Manufacturing';

  @override
  String get navPurchasereturns => 'Purchase Returns';

  @override
  String get navInvoicereturns => 'Invoice Returns';

  @override
  String get navQuickinvoice => 'Quick Invoice';

  @override
  String get navProductionsummary => 'Production Summary';

  @override
  String get navBomusage => 'BOM Usage';

  @override
  String get navManageexpenses => 'Manage Expenses';

  @override
  String get navCustomreports => 'Custom Reports';

  @override
  String get customreportsTitle => 'Custom Reports';

  @override
  String get customreportsSubtitle =>
      'Build and manage ad-hoc reports with a visual builder';

  @override
  String get customreportsNewreport => 'New Report';

  @override
  String get customreportsFromtemplate => 'From Template';

  @override
  String get customreportsChoosetemplate => 'Choose a Template';

  @override
  String get customreportsCreatefromtemplate => 'Create from Template';

  @override
  String get customreportsBasedon => 'Based on';

  @override
  String get customreportsName => 'Report Name';

  @override
  String get customreportsNameplaceholder => 'e.g., Monthly Sales Analysis';

  @override
  String get customreportsDescription => 'Description';

  @override
  String get customreportsDescplaceholder =>
      'Optional description for this report';

  @override
  String get customreportsNamerequired => 'Report name is required';

  @override
  String get customreportsCreateandedit => 'Create & Open Editor';

  @override
  String get customreportsTotalreports => 'Total Reports';

  @override
  String get customreportsTemplates => 'Templates';

  @override
  String get customreportsLastrun => 'Last Run';

  @override
  String get customreportsCreated => 'Report created successfully';

  @override
  String get customreportsUpdated => 'Updated';

  @override
  String get customreportsTemplate => 'Template';

  @override
  String get customreportsActions => 'Actions';

  @override
  String get customreportsRun => 'Run';

  @override
  String get customreportsEdit => 'Edit';

  @override
  String get customreportsDuplicate => 'Duplicate';

  @override
  String get customreportsDelete => 'Delete';

  @override
  String get customreportsConfirmdelete => 'Delete Report';

  @override
  String get customreportsConfirmdeletemsg => 'Are you sure you want to delete';

  @override
  String get customreportsDeleted => 'Report deleted successfully';

  @override
  String get customreportsDeleteerror => 'Failed to delete report';

  @override
  String get customreportsDuplicated => 'Report duplicated successfully';

  @override
  String get customreportsDuplicateerror => 'Failed to duplicate report';

  @override
  String get customreportsCreateerror => 'Failed to create report';

  @override
  String get customreportsRan => 'Report executed successfully';

  @override
  String get customreportsRunerror => 'Failed to run report';

  @override
  String get customreportsRows => 'rows';

  @override
  String get customreportsNoreports => 'No custom reports yet';

  @override
  String get customreportsNoreportsdesc =>
      'Create your first report from scratch or use a template to get started.';

  @override
  String get customreportsbuilderSave => 'Save';

  @override
  String get customreportsbuilderSaved => 'Report saved';

  @override
  String get customreportsbuilderSaveerror => 'Failed to save report';

  @override
  String get customreportsbuilderEntity => 'Entity';

  @override
  String get customreportsbuilderFields => 'Fields';

  @override
  String get customreportsbuilderColumns => 'Columns';

  @override
  String get customreportsbuilderFilters => 'Filters';

  @override
  String get customreportsbuilderSort => 'Sort';

  @override
  String get customreportsbuilderComputed => 'Computed';

  @override
  String get customreportsbuilderDragfieldshint => 'Drag fields below';

  @override
  String get customreportsbuilderDropfieldshere =>
      'Drag fields here to add columns';

  @override
  String get customreportsbuilderAddfilter => 'Add Filter';

  @override
  String get customreportsbuilderNofilters =>
      'No filters — add one to filter results';

  @override
  String get customreportsbuilderAddsort => 'Add Sort';

  @override
  String get customreportsbuilderNosorts =>
      'No sorts — add one to order results';

  @override
  String get customreportsbuilderAddcomputed => 'Add Computed Column';

  @override
  String get customreportsbuilderNocomputed =>
      'No computed columns — add one for aggregations';

  @override
  String get customreportsbuilderRun => 'Run Report';

  @override
  String get customreportsbuilderRunerror => 'Failed to run report';

  @override
  String get customreportsbuilderPreview => 'Preview';

  @override
  String get customreportsbuilderRuntopreview =>
      'Click \'Run Report\' to see results';

  @override
  String get customreportsbuilderSelectentityfirst =>
      'Select an entity to start building your report';

  @override
  String get customreportsbuilderChart => 'Chart';

  @override
  String get customreportsbuilderEnablechart => 'Enable chart visualization';

  @override
  String get customreportsbuilderCharttype => 'Chart Type';

  @override
  String get customreportsbuilderChartbar => 'Bar';

  @override
  String get customreportsbuilderChartline => 'Line';

  @override
  String get customreportsbuilderChartpie => 'Pie';

  @override
  String get customreportsbuilderChartdoughnut => 'Doughnut';

  @override
  String get customreportsbuilderLabelfield => 'Label Field';

  @override
  String get customreportsbuilderValuefield => 'Value Field';

  @override
  String get customreportsbuilderChartempty =>
      'Select label and value fields in the Chart tab to render a chart.';

  @override
  String get customreportsbuilderGroup => 'Group';

  @override
  String get customreportsbuilderEnablegroupby => 'Enable grouping';

  @override
  String get customreportsbuilderGroupfields => 'Group By Fields';

  @override
  String get customreportsbuilderNogroupfields =>
      'Select at least one field to group by';

  @override
  String get customreportsbuilderGroupbyinfo =>
      'Add SUM, COUNT, or other aggregate computed columns to show grouped values.';

  @override
  String get customreportsbuilderAggregates => 'Aggregates';

  @override
  String get customreportsbuilderAddaggregate => 'Add Aggregate';

  @override
  String get customreportsbuilderNoaggregates =>
      'No aggregates — add one to compute grouped values';

  @override
  String get customreportsbuilderExportcsv => 'Export as CSV';

  @override
  String get customreportsbuilderExportpdf => 'Export as PDF';

  @override
  String get customreportsbuilderSaveastemplate => 'Save as Template';

  @override
  String get customreportsbuilderShowall => 'Show All';

  @override
  String get customreportsbuilderHideall => 'Hide All';

  @override
  String get customreportsbuilderTemplatenameprompt => 'Template name:';

  @override
  String get customreportsbuilderTemplatesaved =>
      'Template saved successfully!';

  @override
  String get customreportsbuilderTemplatesaveerror => 'Failed to save template';

  @override
  String get actionsSave => 'Save';

  @override
  String get actionsCancel => 'Cancel';

  @override
  String get actionsDelete => 'Delete';

  @override
  String get actionsEdit => 'Edit';

  @override
  String get actionsAdd => 'Add';

  @override
  String get actionsSearch => 'Search';

  @override
  String get actionsFilter => 'Filter';

  @override
  String get actionsExport => 'Export';

  @override
  String get actionsImport => 'Import';

  @override
  String get actionsPrint => 'Print';

  @override
  String get actionsClose => 'Close';

  @override
  String get actionsConfirm => 'Confirm';

  @override
  String get actionsSubmit => 'Submit';

  @override
  String get actionsClear => 'Clear';

  @override
  String get actionsReset => 'Reset';

  @override
  String get actionsRefresh => 'Refresh';

  @override
  String get actionsView => 'View';

  @override
  String get actionsCreate => 'Create';

  @override
  String get actionsUpdate => 'Update';

  @override
  String get actionsDownload => 'Download';

  @override
  String get actionsUpload => 'Upload';

  @override
  String get actionsBack => 'Back';

  @override
  String get actionsNext => 'Next';

  @override
  String get actionsPrevious => 'Previous';

  @override
  String get actionsApply => 'Apply';

  @override
  String get actionsSelect => 'Select';

  @override
  String get actionsYes => 'Yes';

  @override
  String get actionsNo => 'No';

  @override
  String get messagesSaved => 'Saved successfully';

  @override
  String get messagesDeleted => 'Deleted successfully';

  @override
  String get messagesError => 'An error occurred';

  @override
  String get messagesConfirm => 'Are you sure?';

  @override
  String get messagesLoading => 'Loading...';

  @override
  String get messagesNodata => 'No data found';

  @override
  String get messagesSuccess => 'Success';

  @override
  String get messagesFailed => 'Failed';

  @override
  String get messagesRequired => 'This field is required';

  @override
  String get messagesInvalid => 'Invalid value';

  @override
  String get messagesSavederror => 'Error saving data';

  @override
  String get messagesDeletederror => 'Error deleting data';

  @override
  String get messagesFetcherror => 'Error fetching data';

  @override
  String get messagesNetworkerror => 'Network error';

  @override
  String get fieldsName => 'Name';

  @override
  String get fieldsQuantity => 'Quantity';

  @override
  String get fieldsPrice => 'Price';

  @override
  String get fieldsTotal => 'Total';

  @override
  String get fieldsDate => 'Date';

  @override
  String get fieldsStatus => 'Status';

  @override
  String get fieldsType => 'Type';

  @override
  String get fieldsDescription => 'Description';

  @override
  String get fieldsAddress => 'Address';

  @override
  String get fieldsPhone => 'Phone';

  @override
  String get fieldsEmail => 'Email';

  @override
  String get fieldsAmount => 'Amount';

  @override
  String get fieldsBalance => 'Balance';

  @override
  String get fieldsReturned => 'Returned';

  @override
  String get fieldsDiscount => 'Discount';

  @override
  String get fieldsTax => 'Tax';

  @override
  String get fieldsSubtotal => 'Subtotal';

  @override
  String get fieldsGrandtotal => 'Grand Total';

  @override
  String get fieldsNotes => 'Notes';

  @override
  String get fieldsReference => 'Reference';

  @override
  String get fieldsInvoice => 'Invoice';

  @override
  String get fieldsCustomer => 'Customer';

  @override
  String get fieldsItem => 'Item';

  @override
  String get fieldsWarehouse => 'Warehouse';

  @override
  String get fieldsSupplier => 'Supplier';

  @override
  String get fieldsCategory => 'Category';

  @override
  String get fieldsUnit => 'Unit';

  @override
  String get fieldsCost => 'Cost';

  @override
  String get fieldsRate => 'Rate';

  @override
  String get fieldsSearch => 'Search';

  @override
  String get fieldsFromdate => 'From Date';

  @override
  String get fieldsTodate => 'To Date';

  @override
  String get fieldsCreatedat => 'Created At';

  @override
  String get fieldsUpdatedat => 'Updated At';

  @override
  String get statusActive => 'Active';

  @override
  String get statusInactive => 'Inactive';

  @override
  String get statusPending => 'Pending';

  @override
  String get statusCompleted => 'Completed';

  @override
  String get statusCancelled => 'Cancelled';

  @override
  String get statusDraft => 'Draft';

  @override
  String get statusPaid => 'Paid';

  @override
  String get statusUnpaid => 'Unpaid';

  @override
  String get statusPartial => 'Partial';

  @override
  String get statusDue => 'Due';

  @override
  String get statusOverdue => 'Overdue';

  @override
  String get commonAll => 'All';

  @override
  String get commonNone => 'None';

  @override
  String get commonSelectoption => 'Select an option';

  @override
  String get commonEntervalue => 'Enter value';

  @override
  String get commonNoresults => 'No results found';

  @override
  String get commonEntries => 'entries';

  @override
  String get commonRequired => 'Required';

  @override
  String get commonOptional => 'Optional';

  @override
  String get commonActions => 'Actions';

  @override
  String get commonDetails => 'Details';

  @override
  String get commonSummary => 'Summary';

  @override
  String get commonHistory => 'History';

  @override
  String get commonSettings => 'Settings';

  @override
  String get commonLanguage => 'Language';

  @override
  String get commonThemeMode => 'Dark mode';

  @override
  String get commonCurrency => 'Currency';

  @override
  String get commonLogout => 'Logout';

  @override
  String get commonLogin => 'Login';

  @override
  String get commonUser => 'User';

  @override
  String get commonTotal => 'Total';

  @override
  String get commonTotalin => 'Total In';

  @override
  String get commonTotalout => 'Total Out';

  @override
  String get commonQuantity => 'Quantity';

  @override
  String get commonAmount => 'Amount';

  @override
  String get commonDate => 'Date';

  @override
  String get commonStatus => 'Status';

  @override
  String get commonCategory => 'Category';

  @override
  String get commonDescription => 'Description';

  @override
  String get commonSave => 'Save';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonEdit => 'Edit';

  @override
  String get commonSearch => 'Search';

  @override
  String get commonFilter => 'Filter';

  @override
  String get commonExport => 'Export';

  @override
  String get commonImport => 'Import';

  @override
  String get commonPrint => 'Print';

  @override
  String get commonDownload => 'Download';

  @override
  String get commonClose => 'Close';

  @override
  String get commonConfirm => 'Confirm';

  @override
  String get commonSubmit => 'Submit';

  @override
  String get commonClear => 'Clear';

  @override
  String get commonReset => 'Reset';

  @override
  String get commonRefresh => 'Refresh';

  @override
  String get commonView => 'View';

  @override
  String get commonCreate => 'Create';

  @override
  String get commonUpdate => 'Update';

  @override
  String get commonAdd => 'Add';

  @override
  String get commonBack => 'Back';

  @override
  String get commonNodata => 'No data found';

  @override
  String get commonLoading => 'Loading...';

  @override
  String get commonSales => 'Sales';

  @override
  String get commonReceiptprinting => 'Receipt printing...';

  @override
  String get commonPurchases => 'Purchases';

  @override
  String get commonProduction => 'Production';

  @override
  String get commonTransfers => 'Transfers';

  @override
  String get commonWarehouse => 'Warehouse';

  @override
  String get commonItem => 'Item';

  @override
  String get commonCustomer => 'Customer';

  @override
  String get commonSupplier => 'Supplier';

  @override
  String get commonUom => 'UOM';

  @override
  String get commonStock => 'Stock';

  @override
  String get commonPrice => 'Price';

  @override
  String get commonCost => 'Cost';

  @override
  String get commonUnits => 'units';

  @override
  String get commonFrom => 'From';

  @override
  String get commonTo => 'To';

  @override
  String get shortcutsQuickactions => 'Quick actions';

  @override
  String get shortcutsDismissbar => 'Hide shortcut bar';

  @override
  String get shortcutsNoshortcuts => 'No shortcuts';

  @override
  String get shortcutsPrinta4 => 'Print A4 Invoice';

  @override
  String get shortcutsPrintreceipt => 'Print Receipt (Thermal)';

  @override
  String get shortcutsPrintpo => 'Print Purchase Order';

  @override
  String get shortcutsPrintquotation => 'Print Quotation';

  @override
  String get errorsNotfound => 'Not found';

  @override
  String get errorsUnauthorized => 'Unauthorized';

  @override
  String get errorsServererror => 'Server error';

  @override
  String get errorsBadrequest => 'Bad request';

  @override
  String get errorsComingsoon => 'Coming soon';

  @override
  String get errorsFailed => 'Failed';

  @override
  String get errorsAllowpopups => 'Please allow popups to print receipts';

  @override
  String get activitylogAction => 'Action';

  @override
  String get activitylogEntity => 'Entity';

  @override
  String get activitylogLevel => 'Level';

  @override
  String get activitylogTimestamp => 'Timestamp';

  @override
  String get activitylogUser => 'User';

  @override
  String get bomFinisheditem => 'Finished Item';

  @override
  String get bomItems => 'Materials';

  @override
  String get bomMaterialcost => 'Material Cost';

  @override
  String get bomName => 'BOM Name';

  @override
  String get bomNo => 'BOM No';

  @override
  String get cashreconCounted => 'Counted';

  @override
  String get cashreconExpected => 'Expected';

  @override
  String get cashreconInflow => 'Inflow';

  @override
  String get cashreconNotes => 'Notes';

  @override
  String get cashreconOpening => 'Opening';

  @override
  String get cashreconOutflow => 'Outflow';

  @override
  String get cashreconVariance => 'Variance';

  @override
  String get commonNext => 'Next';

  @override
  String get commonOf => 'of';

  @override
  String get commonPage => 'Page';

  @override
  String get commonPerpage => 'per page';

  @override
  String get commonPrevious => 'Previous';

  @override
  String get drpAddPreset => 'Add preset';

  @override
  String drpDaysSelected(Object n) {
    return '$n days selected';
  }

  @override
  String get drpDefaultFailed => 'Couldn\'t save default range';

  @override
  String get drpDefaultSet => 'Default range set';

  @override
  String get drpNextPeriod => 'Next period';

  @override
  String get drpOneDay => '1 day';

  @override
  String get drpPickDate => 'Pick a date';

  @override
  String get drpPickEnd => 'Pick an end date';

  @override
  String get drpPickStart => 'Pick a start date';

  @override
  String get drpPresetAddFailed => 'Couldn\'t save preset';

  @override
  String get drpPresetAdded => 'Preset added';

  @override
  String get drpPresetAllDates => 'All dates';

  @override
  String get drpPresetCustom => 'Custom';

  @override
  String get drpPresetCustomRange => 'Custom range';

  @override
  String get drpPresetLast30 => 'Last 30 days';

  @override
  String get drpPresetLast7 => 'Last 7 days';

  @override
  String get drpPresetLast90 => 'Last 90 days';

  @override
  String get drpPresetLastMonth => 'Last month';

  @override
  String get drpPresetLastWeek => 'Last week';

  @override
  String get drpPresetName => 'Preset name';

  @override
  String get drpPresetRemove => 'Remove preset';

  @override
  String get drpPresetRemoveFailed => 'Couldn\'t remove preset';

  @override
  String get drpPresetThisMonth => 'This month';

  @override
  String get drpPresetThisWeek => 'This week';

  @override
  String get drpPresetToday => 'Today';

  @override
  String get drpPresetYesterday => 'Yesterday';

  @override
  String get drpPrevPeriod => 'Previous period';

  @override
  String get drpSetDefault => 'Set as default range';

  @override
  String get drpWeekStartFailed => 'Couldn\'t save week start';

  @override
  String get drpWeekStartsOn => 'Week starts on';

  @override
  String get drpWeekdayMonday => 'Monday';

  @override
  String get drpWeekdaySaturday => 'Saturday';

  @override
  String get drpWeekdaySunday => 'Sunday';

  @override
  String get expensesCreatedby => 'Created By';

  @override
  String get expensesExpenseno => 'Expense No';

  @override
  String get expensesPaymentmethod => 'Payment Method';

  @override
  String get expensesProject => 'Project';

  @override
  String get expensesReferenceno => 'Reference No';

  @override
  String get expensesVendor => 'Vendor';

  @override
  String get fieldsAccount => 'Account';

  @override
  String get fieldsCustomerCode => 'Customer Code';

  @override
  String get fieldsMetric => 'Metric';

  @override
  String get fieldsValue => 'Value';

  @override
  String get inventoryCurrentstock => 'Current Stock';

  @override
  String get inventoryReorderlevel => 'Reorder Level';

  @override
  String get inventoryStockledgerBalance => 'Balance';

  @override
  String get inventoryStockledgerIn => 'In';

  @override
  String get inventoryStockledgerOut => 'Out';

  @override
  String get inventoryStockledgerType => 'Type';

  @override
  String get paymentsErrorAmountGreaterThanZero =>
      'Payment amount must be greater than zero';

  @override
  String get productionBatchno => 'Batch No';

  @override
  String get productionNo => 'Production No';

  @override
  String get productionOutputitem => 'Output Item';

  @override
  String get productionTotalcost => 'Total Cost';

  @override
  String get productionUnitcost => 'Unit Cost';

  @override
  String get productionWarehouse => 'Finished Goods Warehouse';

  @override
  String get purchaseordersExpecteddelivery => 'Expected Delivery';

  @override
  String get purchaseordersPono => 'PO No';

  @override
  String get purchasesReturnno => 'Return No';

  @override
  String get reportsAvginvoicevalue => 'Avg. Invoice Value';

  @override
  String get reportsAvgordervalue => 'Avg. Order Value';

  @override
  String get reportsBalance => 'Balance';

  @override
  String get reportsClosingbalance => 'Closing Balance';

  @override
  String get reportsCurrent => 'Current';

  @override
  String get reportsDays1_30 => '1-30 Days';

  @override
  String get reportsDays31_60 => '31-60 Days';

  @override
  String get reportsDays61_90 => '61-90 Days';

  @override
  String get reportsDays90plus => '90+ Days';

  @override
  String get reportsDsodays => 'Days Sales Outstanding';

  @override
  String get reportsGrossprofit => 'Gross Profit';

  @override
  String get reportsGrossprofitmargin => 'Gross Profit Margin';

  @override
  String get reportsInvoicecount => 'Invoice Count';

  @override
  String get reportsItems => 'Items';

  @override
  String get reportsLastpurchase => 'Last Purchase';

  @override
  String get reportsMovementno => 'Movement No';

  @override
  String get reportsNetcashflow => 'Net Cash Flow';

  @override
  String get reportsNetprofit => 'Net Profit';

  @override
  String get reportsNetprofitmargin => 'Net Profit Margin';

  @override
  String get reportsOntimedeliveryrate => 'On-time Delivery Rate';

  @override
  String get reportsOpeningbalance => 'Opening Balance';

  @override
  String get reportsPeriod => 'Period';

  @override
  String get reportsTotalar => 'Total AR';

  @override
  String get reportsTotalcogs => 'Cost of Goods Sold (COGS)';

  @override
  String get reportsTotalcredits => 'Total Credits';

  @override
  String get reportsTotaldebits => 'Total Debits';

  @override
  String get reportsTotalexpenses => 'Total Expenses';

  @override
  String get reportsTotalinflow => 'Total Cash Inflow';

  @override
  String get reportsTotalinvoiced => 'Total Invoiced';

  @override
  String get reportsTotalinvoices => 'Total Invoices';

  @override
  String get reportsTotalorders => 'Total Orders';

  @override
  String get reportsTotaloutflow => 'Total Cash Outflow';

  @override
  String get reportsTotaloutstanding => 'Total Outstanding';

  @override
  String get reportsTotalpurchasevalue => 'Total Purchase Value';

  @override
  String get reportsTotalrevenue => 'Total Revenue';

  @override
  String get reportsTotalsales => 'Total Sales';

  @override
  String get reportsTotalvalue => 'Total Value';

  @override
  String get reportsUnitcost => 'Unit Cost';

  @override
  String get reportsValuationmethod => 'Valuation Method';

  @override
  String get salesPaymentdate => 'Payment Date';

  @override
  String get salesreturnsReturns => 'Invoice Returns';

  @override
  String get salesreturnsReturndate => 'Return Date';

  @override
  String get salesreturnsReturnno => 'Return No';

  @override
  String get salesreturnsReturnqty => 'Return Qty';

  @override
  String get salesreturnsReturnvalue => 'Total Return Value';

  @override
  String get suppliersAccountsettings => 'Account Settings';

  @override
  String get suppliersAllocatedpurchases => 'Allocated Purchases';

  @override
  String get suppliersAllocatedpos => 'Allocated POs';

  @override
  String get suppliersAllocationpurchases => 'Purchases';

  @override
  String get suppliersAvailablepurchases => 'Available Purchases';

  @override
  String get suppliersAllpurchasesallocated => 'All purchases allocated';

  @override
  String get suppliersNoopenpurchases =>
      'No open purchases to allocate against';

  @override
  String get suppliersRecordpaymentforpurchase =>
      'Record payment for this purchase';

  @override
  String get suppliersAllocationrequiredpurchases =>
      'At least one PO or purchase allocation is required';

  @override
  String get suppliersAllocation => 'Allocation';

  @override
  String get suppliersAllocationrequired =>
      'At least one PO allocation is required';

  @override
  String get suppliersAllposallocated => 'All available POs are allocated';

  @override
  String get suppliersAmount => 'Amount';

  @override
  String get suppliersAmountmustmatch => 'Amount must match total allocated';

  @override
  String get suppliersAutoallocate => 'Auto Allocate';

  @override
  String get suppliersAvailablepos => 'Available POs';

  @override
  String get suppliersBacktosuppliers => 'Back to Suppliers';

  @override
  String get suppliersBalance => 'Balance';

  @override
  String get suppliersBalancesrecalculated =>
      'Supplier balances recalculated successfully';

  @override
  String get suppliersBeginningbalance => 'Beginning balance';

  @override
  String get suppliersClosingbalance => 'Closing Balance';

  @override
  String get suppliersCompleted => 'Completed';

  @override
  String get suppliersConfirmdelete => 'Are you sure you want to delete';

  @override
  String get suppliersConfirmdeletepayment =>
      'Are you sure you want to delete payment';

  @override
  String get suppliersContactinfo => 'Contact Info';

  @override
  String get suppliersContactperson => 'Contact Person';

  @override
  String get suppliersCurrentbalance => 'Current Balance';

  @override
  String get suppliersDelete => 'Delete';

  @override
  String get suppliersDeletepayment => 'Delete Payment';

  @override
  String get suppliersDraft => 'Draft';

  @override
  String get suppliersEditsupplier => 'Edit Supplier';

  @override
  String get suppliersEndingbalance => 'Ending balance';

  @override
  String get suppliersErrorCodeRequired => 'Supplier code is required';

  @override
  String get suppliersErrorNameRequired => 'Supplier name is required';

  @override
  String get suppliersExpecteddelivery => 'Expected Delivery';

  @override
  String get suppliersExportcsv => 'Export CSV';

  @override
  String get suppliersExportimage => 'Image';

  @override
  String get suppliersExportpdf => 'Export PDF';

  @override
  String get suppliersExportsuccess => 'Exported successfully';

  @override
  String get suppliersFinancialsummary => 'Financial Summary';

  @override
  String get suppliersFixbalances => 'Fix Balances';

  @override
  String get suppliersFixbalancesconfirm =>
      'This will recalculate all supplier balances from their ledger entries. Continue?';

  @override
  String get suppliersLedger => 'Ledger';

  @override
  String get suppliersLedgerCredit => 'Credit';

  @override
  String get suppliersLedgerDebit => 'Debit';

  @override
  String get suppliersLedgerNoentries => 'No ledger entries found';

  @override
  String get suppliersLedgerTotalcredit => 'Total Credit';

  @override
  String get suppliersLedgerTotaldebit => 'Total Debit';

  @override
  String get suppliersLedgerType => 'Type';

  @override
  String get suppliersMethod => 'Method';

  @override
  String get suppliersNoopenpos =>
      'No open purchase orders to allocate against';

  @override
  String get suppliersNopayments => 'No payments found';

  @override
  String get suppliersNopos => 'No purchase orders found';

  @override
  String get suppliersNopurchases => 'No purchases found';

  @override
  String get suppliersNotes => 'Notes';

  @override
  String get suppliersOpeningbalance => 'Opening Balance';

  @override
  String get suppliersOverview => 'Overview';

  @override
  String get suppliersPartial => 'Partial';

  @override
  String get suppliersPaymentdeleted => 'Payment deleted successfully!';

  @override
  String get suppliersPaymentno => 'Payment No';

  @override
  String get suppliersPaymentrecordedsuccess => 'Payment Recorded Successfully';

  @override
  String get suppliersPayments => 'Payments';

  @override
  String get suppliersPaymentterms => 'Payment Terms';

  @override
  String get suppliersPono => 'PO No';

  @override
  String get suppliersPos => 'POs';

  @override
  String get suppliersPostatus => 'Purchase Order Status';

  @override
  String get suppliersPrintreceipt => 'Print Receipt';

  @override
  String get suppliersPrintreceipta4 => 'Print Receipt (A4)';

  @override
  String get suppliersPurchases => 'Purchases';

  @override
  String get suppliersRecordpayment => 'Record Payment';

  @override
  String get suppliersReference => 'Reference';

  @override
  String get suppliersSincesupplier => 'Supplier Since';

  @override
  String get suppliersStatement => 'Statement';

  @override
  String get suppliersStatementsummary => 'Statement Summary';

  @override
  String get suppliersSubmitted => 'Submitted';

  @override
  String get suppliersSuppliercode => 'Supplier Code';

  @override
  String get suppliersSupplierdeleted => 'Supplier deleted successfully!';

  @override
  String get suppliersSupplierdetails => 'Supplier Details';

  @override
  String get suppliersTotal => 'Total';

  @override
  String get suppliersTotalamount => 'Total Amount';

  @override
  String get suppliersTotalcredits => 'Total Credits';

  @override
  String get suppliersTotaldebits => 'Total Debits';

  @override
  String get suppliersTotalpos => 'Total POs';

  @override
  String get suppliersTotalpovalue => 'Total PO Value';

  @override
  String get suppliersTransactiondetails => 'Transaction Details';

  @override
  String get suppliersUnallocated => 'Unallocated Amount';

  @override
  String get suppliersWhatnext => 'What would you like to do next?';

  @override
  String activitylogCleanupsuccess(Object days) {
    return 'Cleaned up $days log entries';
  }

  @override
  String usermanagementPermissionsubtitle(Object roleName) {
    return 'Assign permissions for $roleName';
  }

  @override
  String customersDays(Object customerPaymentTermsDays) {
    return '$customerPaymentTermsDays days';
  }

  @override
  String paymentsErrorAmountExceedsBalance(Object remainingBalance) {
    return 'Payment exceeds the remaining balance of $remainingBalance';
  }

  @override
  String productionShortfallLine(Object arg0, Object arg1, Object arg2) {
    return '$arg0: $arg1 available, $arg2 required';
  }

  @override
  String quotationsConvertedmsg(Object salesOrderNo) {
    return 'Quotation converted — sales order $salesOrderNo created';
  }

  @override
  String get activitylogAllactions => 'All actions';

  @override
  String get activitylogAllentities => 'All entity types';

  @override
  String get activitylogAllusers => 'All users';

  @override
  String get activitylogCleanup => 'Cleanup';

  @override
  String get activitylogCleanupdays => 'Retention (days)';

  @override
  String get activitylogCleanupdesc =>
      'Permanently deletes log entries older than the retention period. This cannot be undone.';

  @override
  String get activitylogCleanupinvalid => 'Enter a valid number of days';

  @override
  String get activitylogCleanuptitle => 'Clean up old logs';

  @override
  String get activitylogCount => 'logs';

  @override
  String get activitylogDetailtitle => 'Activity Detail';

  @override
  String get activitylogDuration => 'Duration';

  @override
  String get activitylogExportcsv => 'Export CSV';

  @override
  String get activitylogExported => 'Activity log exported';

  @override
  String get activitylogExportfailed => 'Export failed';

  @override
  String get activitylogIp => 'IP Address';

  @override
  String get activitylogMetadata => 'Metadata';

  @override
  String get activitylogToday => 'Today';

  @override
  String get activitylogTotal => 'Total logs';

  @override
  String get activitylogUseragent => 'User Agent';

  @override
  String get bomActivate => 'Activate';

  @override
  String get bomAddmaterial => 'Add Material';

  @override
  String get bomCreated => 'Created';

  @override
  String get bomCurrentstock => 'Current Stock';

  @override
  String get bomDeactivate => 'Deactivate';

  @override
  String get bomDeleteconfirm =>
      'Delete this BOM? Materials referencing it will remain untouched. Note: BOMs already used in production records cannot be deleted.';

  @override
  String get bomDeleted => 'BOM deleted';

  @override
  String get bomDescription => 'Description';

  @override
  String get bomDetailstitle => 'Bill of Materials';

  @override
  String get bomEdittitle => 'Edit BOM';

  @override
  String get bomErrorFinisheditem =>
      'Select the finished item this BOM produces.';

  @override
  String get bomErrorItemsrequired => 'Add at least one material line';

  @override
  String get bomExportcsv => 'Export CSV';

  @override
  String get bomExported => 'BOMs exported';

  @override
  String get bomExportfailed => 'Export failed';

  @override
  String get bomMaterials => 'Materials';

  @override
  String get bomNoMaterials => 'No material lines';

  @override
  String get bomQuantity => 'Batch Quantity';

  @override
  String get bomSaved => 'BOM saved';

  @override
  String get bomUnitcost => 'Std Cost';

  @override
  String get cashposExpense => 'Expense';

  @override
  String get cashposPaymentreceived => 'Payment Received';

  @override
  String get cashposPurchase => 'Purchase';

  @override
  String get cashposRefund => 'Refund';

  @override
  String get cashposSalary => 'Salary';

  @override
  String get cashposOwnercapital => 'Owner Capital';

  @override
  String get cashposOwnerwithdrawal => 'Owner Withdrawal';

  @override
  String get cashposSupplierpayment => 'Supplier Payment';

  @override
  String get cashposTransactions => 'Transactions';

  @override
  String get cashreconNet => 'Net';

  @override
  String get cashreconNotcounted => 'Not Counted';

  @override
  String get cashreconReconciled => 'Reconciled';

  @override
  String get cashreconSave => 'Save';

  @override
  String get cashreconSaved => 'Saved';

  @override
  String get changePasswordButton => 'Change Password';

  @override
  String get changePasswordConfirm => 'Confirm New Password';

  @override
  String get changePasswordCurrent => 'Current Password';

  @override
  String get changePasswordMismatch => 'Passwords do not match';

  @override
  String get changePasswordNew => 'New Password';

  @override
  String get changePasswordSameAsCurrent =>
      'New password must be different from the current password';

  @override
  String get changePasswordSuccess => 'Password changed successfully';

  @override
  String get changePasswordTitle => 'Change Password';

  @override
  String get changePasswordTooShort => 'Password must be at least 6 characters';

  @override
  String get changePasswordUpdating => 'Updating...';

  @override
  String get changePasswordWrongCurrent => 'Current password is incorrect';

  @override
  String get commonHide => 'Hide';

  @override
  String get commonRemove => 'Remove';

  @override
  String get commonShow => 'Show';

  @override
  String get customersAccountsettings => 'Account Settings';

  @override
  String get customersAllinvoicesallocated =>
      'All open invoices are already allocated';

  @override
  String get customersAllocatedinvoices => 'Total Allocated';

  @override
  String get customersAllocation => 'Invoice Allocations';

  @override
  String get customersAllocationrequired =>
      'At least one invoice allocation is required';

  @override
  String get customersAmount => 'Amount';

  @override
  String get customersAmountmustmatch => 'Amount must match total allocated';

  @override
  String get customersAutoallocate => 'Auto Allocate';

  @override
  String get customersAvailableinvoices => 'Available Invoices';

  @override
  String get customersAvgdaystopay => 'Avg. Days to Pay';

  @override
  String get customersBacktocustomers => 'Back to Customers';

  @override
  String get customersBalance => 'Balance';

  @override
  String get customersBillingaddress => 'Billing Address';

  @override
  String get customersCancelinvoice => 'Cancel Invoice';

  @override
  String get customersCancelinvoiceconfirm =>
      'Cancel this invoice? This cannot be undone.';

  @override
  String get customersClosingbalance => 'Closing Balance';

  @override
  String get customersConfirmdeleteinvoice => 'Delete invoice';

  @override
  String get customersConfirmdeletepayment => 'Delete payment';

  @override
  String get customersContactinfo => 'Contact Info';

  @override
  String get customersContactperson => 'Contact Person';

  @override
  String get customersCredit => 'Credit';

  @override
  String get customersCreditAbbrev => 'CR';

  @override
  String get customersCreditlimit => 'Credit Limit';

  @override
  String get customersCreditutilization => 'Credit Utilization';

  @override
  String get customersCurrentbalance => 'Current Balance';

  @override
  String get customersCustomercode => 'Customer Code';

  @override
  String get customersCustomerdetails => 'Customer Details';

  @override
  String get customersCustomersince => 'Customer Since';

  @override
  String get customersDeleteinvoice => 'Delete Invoice';

  @override
  String get customersDeletepayment => 'Delete Payment';

  @override
  String get customersDuedate => 'Due Date';

  @override
  String get customersEditcustomer => 'Edit Customer';

  @override
  String get customersErrorNameRequired => 'Customer name is required';

  @override
  String get customersErrorNonnegative => 'Must be 0 or more';

  @override
  String get customersErrorNumber => 'Enter a valid number';

  @override
  String get customersErrorPhoneRequired => 'Phone number is required';

  @override
  String get customersExportcsv => 'Export to CSV';

  @override
  String get customersExportimage => 'Image';

  @override
  String get customersExportpdf => 'Export to PDF';

  @override
  String get customersExportsuccess => 'Export successful';

  @override
  String get customersFinancialsummary => 'Financial Summary';

  @override
  String get customersFixbalances => 'Fix Balances';

  @override
  String get customersFixbalancesconfirm =>
      'This will recalculate all customer balances from unpaid invoices. Continue?';

  @override
  String get customersFixbalancessuccess =>
      'Balances recalculated successfully';

  @override
  String get customersInvoicecancelled => 'Invoice cancelled';

  @override
  String get customersInvoicedeleted => 'Invoice deleted';

  @override
  String get customersInvoiceno => 'Invoice No';

  @override
  String get customersInvoices => 'Invoices';

  @override
  String get customersInvoicestatus => 'Invoice Status';

  @override
  String get customersLedger => 'Ledger';

  @override
  String get customersLedgerClosingbalance => 'Closing Balance';

  @override
  String get customersLedgerCredit => 'Credit';

  @override
  String get customersLedgerDebit => 'Debit';

  @override
  String get customersLedgerNoentries => 'No ledger entries found';

  @override
  String get customersLedgerPayments => 'payments';

  @override
  String get customersLedgerTotalcredit => 'Total Credit';

  @override
  String get customersLedgerTotaldebit => 'Total Debit';

  @override
  String get customersLedgerTotals => 'TOTALS';

  @override
  String get customersLedgerType => 'Type';

  @override
  String get customersMethod => 'Method';

  @override
  String get customersNoinvoices => 'No invoices found';

  @override
  String get customersNopayments => 'No payments found';

  @override
  String get customersNotapplicable => 'N/A';

  @override
  String get customersNotes => 'Notes';

  @override
  String get customersOpeningbalance => 'Opening Balance';

  @override
  String get customersOutstanding => 'Outstanding';

  @override
  String get customersOverdue => 'Overdue';

  @override
  String get customersOverview => 'Overview';

  @override
  String get customersPaid => 'Paid';

  @override
  String get customersPaymentdeleted => 'Payment deleted';

  @override
  String get customersPaymentno => 'Payment No';

  @override
  String get customersPaymentrecordedsuccess => 'Payment Recorded Successfully';

  @override
  String get customersPayments => 'Payments';

  @override
  String get customersPaymentterms => 'Payment Terms';

  @override
  String get customersPaymenttermsdays => 'Payment Terms (Days)';

  @override
  String get customersPending => 'Pending';

  @override
  String get customersPrintreceipt => 'Print Receipt';

  @override
  String get customersPrintreceipta4 => 'Print Receipt (A4)';

  @override
  String get customersRecordpayment => 'Record Payment';

  @override
  String get customersReference => 'Reference';

  @override
  String get customersShippingaddress => 'Shipping Address';

  @override
  String get customersStatement => 'Statement';

  @override
  String get customersStatementsummary => 'Statement Summary';

  @override
  String get customersTotal => 'Total';

  @override
  String get customersTotalamount => 'Total Amount';

  @override
  String get customersTotalcredits => 'Total Credits';

  @override
  String get customersTotaldebits => 'Total Debits';

  @override
  String get customersTotalinvoiced => 'Total Invoiced';

  @override
  String get customersTotalreceived => 'Total Received';

  @override
  String get customersTransactiondetails => 'Transaction Details';

  @override
  String get customersUnallocated => 'Unallocated Amount';

  @override
  String get customersUtilization => 'Utilization';

  @override
  String get customersWhatnext => 'What would you like to do next?';

  @override
  String get dashboardArsummary => 'AR Summary';

  @override
  String get dashboardCashbankposition => 'Cash / Bank Position';

  @override
  String get dashboardCashrecon => 'Reconcile';

  @override
  String get dashboardCustomers => 'customers';

  @override
  String get dashboardGlobalDateRangeHint =>
      'Date range applies to all report screens';

  @override
  String get dashboardGrossProfit => 'Gross Profit';

  @override
  String get dashboardInvoices => 'invoices';

  @override
  String get dashboardOpeningbalance => 'Opening balance';

  @override
  String get dashboardOpeningbalanceHint =>
      'The starting cash/bank balance your business was founded with. It is added to today\'s position.';

  @override
  String get dashboardPurchaseOrders => 'PO\'s';

  @override
  String get dashboardPurchaseOrdersHint =>
      'Total value of purchases in the selected date range';

  @override
  String get dashboardRecentproductions => 'Recent Productions';

  @override
  String get dashboardTopcustomers => 'Top Customers';

  @override
  String get employeesActivecount => 'Active';

  @override
  String get employeesAlldepartments => 'All Departments';

  @override
  String get employeesAllstatus => 'All Statuses';

  @override
  String get employeesCount => 'employees';

  @override
  String get employeesDeleteconfirm =>
      'Delete this employee? This cannot be undone.';

  @override
  String get employeesDocumentsSelectfile => 'Select File';

  @override
  String get employeesEmploymenttype => 'Employment Type';

  @override
  String get employeesFullname => 'Full Name';

  @override
  String get employeesInvalidamount => 'Enter a valid amount';

  @override
  String get employeesNosalaryhistory => 'No salary payments yet';

  @override
  String get employeesPaymentdate => 'Payment Date';

  @override
  String get employeesPaymentmethod => 'Payment Method';

  @override
  String get employeesPaysalary => 'Pay Salary';

  @override
  String get employeesReferenceno => 'Reference No';

  @override
  String get employeesSalaryamount => 'Amount';

  @override
  String get employeesSalaryhistory => 'Salary History';

  @override
  String get employeesSalarynotes => 'Notes';

  @override
  String get employeesPaymenttype => 'Payment Type';

  @override
  String get employeesPaymenttypeFull => 'Full';

  @override
  String get employeesPaymenttypeAdvance => 'Advance';

  @override
  String get employeesPaymenttypePartial => 'Partial';

  @override
  String get employeesRemainingbalance => 'Remaining Balance';

  @override
  String get employeesSalarydeleted => 'Salary payment deleted';

  @override
  String get employeesSalarypaid => 'Salary payment recorded';

  @override
  String get employeesSalarystatusPaid => 'Paid';

  @override
  String get employeesSalarystatusPartial => 'Partial';

  @override
  String get employeesSalarystatusAdvance => 'Advance';

  @override
  String get employeesAlreadyPaid => 'Already paid this month';

  @override
  String get employeesAdvanceFromPrevious => 'Advance from previous month';

  @override
  String get employeesAdvanceFrom => 'Advance from';

  @override
  String get employeesTotaladvance => 'Total Advance Carryover';

  @override
  String get employeesMonthdetail => 'Salary Details';

  @override
  String get employeesPaymore => 'Pay More';

  @override
  String get employeesLoans => 'Loans';

  @override
  String get employeesNoLoans => 'No loans recorded';

  @override
  String get employeesNewLoan => 'New Loan';

  @override
  String get employeesRepayLoan => 'Repay Loan';

  @override
  String get employeesLoanAmount => 'Loan Amount';

  @override
  String get employeesLoanBalance => 'Remaining Balance';

  @override
  String get employeesLoanPurpose => 'Purpose';

  @override
  String get employeesLoanDisbursementDate => 'Disbursement Date';

  @override
  String get employeesLoanDueDate => 'Due Date';

  @override
  String get employeesLoanMonthlyInstallment => 'Monthly Installment';

  @override
  String get employeesLoanPaymentMethod => 'Payment Method';

  @override
  String get employeesLoanStatusActive => 'Active';

  @override
  String get employeesLoanStatusCompleted => 'Completed';

  @override
  String get employeesLoanStatusOverdue => 'Overdue';

  @override
  String get employeesLoanStatusWrittenOff => 'Written Off';

  @override
  String get employeesLoanCreated => 'Loan recorded successfully';

  @override
  String get employeesLoanRepaid => 'Repayment recorded';

  @override
  String get employeesLoanWrittenOff => 'Loan written off';

  @override
  String get employeesLoanDeleted => 'Loan deleted';

  @override
  String get employeesLoanRepaymentAmount => 'Repayment Amount';

  @override
  String get employeesLoanRepaymentDate => 'Repayment Date';

  @override
  String get employeesLoanRepaymentTypeDirect => 'Direct Payment';

  @override
  String get employeesLoanRepaymentTypeSalary => 'Salary Deduction';

  @override
  String get employeesLoanRepaymentExceeds => 'Repayment exceeds loan balance';

  @override
  String get employeesLoanOutstanding => 'Total Outstanding';

  @override
  String get employeesLoanTotalRepaid => 'Total Repaid';

  @override
  String get employeesLoanDeductFromSalary => 'Deduct for loan';

  @override
  String get employeesLoanSuggestedInstallment => 'Suggested';

  @override
  String get employeesSearch => 'Search employees...';

  @override
  String get employeesTotalsalary => 'Total Salary';

  @override
  String get expensesAddcategory => 'Add Category';

  @override
  String get expensesAllcategories => 'All Categories';

  @override
  String get expensesAllstatuses => 'All Statuses';

  @override
  String get expensesCategories => 'Expense Categories';

  @override
  String get expensesCategorycreated => 'Expense category created';

  @override
  String get expensesCategorydeleted => 'Expense category deleted';

  @override
  String get expensesCategoryname => 'Category Name';

  @override
  String get expensesCount => 'expenses';

  @override
  String expensesDeletecategoryconfirm(Object categoryName) {
    return 'Delete category \"$categoryName\"? This cannot be undone.';
  }

  @override
  String get expensesDeleteconfirmdesc =>
      'This will permanently remove the expense record.';

  @override
  String get expensesDeleted => 'Expense deleted';

  @override
  String get expensesEdit => 'Edit Expense';

  @override
  String get expensesErrorAmountInvalid => 'Enter a valid amount';

  @override
  String get expensesErrorAmountRequired => 'Amount is required';

  @override
  String get expensesErrorCategoryRequired => 'Category is required';

  @override
  String get expensesErrorCategorynameRequired => 'Category name is required';

  @override
  String get expensesExpensedate => 'Expense Date';

  @override
  String get expensesExportcsv => 'Export to CSV';

  @override
  String get expensesExported => 'Expenses exported';

  @override
  String get expensesExportfailed => 'Failed to export expenses';

  @override
  String get forecastsAdequate => 'Adequate';

  @override
  String get forecastsConfidence => 'Confidence';

  @override
  String get forecastsCritical => 'Critical';

  @override
  String get forecastsMonitor => 'Monitor';

  @override
  String get forecastsOk => 'OK';

  @override
  String get forecastsOrdernow => 'Order Now';

  @override
  String get forecastsOrdersoon => 'Order Soon';

  @override
  String get forecastsPredictedmonth => 'Predicted (Month)';

  @override
  String get forecastsPredictedquarter => 'Predicted (Quarter)';

  @override
  String get forecastsPredictedweek => 'Predicted (Week)';

  @override
  String get forecastsRecommendation => 'Recommendation';

  @override
  String get forecastsSearchitems => 'Search items...';

  @override
  String get forecastsWarning => 'Warning';

  @override
  String get integrationsApikey => 'API Key';

  @override
  String get integrationsApikeyHelper =>
      'Stored encrypted — leave blank to keep the current key.';

  @override
  String get integrationsConfigured => 'Configured';

  @override
  String get integrationsEnabled => 'Enabled';

  @override
  String get integrationsFieldAccountsid => 'Account SID';

  @override
  String get integrationsFieldBase => 'Base Currency';

  @override
  String get integrationsFieldDefaultcountry => 'Default Country';

  @override
  String get integrationsFieldDefaultlocation => 'Default Location';

  @override
  String get integrationsFieldFromemail => 'From Email';

  @override
  String get integrationsFieldFromname => 'From Name';

  @override
  String get integrationsFieldPhonenumber => 'Phone Number';

  @override
  String get integrationsFieldUpdateinterval => 'Update Interval (s)';

  @override
  String get integrationsFieldZipcode => 'ZIP Code';

  @override
  String get integrationsNotconfigured => 'Not configured';

  @override
  String get integrationsSaveFailed => 'Failed to save integration settings';

  @override
  String get integrationsSaved => 'Integration settings saved';

  @override
  String get integrationsServiceCurrency => 'Currency Exchange (Fixer)';

  @override
  String get integrationsServiceEmail => 'Email (SendGrid)';

  @override
  String get integrationsServiceNotifications => 'SMS Notifications (Twilio)';

  @override
  String get integrationsServiceTax => 'Tax Calculation (TaxJar)';

  @override
  String get integrationsServiceValidation => 'Phone Validation (Numverify)';

  @override
  String get integrationsServiceWeather => 'Weather (Weatherstack)';

  @override
  String get integrationsSubtitle =>
      'Configure third-party services (email, SMS, weather, validation, currency, tax). API keys are stored encrypted and never displayed.';

  @override
  String get inventoryEdititem => 'Edit Item';

  @override
  String get inventoryErrorCodeRequired => 'Item code is required';

  @override
  String get inventoryErrorNameRequired => 'Item name is required';

  @override
  String get inventoryErrorNonnegative => 'Must be 0 or more';

  @override
  String get inventoryErrorNumber => 'Enter a valid number';

  @override
  String get inventoryErrorUomRequired => 'Unit of measure is required';

  @override
  String get inventoryInstock => 'In Stock';

  @override
  String get inventoryItemdetails => 'Item Details';

  @override
  String get inventoryItemtype => 'Type';

  @override
  String get inventoryPurchased => 'Purchased';

  @override
  String get inventoryPurchaseprice => 'Purchase Price';

  @override
  String get inventoryRack => 'Rack';

  @override
  String get inventoryRequired => 'Required';

  @override
  String get inventorySaletype => 'Sale Type';

  @override
  String get inventorySaletypeLoose => 'Loose';

  @override
  String get inventorySaletypePacked => 'Packed';

  @override
  String get inventorySellingprice => 'Selling Price';

  @override
  String get inventoryStandardcost => 'Standard Cost';

  @override
  String get inventoryStockbywarehouse => 'Stock by Warehouse';

  @override
  String get inventoryStockledger => 'Stock Ledger';

  @override
  String get inventoryStockledgerAllwarehouses => 'All Warehouses';

  @override
  String get inventoryStockledgerExportcsv => 'Export to CSV';

  @override
  String get inventoryStockledgerExported => 'Stock ledger exported';

  @override
  String get inventoryStockledgerExportfailed =>
      'Failed to export stock ledger';

  @override
  String get inventoryStockledgerNoentries => 'No stock movements found';

  @override
  String get loginDevHint => 'Default login: admin / admin123';

  @override
  String get loginInvalidCredentials => 'Invalid username or password';

  @override
  String get loginPassword => 'Password';

  @override
  String get loginServerUnreachable =>
      'Cannot reach the server. Is it running on port 3011?';

  @override
  String get loginSigningIn => 'Signing in...';

  @override
  String get loginUsername => 'Username';

  @override
  String get logoutConfirmMessage => 'Are you sure you want to log out?';

  @override
  String get paymentsBalance => 'Balance';

  @override
  String get paymentsNoopeninvoices => 'No open invoices for this customer';

  @override
  String get paymentsNoteshint => 'Optional notes...';

  @override
  String get paymentsOpeninvoices => 'Open Invoices';

  @override
  String get paymentsPaymentdetails => 'Payment Details';

  @override
  String get paymentsPaymentno => 'Payment No';

  @override
  String get paymentsTypein => 'In';

  @override
  String get paymentsTypeout => 'Out';

  @override
  String get paymentsParty => 'Party';

  @override
  String get paymentsRecordedsuccess => 'Payment recorded successfully';

  @override
  String get paymentsReferencehint => 'Check number, transaction ID, etc.';

  @override
  String get paymentsSelectinvoices =>
      'Allocate the payment to this customer\'s open invoices';

  @override
  String get paymentsTotalallocated => 'Total Allocated';

  @override
  String get physicalcountsCancelconfirm =>
      'Cancel this count? It cannot be completed afterward.';

  @override
  String get physicalcountsCancelcount => 'Cancel Count';

  @override
  String get physicalcountsCancelledmsg => 'Count cancelled';

  @override
  String get physicalcountsCompleteconfirm =>
      'Complete this count? Adjustments will be posted for any items with variances.';

  @override
  String get physicalcountsCompletecount => 'Complete Count';

  @override
  String get physicalcountsCompletedmsg => 'Count completed';

  @override
  String get physicalcountsRecordedmsg => 'Counts recorded';

  @override
  String get physicalcountsRecordhint => 'Counted quantity';

  @override
  String get physicalcountsRecordinvalid => 'Enter a valid quantity';

  @override
  String get physicalcountsRecorditems => 'Record Items';

  @override
  String get physicalcountsRecordnone => 'Enter at least one counted quantity';

  @override
  String get physicalcountsRecordsave => 'Save Counts';

  @override
  String get productionAvailable => 'Available';

  @override
  String get productionBom => 'BOM';

  @override
  String get productionBomwarningMismatch =>
      'The selected BOM produces a different item. Change the BOM or the output item.';

  @override
  String get productionBomwarningPickoutput =>
      'Pick an output item first — the BOM auto-fills the inputs for its finished product.';

  @override
  String get productionCostperunit => 'Cost per Unit';

  @override
  String get productionCostpreview => 'Batch Cost Preview';

  @override
  String get productionCreatedby => 'Created by';

  @override
  String get productionDeleteconfirm =>
      'Delete this production run? Stock movements and the GL entry will be reversed.';

  @override
  String get productionDeleted => 'Production deleted';

  @override
  String get productionDetailstitle => 'Production Details';

  @override
  String get productionErrorBomrequired =>
      'Select a BOM to load its material inputs.';

  @override
  String get productionErrorInputsrequired =>
      'Add at least one input material.';

  @override
  String get productionErrorOutputrequired => 'Output item is required.';

  @override
  String get productionErrorWarehouserequired =>
      'Finished-goods warehouse is required.';

  @override
  String get productionExportcsv => 'Export CSV';

  @override
  String get productionExported => 'Productions exported.';

  @override
  String get productionExportfailed => 'Export failed';

  @override
  String get productionInputqty => 'Quantity';

  @override
  String get productionInputs => 'Inputs';

  @override
  String get productionInputsBomhint =>
      'Select a BOM — its material lines appear here.';

  @override
  String get productionMaterialcost => 'Material Cost';

  @override
  String get productionNoinputs => 'No input materials recorded for this run.';

  @override
  String get productionOutputquantity => 'Output Quantity';

  @override
  String get productionOverhead => 'Overhead Cost';

  @override
  String get productionRawmaterialsWarehouse => 'Raw Materials Warehouse';

  @override
  String get productionSaved => 'Production recorded';

  @override
  String get productionShortfallTitle => 'Insufficient stock for these inputs';

  @override
  String get purchaseordersAdditem => 'Add Item';

  @override
  String get purchaseordersBalance => 'Balance';

  @override
  String get purchaseordersDeleteconfirm =>
      'Are you sure you want to delete this purchase order? This cannot be undone.';

  @override
  String get purchaseordersDeleted => 'Purchase order deleted';

  @override
  String get purchaseordersDetailstitle => 'Purchase Order Details';

  @override
  String get purchaseordersEditpurchaseorder => 'Edit Purchase Order';

  @override
  String get purchaseordersErrorItemsrequired => 'Add at least one item';

  @override
  String get purchaseordersErrorQtyexceeds =>
      'Received quantity cannot exceed the pending quantity';

  @override
  String get purchaseordersErrorReceiveditemsrequired =>
      'Enter at least one received quantity';

  @override
  String get purchaseordersErrorSupplierrequired => 'Select a supplier';

  @override
  String get purchaseordersErrorWarehouserequired => 'Select a warehouse';

  @override
  String get purchaseordersExportcsv => 'Export to CSV';

  @override
  String get purchaseordersExported => 'Purchase orders exported';

  @override
  String get purchaseordersExportfailed => 'Failed to export purchase orders';

  @override
  String get purchaseordersNoitems => 'No items on this order';

  @override
  String get purchaseordersNoreceipts => 'No receipts recorded yet';

  @override
  String get purchaseordersOrdered => 'Ordered';

  @override
  String get purchaseordersPending => 'Pending';

  @override
  String get purchaseordersPodate => 'PO Date';

  @override
  String get purchaseordersPrinta4 => 'Print A4';

  @override
  String get purchaseordersQtyreceived => 'Qty Received';

  @override
  String get purchaseordersReceiptdate => 'Receipt Date';

  @override
  String get purchaseordersReceiptno => 'Receipt No';

  @override
  String get purchaseordersReceipts => 'Receipts';

  @override
  String get purchaseordersReceiptsaved => 'Goods receipt recorded';

  @override
  String get purchaseordersReceivegoods => 'Receive Goods';

  @override
  String get purchaseordersSaved => 'Purchase order saved';

  @override
  String get purchaseordersSubmitconfirm =>
      'Submit this purchase order? It will be locked and posted to the supplier ledger.';

  @override
  String get purchaseordersSubmittedsuccess => 'Purchase order submitted';

  @override
  String get purchasesAvailableqty => 'Available for Return';

  @override
  String get purchasesDetailstitle => 'Purchase Details';

  @override
  String get purchasesExportcsv => 'Export to CSV';

  @override
  String get purchasesExported => 'Purchase returns exported';

  @override
  String get purchasesExportfailed => 'Failed to export purchase returns';

  @override
  String get purchasesReturnqtyexceeds =>
      'Return quantity exceeds the available quantity';

  @override
  String get purchasesReturnqtyinvalid => 'Enter a valid return quantity';

  @override
  String get purchasesReturnstockmoved =>
      'This item\'s stock no longer sits in the receipt warehouse — select the warehouse to return from';

  @override
  String get purchasesReturnwarehousenostock =>
      'The selected warehouse doesn\'t have enough stock for the returned items';

  @override
  String get purchasesReturnpickhint =>
      'Select the warehouse holding this stock';

  @override
  String get quotationsAdditem => 'Add Item';

  @override
  String get quotationsConvertconfirm =>
      'This will create a sales order from this quotation and mark it as converted. Continue?';

  @override
  String get quotationsDetailstitle => 'Quotation Details';

  @override
  String get quotationsEditsquotation => 'Edit Quotation';

  @override
  String get quotationsErrorCustomerrequired => 'Select a customer';

  @override
  String get quotationsErrorItemsrequired => 'Add at least one item';

  @override
  String get quotationsExpirydate => 'Expiry Date';

  @override
  String get quotationsExportcsv => 'Export to CSV';

  @override
  String get quotationsExported => 'Quotations exported';

  @override
  String get quotationsExportfailed => 'Failed to export quotations';

  @override
  String get quotationsItem => 'Item';

  @override
  String get quotationsPrinta4 => 'Print A4';

  @override
  String get quotationsQuantity => 'Quantity';

  @override
  String get quotationsQuotationdate => 'Quotation Date';

  @override
  String get quotationsSaved => 'Quotation saved';

  @override
  String get quotationsSearchplaceholder => 'Search quotations...';

  @override
  String get quotationsTerms => 'Terms';

  @override
  String get quotationsUnitprice => 'Unit Price';

  @override
  String get reportsAsOf => 'As of';

  @override
  String get reportsCashflownegative =>
      'This period shows a negative cash flow, consider reviewing expenses and cash outflows.';

  @override
  String get reportsCashflowpositive =>
      'This period shows a positive cash flow, indicating good liquidity.';

  @override
  String get reportsCashreconciliation => 'Cash Reconciliation';

  @override
  String get reportsDashboardSubtitle =>
      'Comprehensive business analytics and reporting';

  @override
  String get reportsDsosubtitle =>
      'Measure of the average number of days it takes to collect payment after a sale.';

  @override
  String get reportsDsounit => 'days';

  @override
  String get reportsExpensesbycategory => 'Expenses by Category';

  @override
  String get reportsExportcsv => 'Export to CSV';

  @override
  String get reportsExported => 'Report exported';

  @override
  String get reportsExportfailed => 'Failed to export report';

  @override
  String get reportsLastinvoicedate => 'Last Invoice Date';

  @override
  String get reportsLowstockcount => 'low stock items';

  @override
  String get reportsPaidamount => 'Paid Amount';

  @override
  String get reportsPlannedquantity => 'Planned Quantity';

  @override
  String get reportsQuantitysold => 'Quantity Sold';

  @override
  String get reportsStockstatus => 'Stock Status';

  @override
  String get reportsTotalamount => 'Total Amount';

  @override
  String get reportsTotalreceivables => 'Total Receivables';

  @override
  String get reportsTotalpayables => 'Total Payables';

  @override
  String get salesAdditem => 'Add Item';

  @override
  String get salesAddmethod => 'Add Method';

  @override
  String get salesClicktoadditem => 'Click to add item...';

  @override
  String get salesDiscount => 'Discount';

  @override
  String get salesDiscountscope => 'Discount Scope';

  @override
  String get salesEditpayment => 'Edit Payment';

  @override
  String get salesErrorCustomerRequired => 'Customer is required';

  @override
  String get salesErrorItemsRequired => 'At least one item is required';

  @override
  String get salesExportcsv => 'Export to CSV';

  @override
  String get salesExported => 'Invoices exported';

  @override
  String get salesExportfailed => 'Failed to export invoices';

  @override
  String get salesGrandtotal => 'Grand Total';

  @override
  String get salesInvoice => 'Invoice';

  @override
  String get salesItems => 'Items';

  @override
  String get salesMethod => 'Method';

  @override
  String get salesPayment => 'Payment';

  @override
  String get salesPaymenthistory => 'Payment History';

  @override
  String get salesPaymentmethods => 'Payment Methods';

  @override
  String get salesPaymentrecorded => 'Payment recorded';

  @override
  String get salesPaymenttotal => 'Payment Total';

  @override
  String get salesPaymentupdated => 'Payment updated';

  @override
  String get salesPeritem => 'Per Item';

  @override
  String get salesRate => 'Rate';

  @override
  String get salesRecordpaymentnow => 'Record payment now';

  @override
  String get salesReference => 'Reference';

  @override
  String get salesSubtotal => 'Subtotal';

  @override
  String get salesTax => 'Tax %';

  @override
  String get salesordersAdditem => 'Add Item';

  @override
  String get salesordersCancelconfirm =>
      'Cancel this sales order? Invoiced orders will have their linked invoice cancelled and stock reversed.';

  @override
  String get salesordersCancelledmsg => 'Sales order cancelled';

  @override
  String get salesordersDelivered => 'Delivered';

  @override
  String get salesordersDeliverydate => 'Delivery Date';

  @override
  String get salesordersDetailstitle => 'Sales Order Details';

  @override
  String get salesordersEditsalesorder => 'Edit Sales Order';

  @override
  String get salesordersErrorCustomerrequired => 'Select a customer';

  @override
  String get salesordersErrorItemsrequired => 'Add at least one item';

  @override
  String get salesordersExportcsv => 'Export to CSV';

  @override
  String get salesordersExported => 'Sales orders exported';

  @override
  String get salesordersExportfailed => 'Failed to export sales orders';

  @override
  String get salesordersItem => 'Item';

  @override
  String get salesordersNoitems => 'No items on this order';

  @override
  String get salesordersPrinta4 => 'Print A4';

  @override
  String get salesordersQuantity => 'Quantity';

  @override
  String get salesordersSaved => 'Sales order saved';

  @override
  String get salesordersSearchplaceholder => 'Search sales orders...';

  @override
  String get salesordersSodate => 'SO Date';

  @override
  String get salesordersUnitprice => 'Unit Price';

  @override
  String get salesreturnsAvailableqty => 'Available for Return';

  @override
  String get salesreturnsDisposition => 'Disposition';

  @override
  String get salesreturnsDispositionadjust => 'Adjust';

  @override
  String get salesreturnsDispositioncredit => 'Credit';

  @override
  String get salesreturnsDispositionrefund => 'Refund';

  @override
  String get salesreturnsExportcsv => 'Export to CSV';

  @override
  String get salesreturnsExported => 'Invoice returns exported';

  @override
  String get salesreturnsExportfailed => 'Failed to export invoice returns';

  @override
  String get salesreturnsProcessreturn => 'Process Return';

  @override
  String get salesreturnsReturn => 'Return';

  @override
  String get salesreturnsReturnnoitems => 'No returns found';

  @override
  String get salesreturnsReturnprocessed => 'Return processed successfully';

  @override
  String get salesreturnsReturnqtyexceeds =>
      'Return quantity exceeds the available quantity';

  @override
  String get salesreturnsReturnqtyinvalid => 'Enter a valid return quantity';

  @override
  String get salesreturnsReturnquantity => 'Return Quantity';

  @override
  String get salesreturnsReturnreason => 'Reason for Return';

  @override
  String get salesreturnsReturnwarehouse => 'Restock Warehouse';

  @override
  String get salesreturnsReturnwarehouserequired =>
      'Select a warehouse to restock into';

  @override
  String get salesreturnsReturnreasonplaceholder =>
      'Enter reason for return...';

  @override
  String get salesreturnsReturnsubtitle => 'Process a return for this invoice';

  @override
  String get salesreturnsReturntitle => 'Invoice Return';

  @override
  String get salesreturnsSearchinvoices => 'Search invoices...';

  @override
  String get salesreturnsSearchplaceholder => 'Search returns...';

  @override
  String get salesreturnsSelectinvoice => 'Select an invoice';

  @override
  String get settingsBackupDeleteFailed => 'Failed to delete backup';

  @override
  String get settingsBackupDeleteMessage =>
      'This permanently deletes the backup file from the server. This action cannot be undone.';

  @override
  String get settingsBackupDeleteTitle => 'Delete backup?';

  @override
  String get settingsBackupDeleted => 'Backup deleted';

  @override
  String get settingsBackupDownloadFailed => 'Failed to download backup';

  @override
  String get settingsBackupDownloaded => 'Backup saved';

  @override
  String get settingsBackupEmpty => 'No backups yet';

  @override
  String get settingsBackupFailed => 'Backup failed';

  @override
  String get settingsBackupFiles => 'Backup files';

  @override
  String get settingsBackupLast => 'Last backup';

  @override
  String get settingsBackupNever => 'Never';

  @override
  String get settingsBackupNow => 'Back Up Now';

  @override
  String get settingsBackupSuccess => 'Backup created';

  @override
  String get settingsEmpty => 'No settings to display';

  @override
  String get settingsKeyCompanyAddress => 'Company Address';

  @override
  String get settingsKeyCompanyEmail => 'Company Email';

  @override
  String get settingsKeyCompanyName => 'Company Name';

  @override
  String get settingsKeyCompanyPhone => 'Company Phone';

  @override
  String get settingsKeyCompanyTaxId => 'Company Tax ID';

  @override
  String get settingsKeyCurrency => 'Currency';

  @override
  String get settingsKeyCurrencyCode => 'Currency Code';

  @override
  String get settingsKeyCurrencySymbol => 'Currency Symbol';

  @override
  String get settingsKeyDateFormat => 'Date Format';

  @override
  String get settingsKeyDecimalPlaces => 'Decimal Places';

  @override
  String get settingsKeyTaxRate => 'Default Tax Rate (%)';

  @override
  String get settingsKeyTooltipTimeout => 'Tooltip Timeout (s)';

  @override
  String get settingsNumberingHelper =>
      'Server-managed document counter — edit with care.';

  @override
  String get settingsSaveFailed => 'Failed to save settings';

  @override
  String get settingsSaved => 'Settings saved';

  @override
  String get settingsSectionBackup => 'Database Backup';

  @override
  String get settingsSectionCompany => 'Company';

  @override
  String get settingsSectionCurrency => 'Currency & Formatting';

  @override
  String get settingsSectionDate => 'Date & Range';

  @override
  String get settingsSectionNumbering => 'Document Numbering';

  @override
  String get settingsSectionOther => 'Other Settings';

  @override
  String get settingsSectionTax => 'Tax';

  @override
  String get settingsSubtitle =>
      'Company profile, currency, tax rates and document numbering.';

  @override
  String get settingsUnsaved => 'Unsaved changes';

  @override
  String get splashLoading => 'Loading...';

  @override
  String get statusApproved => 'Approved';

  @override
  String get statusPartiallypaid => 'Partially Paid';

  @override
  String get statusPartiallyreceived => 'Partially Received';

  @override
  String get statusPartiallyreturned => 'Partially Returned';

  @override
  String get statusReturned => 'Returned';

  @override
  String get statusSent => 'Sent';

  @override
  String get statusSubmitted => 'Submitted';

  @override
  String get statusPosted => 'Posted';

  @override
  String get statusVoided => 'Voided';

  @override
  String get stockmovementsAdjustmenthint => 'e.g. -10 or 10';

  @override
  String get stockmovementsAdjustmentinvalid => 'Enter a valid quantity';

  @override
  String get stockmovementsAdjustmentmsg => 'Stock adjustment recorded';

  @override
  String get stockmovementsAdjustmentreason => 'Reason';

  @override
  String get stockmovementsAdjustmentsave => 'Record Adjustment';

  @override
  String get stockmovementsAdjustmentsubtitle =>
      'Item, Warehouse, Quantity — negative quantity adjusts stock down.';

  @override
  String get stockmovementsAdjustmentzero => 'Quantity cannot be zero';

  @override
  String get stockmovementsFilteradjustment => 'Adjustment';

  @override
  String get stockmovementsFilterall => 'All Movements';

  @override
  String get stockmovementsFilterproduction => 'Production';

  @override
  String get stockmovementsFilterpurchase => 'Purchase';

  @override
  String get stockmovementsFiltersale => 'Sale';

  @override
  String get stockmovementsFiltertransfer => 'Transfer';

  @override
  String get stockmovementsLinkedmovement => 'Linked Movement';

  @override
  String get stockmovementsNewtransfer => 'New Transfer';

  @override
  String get stockmovementsReverse => 'Reverse Adjustment';

  @override
  String get stockmovementsReverseconfirm =>
      'Post a compensating movement for this adjustment? Stock will be adjusted back by the same quantity.';

  @override
  String get stockmovementsReversemsg => 'Adjustment reversed';

  @override
  String get stockmovementsTransferdiff =>
      'Source and destination must be different';

  @override
  String get stockmovementsTransferfrom => 'From Warehouse';

  @override
  String get stockmovementsTransfermsg => 'Stock transferred';

  @override
  String get stockmovementsTransferpartialfail =>
      'Transfer incomplete: the outgoing movement was recorded, but the incoming leg failed:';

  @override
  String get stockmovementsTransferpositive => 'Quantity must be positive';

  @override
  String get stockmovementsTransfersave => 'Transfer Stock';

  @override
  String get stockmovementsTransfersubtitle =>
      'Creates an outgoing movement from the source warehouse and an incoming movement to the destination.';

  @override
  String get stockmovementsTransferto => 'To Warehouse';

  @override
  String get suppliersLedgerTotals => 'Totals';

  @override
  String get usermanagementActivate => 'Activate';

  @override
  String get usermanagementActivated => 'User activated';

  @override
  String get usermanagementAllroles => 'All Roles';

  @override
  String get usermanagementAllstatus => 'All Statuses';

  @override
  String get usermanagementCantmodifysystem =>
      'System roles cannot be modified';

  @override
  String get usermanagementDeactivate => 'Deactivate';

  @override
  String get usermanagementDeactivated => 'User deactivated';

  @override
  String get usermanagementDeleteconfirm =>
      'Delete this user? This cannot be undone.';

  @override
  String get usermanagementDescription => 'Description';

  @override
  String get usermanagementEditrole => 'Edit Role';

  @override
  String get usermanagementEdituser => 'Edit User';

  @override
  String get usermanagementEmail => 'Email';

  @override
  String get usermanagementFullname => 'Full Name';

  @override
  String get usermanagementNewpassword => 'New Password';

  @override
  String get usermanagementNewrole => 'New Role';

  @override
  String get usermanagementNewuser => 'New User';

  @override
  String get usermanagementPassword => 'Password';

  @override
  String get usermanagementPermissioncount => 'permissions';

  @override
  String get usermanagementPermissions => 'Permissions';

  @override
  String get usermanagementPermissionsaved => 'Permissions updated';

  @override
  String get usermanagementPermissionstitle => 'Role Permissions';

  @override
  String get usermanagementResetconfirm => 'Reset this user\'s password?';

  @override
  String get usermanagementResetdone => 'Password reset successfully';

  @override
  String get usermanagementResetpassword => 'Reset Password';

  @override
  String get usermanagementRole => 'Role';

  @override
  String get usermanagementRolecreated => 'Role created successfully';

  @override
  String get usermanagementRoledeleteconfirm =>
      'Delete this role? Users assigned to it must be reassigned first.';

  @override
  String get usermanagementRoledeleted => 'Role deleted successfully';

  @override
  String get usermanagementRolename => 'Role Name';

  @override
  String get usermanagementRoleupdated => 'Role updated successfully';

  @override
  String get usermanagementRolevalidationname => 'Role name is required';

  @override
  String get usermanagementSearchusers => 'Search users...';

  @override
  String get usermanagementSubtitle =>
      'Create and manage system users, roles and permissions';

  @override
  String get usermanagementSystemrole => 'System';

  @override
  String get usermanagementUsercreated => 'User created successfully';

  @override
  String get usermanagementUserdeleted => 'User deleted successfully';

  @override
  String get usermanagementUsername => 'Username';

  @override
  String get usermanagementUserupdated => 'User updated successfully';

  @override
  String get usermanagementValidationEmailrequired => 'Email is required';

  @override
  String get usermanagementValidationInvalidemail => 'Invalid email format';

  @override
  String get usermanagementValidationPasswordlength =>
      'Password must be at least 6 characters';

  @override
  String get usermanagementValidationRolerequired => 'Select a role';

  @override
  String get warehousesDeleteconfirm =>
      'Delete this warehouse? It cannot be undone.';

  @override
  String get warehousesDeletedmsg => 'Warehouse deleted';

  @override
  String get customersErrorEmail => 'Invalid email format';

  @override
  String get customersRemove => 'Remove';

  @override
  String get customersAdd => 'Add';

  @override
  String get dashboardOpeningbalanceSaved => 'Opening balances saved';

  @override
  String get bomActivated => 'BOM activated';

  @override
  String get bomDeactivated => 'BOM deactivated';

  @override
  String get reportsCategoryFinancial => 'Financial Reports';

  @override
  String get reportsCategoryAr => 'Accounts Receivable';

  @override
  String get reportsCategoryAp => 'Accounts Payable';

  @override
  String get reportsTabsAp_aging => 'AP Aging';

  @override
  String get reportsCategoryInventory => 'Inventory Reports';

  @override
  String get reportsTabsBatch_traceability => 'Batch Traceability';

  @override
  String get reportsCategoryAccounting => 'Accounting Reports';

  @override
  String get reportsTabsTrial_balance => 'Trial Balance';

  @override
  String get reportsTabsGeneral_ledger => 'General Ledger';

  @override
  String get reportsTabsIncome_statement => 'Income Statement';

  @override
  String get reportsTabsTax_summary => 'Tax Summary';

  @override
  String get reportsSelectitem => 'Select Item';

  @override
  String get reportsNodata => 'No data available';

  @override
  String get reportsMovementtype => 'Movement Type';

  @override
  String get reportsDate => 'Date';

  @override
  String get reportsQuantity => 'Quantity';

  @override
  String get reportsExpenses => 'Expenses';

  @override
  String get reportsBalanceSheet => 'Balance Sheet';

  @override
  String get reportsTrialbalance => 'Trial Balance';

  @override
  String get reportsAccountcode => 'Account Code';

  @override
  String get reportsAccountname => 'Account Name';

  @override
  String get reportsAccounttype => 'Account Type';

  @override
  String get reportsTotaldebit => 'Total Debit';

  @override
  String get reportsTotalcredit => 'Total Credit';

  @override
  String get reportsBalanced => 'Balanced';

  @override
  String get reportsGeneralledger => 'General Ledger';

  @override
  String get reportsDebit => 'Debit';

  @override
  String get reportsCredit => 'Credit';

  @override
  String get reportsReferenceno => 'Reference No';

  @override
  String get reportsTransactiontype => 'Transaction Type';

  @override
  String get reportsIncomestatement => 'Income Statement';

  @override
  String get reportsRevenue => 'Revenue';

  @override
  String get reportsCogs => 'Cost of Goods Sold';

  @override
  String get reportsNetincome => 'Net Income';

  @override
  String get reportsTaxsummary => 'Tax Summary';

  @override
  String get reportsTotaltax => 'Total Tax';

  @override
  String get reportsBatchtraceability => 'Batch Traceability';

  @override
  String get reportsWarehouseswithstock => 'Warehouses with Stock';

  @override
  String get reportsRecentmovements => 'Recent Movements';

  @override
  String get salesNoproductsfound => 'No products found';

  @override
  String get suppliersErrorEmail => 'Invalid email format';

  @override
  String get searchHint => 'Search customers, suppliers, products, invoices…';

  @override
  String get searchNoResults => 'No results found';

  @override
  String get searchError => 'Search failed';

  @override
  String get searchQuickActions => 'Quick Actions';

  @override
  String get searchRecent => 'Recent';

  @override
  String get searchClose => 'Close';

  @override
  String get expiryTracking => 'Expiry Tracking';

  @override
  String get trackExpiryDates => 'Track expiry dates';

  @override
  String get nearExpiryThreshold => 'Near-expiry threshold (days)';

  @override
  String get expiryDate => 'Expiry Date';

  @override
  String get expirySelectDateOptional => 'Select date (optional)';

  @override
  String get batchManagement => 'Batch Management';

  @override
  String get expiryStatus => 'Expiry Status';

  @override
  String get statusNormal => 'Normal';

  @override
  String get statusNearExpiry => 'Near Expiry';

  @override
  String get statusExpired => 'Expired';

  @override
  String get statusHalted => 'Halted';

  @override
  String get haltBatch => 'Halt Batch';

  @override
  String get unhaltBatch => 'Unhalt Batch';

  @override
  String get haltReason => 'Halt Reason';

  @override
  String get haltReasonHint => 'Reason (optional)';

  @override
  String get manageBatches => 'Manage Batches';

  @override
  String get expiryNotice => 'Expiry Notice';

  @override
  String get nearExpiryNotice => 'Near-Expiry Notice';

  @override
  String get soldAfterExpiry => 'Sold after expiry';

  @override
  String get expiringSoon => 'Expiring Soon';

  @override
  String get expiryReport => 'Expiry Report';

  @override
  String expiryReportPagination(
    Object currentPage,
    Object totalPages,
    Object totalRows,
  ) {
    return '$totalRows rows • Page $currentPage of $totalPages';
  }

  @override
  String get expiryReportFirstPage => 'First page';

  @override
  String get expiryReportPreviousPage => 'Previous page';

  @override
  String get expiryReportNextPage => 'Next page';

  @override
  String get expiryReportLastPage => 'Last page';

  @override
  String get expiryAlerts => 'Expiry Alerts';

  @override
  String get thresholdDays => 'Threshold (days)';

  @override
  String get expiryWarehouseLabel => 'Warehouse';

  @override
  String get daysUntilExpiry => 'Days Until Expiry';

  @override
  String get totalValue => 'Total Value';

  @override
  String get exportCsv => 'Export CSV';

  @override
  String get filters => 'Filters';

  @override
  String get noExpiringBatches => 'No expiring batches';

  @override
  String get fieldsBatchno => 'Batch No';

  @override
  String get fieldsSource => 'Source';

  @override
  String get fieldsUnitcost => 'Unit Cost';

  @override
  String get inventoryQtyoriginal => 'Original Qty';

  @override
  String get inventoryQtyremaining => 'Remaining Qty';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonSaved => 'Saved';

  @override
  String daysRemaining(Object days) {
    return '$days days remaining';
  }

  @override
  String daysExpired(Object days) {
    return '$days days after expiry';
  }

  @override
  String batchesSummary(Object expired, Object near, Object total) {
    return 'Batches: $total total, $near near-expiry, $expired expired';
  }

  @override
  String confirmSellExpired(Object days) {
    return 'This item expired $days days ago. Are you sure you want to sell it?';
  }

  @override
  String get expiredStockConfirm =>
      'The following batches are expired. Selling expired stock may violate policy. Continue anyway?';

  @override
  String nearExpirySaleWarning(
    Object batchNo,
    Object expiryDate,
    Object itemName,
  ) {
    return 'Selling $itemName from batch $batchNo expiring on $expiryDate';
  }

  @override
  String get overrideExpiredSale => 'Override & Sell';

  @override
  String get overrideExpiredBody =>
      'The following batches are expired. Override will temporarily clear their expiry date to allow this sale.';

  @override
  String batchOverrideCleared(Object count) {
    return '$count expired batch(es) overridden for this sale';
  }

  @override
  String get navOwnersequity => 'Owner\'s Equity';

  @override
  String get equityCapital => 'Capital';

  @override
  String get equityWithdrawals => 'Withdrawals';

  @override
  String get equityTotalcapitalin => 'Total Capital In';

  @override
  String get equityTotalwithdrawn => 'Total Withdrawn';

  @override
  String get equityNetcontributions => 'Net Contributions';

  @override
  String get equityNewcapital => 'New Capital';

  @override
  String get equityEditcapital => 'Edit Capital Entry';

  @override
  String get equityCapitaldate => 'Capital date';

  @override
  String get equityCapitalno => 'Doc No';

  @override
  String get equityNewwithdrawal => 'New Withdrawal';

  @override
  String get equityEditwithdrawal => 'Edit Withdrawal';

  @override
  String get equityWithdrawalno => 'Doc No';

  @override
  String get equityKindcash => 'Cash';

  @override
  String get equityKindgoods => 'Goods';

  @override
  String get equityAllkinds => 'All kinds';

  @override
  String get equityKind => 'Kind';

  @override
  String get equityItemstaken => 'Items taken';

  @override
  String get equityItem => 'Item';

  @override
  String get equityItems => 'Items';

  @override
  String get equityWarehouse => 'Warehouse';

  @override
  String get equityAdditem => 'Add item';

  @override
  String get equityMovements => 'Batch movements (at cost)';

  @override
  String get equityTakenout => 'Taken out';

  @override
  String get equityReturned => 'Returned';

  @override
  String get equityCostpreview => 'Costing preview (FIFO)';

  @override
  String get equityCostpreviewempty =>
      'Add item lines to see the calculated withdrawal value.';

  @override
  String get equityCosttotal => 'Total withdrawal value';

  @override
  String get equityCostatcostnote =>
      'Value is calculated from inventory cost, not selling price.';

  @override
  String equityBreakdownTitle(Object docNo) {
    return 'Withdrawal $docNo';
  }

  @override
  String get equitySaved => 'Saved';

  @override
  String get equityVoided => 'Entry voided';

  @override
  String get equityDeleteconfirmdesc =>
      'This voids the general-ledger posting and, for goods withdrawals, returns stock to its original batches. The record stays in history as voided.';

  @override
  String get equityExported => 'Exported';

  @override
  String get equityExportfailed => 'Export failed';

  @override
  String get equityErrorAmountRequired => 'Amount is required';

  @override
  String get equityErrorAmountInvalid => 'Amount must be a positive number';

  @override
  String get equityErrorItemsRequired =>
      'Add at least one item line with a quantity.';

  @override
  String get fieldsNote => 'Note';

  @override
  String get paymentsNewpayment => 'New Payment';

  @override
  String get paymentsFilterAll => 'All';

  @override
  String get paymentsFilterBytype => 'Filter by type';

  @override
  String get paymentsTypeCustomer => 'Customer';

  @override
  String get paymentsTypeSupplier => 'Supplier';

  @override
  String get paymentsTypeExpense => 'Expense';

  @override
  String get paymentsTypeSalary => 'Salary';

  @override
  String get paymentsTypeOwnerCapital => 'Owner Capital';

  @override
  String get paymentsTypeOwnerWithdrawal => 'Owner Withdrawal';

  @override
  String get paymentsTypeUnknown => 'Unknown';

  @override
  String get paymentsMethodCash => 'Cash';

  @override
  String get paymentsMethodBank => 'Bank';

  @override
  String get paymentsMethodCard => 'Card';

  @override
  String get paymentsMethodMobileWallet => 'Mobile Wallet';

  @override
  String get paymentsMethodCredit => 'Credit';

  @override
  String get paymentsMethodOther => 'Other';

  @override
  String get paymentsMethodUnknown => 'Unknown';

  @override
  String get paymentsReceiveFromCustomer => 'Receive from Customer';

  @override
  String get paymentsPayToSupplier => 'Pay to Supplier';

  @override
  String get paymentsRecordExpense => 'Record Expense';

  @override
  String get paymentsPaySalary => 'Pay Salary';

  @override
  String get paymentsOwnerCapital => 'Owner Capital';

  @override
  String get paymentsOwnerWithdrawal => 'Owner Withdrawal';

  @override
  String get paymentsSelectSupplier => 'Select Supplier';

  @override
  String get paymentsSelectEmployee => 'Select Employee';

  @override
  String get paymentsTransactionDetail => 'Transaction Detail';

  @override
  String get paymentsViewEmployee => 'View Employee';

  @override
  String get paymentsSalaryPaymentDetail => 'Salary Payment Detail';

  @override
  String get paymentsExpenseDetail => 'Expense Detail';

  @override
  String get paymentsOwnerCapitalDetail => 'Owner Capital Detail';

  @override
  String get paymentsOwnerWithdrawalDetail => 'Owner Withdrawal Detail';

  @override
  String get paymentsUnknownRow => 'Invalid / legacy row';
}
