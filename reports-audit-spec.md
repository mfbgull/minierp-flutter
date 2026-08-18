# Reports Section Audit Spec

**Date:** 2026-08-19  
**Author:** Buffy (Codebuff)  
**Status:** Draft — pending user review  
**Version:** 2.0 (detailed)

---

## 1. Executive Summary

The reports section contains **22 reports** across 6 categories. After auditing every report against its corresponding module screen, **12 reports are redundant** (show the same data as module screens), **10 reports are unique** (purely analytical, no module equivalent), and **5 server endpoints exist but have no Flutter screen** (need porting).

**Decision:** Remove all 12 duplicate reports (full stack: Flutter screen + server endpoint). Keep all 10 unique reports. Port all 5 missing reports. Add a new "Accounting" category for 3 of the ported reports.

**After cleanup: 15 reports across 7 categories** (down from 22 across 8 categories)

---

## 2. Duplicate Reports — REMOVE (12 reports)

### 2.1 Sales Summary Report

**Overlap:** Both show invoice-level data (date, number, customer, total, paid, balance, status)

**Files to delete:**
- `lib/features/reports/sales_summary_report_screen.dart`
- Server: `GET /reports/sales-summary` endpoint

**Server function signature:**
```typescript
// server/src/models/Reports.ts:233
function getSalesSummary(db: Database.Database, startDate: string, endDate: string)

// server/src/controllers/reportsController.ts:83
function getSalesSummary(req: Request, res: Response): void
```

**Flutter model classes to remove from `lib/data/models/report.dart`:**
- `SalesSummaryPeriod` (line 99) — fields: `startDate`, `endDate`
- `SalesSummaryStats` (line 112) — fields: `totalInvoices`, `totalSales`, `totalItemsSold`, `averageInvoiceValue`, `totalPaid`, `totalBalance`
- `SalesSummaryRow` (line 141) — fields: `invoiceDate`, `invoiceNo`, `customerName`, `totalSales`, `totalItems`, `paidAmount`, `balanceAmount`, `status`
- `SalesSummaryReport` (line 175) — fields: `period`, `summary`, `sales`

**l10n keys to remove from `en.arb` and `ur.arb`:**
- `reportsSalessummaryreport`
- `reportsAvginvoicevalue`
- `reportsTotalinvoices`
- `reportsTotalsales`
- `reportsItemssold`
- `salesTotalsales`
- `salesTotalpaid`
- `salesTotaldue`

**CSV builder to remove from `lib/core/utils/csv_export.dart`:**
- `buildSalesSummaryCsv` (line 549)

**Provider to remove from `lib/features/reports/report_providers.dart`:**
- `salesSummaryProvider`
- `reportSalesFromDateProvider`
- `reportSalesToDateProvider`

---

### 2.2 Sales by Customer Report

**Overlap:** Customer names/codes

**Files to delete:**
- `lib/features/reports/sales_by_customer_report_screen.dart`
- `lib/features/reports/sales_by_customer_detail_dialog.dart`
- Server: `GET /reports/sales-by-customer` endpoint

**Server function signature:**
```typescript
// server/src/models/Reports.ts:270
function getSalesByCustomer(db: Database.Database, startDate: string, endDate: string)

// server/src/controllers/reportsController.ts:102
function getSalesByCustomer(req: Request, res: Response): void
```

**Flutter model class to remove from `lib/data/models/report.dart`:**
- `SalesByCustomerRow` (line 426) — fields: `customerName`, `customerCode`, `email`, `phone`, `totalInvoices`, `totalSales`, `totalItems`, `averageOrderValue`, `lastPurchaseDate`

**l10n keys to remove:**
- `reportsSalesbycustomerreport`
- `reportsAvgordervalue`
- `reportsLastpurchase`

**CSV builder to remove:**
- `buildSalesByCustomerCsv` (line 646)

**Provider to remove:**
- `salesByCustomerReportProvider`
- `reportSalesByCustomerFromDateProvider`
- `reportSalesByCustomerToDateProvider`

---

### 2.3 Sales by Item Report

**Overlap:** Item names/codes

**Files to delete:**
- `lib/features/reports/sales_by_item_report_screen.dart`
- `lib/features/reports/sales_by_item_detail_dialog.dart`
- Server: `GET /reports/sales-by-item` endpoint

**Server function signature:**
```typescript
// server/src/models/Reports.ts:287
function getSalesByItem(db: Database.Database, startDate: string, endDate: string)

// server/src/controllers/reportsController.ts:117
function getSalesByItem(req: Request, res: Response): void
```

**Flutter model class to remove from `lib/data/models/report.dart`:**
- `SalesByItemRow` (line 975) — fields: `itemCode`, `itemName`, `itemCategory`, `totalQuantitySold`, `totalSales`, `averageSellingPrice`

**l10n keys to remove:**
- `reportsSalesbyitemreport`
- `reportsAvgsellingprice`
- `reportsTotalquantitysold`

**CSV builder to remove:**
- `buildSalesByItemCsv` (line 913)

**Provider to remove:**
- `salesByItemReportProvider`
- `reportSalesByItemFromDateProvider`
- `reportSalesByItemToDateProvider`

---

### 2.4 Stock Level Report

**Overlap:** Both show item names, codes, stock levels, and pricing

**Files to delete:**
- `lib/features/reports/stock_level_report_screen.dart`
- Server: `GET /reports/stock-level` endpoint

**Server function signature:**
```typescript
// server/src/models/Reports.ts:814
function getStockLevelReport(db: Database.Database)

// server/src/controllers/reportsController.ts:132
function getStockLevelReport(req: Request, res: Response): void
```

**Flutter model classes to remove from `lib/data/models/report.dart`:**
- `StockLevelRow` (line 258) — fields: `id`, `itemCode`, `itemName`, `itemCategory`, `unitOfMeasure`, `currentStock`, `minimumStock`, `reorderLevel`, `standardSellingPrice`, `stockStatus`
- `StockLevelSummary` (line 297) — fields: `totalItems`, `inStock`, `lowStock`, `outOfStock`
- `StockLevelReport` (line 319) — fields: `rows`, `summary`

**l10n keys to remove:**
- `reportsStocklevelreport`
- `reportsSellingprice`
- `reportsTotalitems`
- `inventoryInstock`
- `inventoryLowstock`
- `inventoryOutofstock`

**CSV builder to remove:**
- `buildStockLevelCsv` (line 583)

**Provider to remove:**
- `stockLevelReportProvider`

---

### 2.5 Low Stock Report

**Overlap:** Item names/codes, stock levels

**Files to delete:**
- `lib/features/reports/low_stock_report_screen.dart`
- `lib/features/reports/low_stock_detail_dialog.dart`
- Server: `GET /reports/low-stock` endpoint

**Server function signature:**
```typescript
// server/src/models/Reports.ts:850
function getLowStockReport(db: Database.Database)

// server/src/controllers/reportsController.ts:137
function getLowStockReport(req: Request, res: Response): void
```

**Flutter model class to remove from `lib/data/models/report.dart`:**
- `LowStockReportRow` (line 208) — fields: `id`, `itemCode`, `itemName`, `itemCategory`, `unitOfMeasure`, `currentStock`, `minimumStock`, `shortage`, `reorderLevel`, `standardSellingPrice`, `stockStatus`

**l10n keys to remove:**
- `reportsLowstockalertreport`
- `reportsLowstockcount`
- `reportsMinimumstock`
- `reportsShortage`
- `reportsShortagetotal`

**CSV builder to remove:**
- `buildLowStockCsv` (line 521)

**Provider to remove:**
- `lowStockReportProvider`

---

### 2.6 Stock Valuation Report

**Overlap:** Item names/codes, cost

**Files to delete:**
- `lib/features/reports/stock_valuation_report_screen.dart`
- `lib/features/reports/stock_valuation_detail_dialog.dart`
- Server: `GET /reports/stock-valuation` endpoint

**Server function signature:**
```typescript
// server/src/models/Reports.ts:299
function getStockValuationReport(db: Database.Database)

// server/src/controllers/reportsController.ts:142
function getStockValuationReport(req: Request, res: Response): void
```

**Flutter model classes to remove from `lib/data/models/report.dart`:**
- `StockValuationRow` (line 342) — fields: `id`, `itemCode`, `itemName`, `itemCategory`, `unitOfMeasure`, `currentStock`, `unitCost`, `totalValue`, `valuationMethod`
- `StockValuationSummary` (line 381) — fields: `totalItems`, `totalValue`, `batchTrackedItems`, `legacyItems`
- `StockValuationReport` (line 403) — fields: `rows`, `summary`

**l10n keys to remove:**
- `reportsStockvaluationreport`
- `reportsTotalinventoryvalue`
- `reportsTotalvalue`
- `reportsUnitcost`
- `reportsValuationmethod`
- `reportsBatchtracked`
- `reportsLegacyitems`

**CSV builder to remove:**
- `buildStockValuationCsv` (line 614)

**Provider to remove:**
- `stockValuationReportProvider`

---

### 2.7 Inventory Movement Report

**Overlap:** Movement data (type, quantity, item)

**Files to delete:**
- `lib/features/reports/inventory_movement_report_screen.dart`
- `lib/features/reports/inventory_movement_detail_dialog.dart`
- Server: `GET /reports/inventory-movement` endpoint

**Server function signature:**
```typescript
// server/src/models/Reports.ts:368
function getInventoryMovementReport(db: Database.Database, startDate?: string, endDate?: string, itemId?: number)

// server/src/controllers/reportsController.ts:149
function getInventoryMovementReport(req: Request, res: Response): void
```

**Flutter model classes to remove from `lib/data/models/report.dart`:**
- `InventoryMovementRow` (line 597) — fields: `movementNo`, `movementType`, `quantity`, `unitCost`, `movementDate`, `referenceDoctype`, `referenceDocno`, `remarks`, `itemCode`, `itemName`, `warehouseName`
- `InventoryMovementSummary` (line 641) — fields: `totalInbound`, `totalOutbound`, `netMovement`
- `InventoryMovementReport` (line 660) — fields: `rows`, `summary`

**l10n keys to remove:**
- `reportsInventorymovementreport`
- `reportsMovementtype`
- `reportsNetmovement`
- `reportsTotalinbound`
- `reportsTotaloutbound`

**CSV builder to remove:**
- `buildInventoryMovementCsv` (line 795)

**Provider to remove:**
- `inventoryMovementReportProvider`
- `reportMovementFromDateProvider`
- `reportMovementToDateProvider`

---

### 2.8 Purchase Summary Report

**Overlap:** PO number, date, supplier, status, total, balance

**Files to delete:**
- `lib/features/reports/purchase_summary_report_screen.dart`
- `lib/features/reports/purchase_summary_detail_dialog.dart`
- Server: `GET /reports/purchase-summary` endpoint

**Server function signature:**
```typescript
// server/src/models/Reports.ts:881
function getPurchaseSummary(startDate: string, endDate: string, db: Database.Database)

// server/src/controllers/reportsController.ts:179
function getPurchaseSummary(req: Request, res: Response): void
```

**Flutter model classes to remove from `lib/data/models/report.dart`:**
- `PurchaseSummaryRow` (line 681) — fields: `poId`, `purchaseOrderNumber`, `purchaseDate`, `supplierName`, `totalCost`, `status`, `totalItems`, `receivedAmount`, `balanceAmount`
- `PurchaseSummaryStats` (line 719) — fields: `totalOrders`, `totalCost`, `totalItems`, `averageOrderValue`, `returnCount`, `returnQuantity`, `returnValue`
- `PurchaseSummaryReport` (line 750) — fields: `rows`, `summary`

**l10n keys to remove:**
- `reportsPurchasesummaryreport`
- `reportsReceived`
- `reportsReturnvalue`
- `reportsTotalcost`
- `reportsTotalorders`

**CSV builder to remove:**
- `buildPurchaseSummaryCsv` (line 828)

**Provider to remove:**
- `purchaseSummaryReportProvider`
- `reportPurchaseFromDateProvider`
- `reportPurchaseToDateProvider`

---

### 2.9 Supplier Analysis Report

**Overlap:** Supplier names/codes

**Files to delete:**
- `lib/features/reports/supplier_analysis_report_screen.dart`
- `lib/features/reports/supplier_analysis_detail_dialog.dart`
- Server: `GET /reports/supplier-analysis` endpoint

**Server function signature:**
```typescript
// server/src/models/Reports.ts:403
function getSupplierAnalysis(db: Database.Database, startDate: string, endDate: string)

// server/src/controllers/reportsController.ts:199
function getSupplierAnalysis(req: Request, res: Response): void
```

**Flutter model class to remove from `lib/data/models/report.dart`:**
- `SupplierAnalysisRow` (line 1009) — fields: `supplierId`, `supplierName`, `supplierCode`, `email`, `phone`, `totalOrders`, `totalPurchaseValue`, `averageOrderValue`, `lastPurchaseDate`, `totalItems`, `onTimeDeliveryRate`

**l10n keys to remove:**
- `reportsSupplieranalysisreport`
- `reportsOntimedeliveryrate`
- `reportsTotalpurchasevalue`

**CSV builder to remove:**
- `buildSupplierAnalysisCsv` (line 939)

**Provider to remove:**
- `supplierAnalysisReportProvider`
- `reportSupplierFromDateProvider`
- `reportSupplierToDateProvider`

---

### 2.10 Production Summary Report

**Overlap:** Production order number, date, quantity

**Files to delete:**
- `lib/features/reports/production_summary_report_screen.dart`
- `lib/features/reports/production_summary_detail_dialog.dart`
- Server: `GET /reports/production-summary` endpoint

**Server function signature:**
```typescript
// server/src/models/Reports.ts:929
function getProductionEfficiency(startDate: string, endDate: string, db: Database.Database)

// server/src/controllers/reportsController.ts:211
function getProductionSummary(req: Request, res: Response): void
```

**Flutter model classes to remove from `lib/data/models/report.dart`:**
- `ProductionSummaryRow` (line 1055) — fields: `workOrderNumber`, `productionDate`, `productionOrderNumber`, `outputItemName`, `outputQuantity`, `completedQuantity`, `scrappedQuantity`, `plannedQuantity`, `itemName`, `status`
- `ProductionSummaryStats` (line 1097) — fields: `totalProductionOrders`, `totalOutput`, `totalCompleted`, `totalScrapped`
- `ProductionSummaryReport` (line 1119) — fields: `rows`, `summary`

**l10n keys to remove:**
- `reportsProductionsummaryreport`
- `reportsProductiondate`
- `reportsProductionorder`
- `reportsOutputitem`
- `reportsOutputquantity`
- `reportsCompletedquantity`
- `reportsScrappedquantity`
- `reportsTotaloutputquantity`
- `reportsTotalproductionorders`

**CSV builder to remove:**
- `buildProductionSummaryCsv` (line 973)

**Provider to remove:**
- `productionSummaryReportProvider`
- `reportProductionFromDateProvider`
- `reportProductionToDateProvider`

---

### 2.11 BOM Usage Report

**Overlap:** BOM names, parent items

**Files to delete:**
- `lib/features/reports/bom_usage_report_screen.dart`
- `lib/features/reports/bom_usage_detail_dialog.dart`
- Server: `GET /reports/bom-usage` endpoint

**Server function signature:**
```typescript
// server/src/models/Reports.ts:971
function getBOMUsageReport(startDate: string, endDate: string, itemId: number | null, db: Database.Database)

// server/src/controllers/reportsController.ts:222
function getBOMUsageReport(req: Request, res: Response): void
```

**Flutter model classes to remove from `lib/data/models/report.dart`:**
- `BomUsageRow` (line 1142) — fields: `bomId`, `bomName`, `parentItemName`, `usageCount`, `lastUsedDate`, `totalComponents`, `status`
- `BomUsageReport` (line 1172) — fields: `rows`

**l10n keys to remove:**
- `reportsBomusage`
- `reportsAllitems`
- `reportsParentitem`
- `reportsTotalcomponents`
- `reportsUsagecount`
- `reportsLastused`

**CSV builder to remove:**
- `buildBomUsageCsv` (line 1003)

**Provider to remove:**
- `bomUsageReportProvider`
- `reportBomFromDateProvider`
- `reportBomToDateProvider`

---

### 2.12 Expenses Report

**Overlap:** Expense data (date, amount, category, status)

**Files to delete:**
- `lib/features/reports/expenses_report_screen.dart`
- Server: `GET /reports/expenses` endpoint

**Server function signature:**
```typescript
// server/src/models/Reports.ts:1159
function getExpenseReport(startDate: string, endDate: string, category?: string, db?: Database.Database)

// server/src/controllers/reportsController.ts:233
function getExpensesReport(req: Request, res: Response): void
```

**Flutter model classes to remove from `lib/data/models/report.dart`:**
- `ExpensesReportRow` (line 858) — fields: `id`, `expenseNo`, `expenseCategory`, `description`, `amount`, `expenseDate`, `paymentMethod`, `referenceNo`, `vendorName`, `project`, `status`
- `ExpenseCategoryBreakdown` (line 924) — fields: `category`, `count`, `totalAmount`
- `ExpensesReportSummary` (line 924) — fields: `totalAmount`, `totalExpenses`, `averageAmount`
- `ExpensesReport` (line 924) — fields: `rows`, `summary`, `categoryBreakdown`

**l10n keys to remove:**
- `reportsExpensesreport`
- `reportsExpensesbycategory`
- `reportsAverageexpense`
- `reportsTotalexpenses`
- `reportsTotalrecords`

**CSV builder:** The existing `buildExpensesCsv` (line 360) takes `List<Expense>` (from the module screen), NOT the report. Do NOT remove it. The expenses report does not have its own CSV builder.

**Provider to remove:**
- `expensesReportProvider`
- `reportExpensesFromDateProvider`
- `reportExpensesToDateProvider`
- `reportExpensesCategoryProvider`

---

## 3. Unique Reports — KEEP (10 reports)

### 3.1 Financial Reports (4)

| Report | Endpoint | Model Class | Key Fields |
|---|---|---|---|
| profit-loss | GET /reports/profit-loss | `ProfitLossReport` | `startDate`, `endDate`, `totalRevenue`, `totalCogs`, `grossProfit`, `expenses[]`, `totalExpenses`, `netProfit`, `grossProfitMargin`, `netProfitMargin` |
| balance-sheet | GET /reports/balance-sheet | `BalanceSheetReport` | `asOfDate`, `assets{}`, `liabilities{}`, `equity{}`, `totals{}` |
| cash-flow | GET /reports/cash-flow | `CashFlowReport` | `startDate`, `endDate`, `totalInflow`, `totalOutflow`, `netCashFlow` |
| cash-reconciliation | GET /reports/cash-reconciliation | `CashReconciliation` | `date`, `accounts[]`, `summary{}` |

### 3.2 Accounts Receivable (5)

| Report | Endpoint | Model Class | Key Fields |
|---|---|---|---|
| ar-aging | GET /reports/ar-aging | `ArAgingReport` | `asOfDate`, `agingBuckets[]`, `summary{}` |
| ar-summary | GET /reports/ar-summary | `ArSummaryReport` | `asOfDate`, `totalReceivables`, `buckets[]` |
| customer-statements | GET /reports/customer-statements | `CustomerStatementRow[]` | `customerId`, `customerName`, `openingBalance`, `totalDebits`, `totalCredits`, `closingBalance` |
| top-debtors | GET /reports/top-debtors | `TopDebtorRow[]` | `customerName`, `totalOutstanding`, `overdueAmount` |
| dso | GET /reports/dso | `DSOMetric` | `dso`, `avgReceivables`, `totalCreditSales`, `totalSales`, `totalAR`, `avgInvoiceValue` |

### 3.3 Accounts Payable (1)

| Report | Endpoint | Model Class | Key Fields |
|---|---|---|---|
| ap-aging | GET /reports/ap-aging | `ApAgingReport` | `asOfDate`, `agingBuckets[]`, `summary{}` |

---

## 4. Missing Reports — PORT (5 reports)

### 4.1 Trial Balance

**Server endpoint:** `GET /reports/trial-balance`  
**Query params:** `asOfDate` (optional, defaults to today)  
**Category:** Accounting (NEW)

**Server function signatures:**
```typescript
// server/src/models/Reports.ts:711
function getTrialBalance(asOfDate: string, db: Database.Database)

// server/src/controllers/reportsController.ts:243
function getTrialBalanceReport(req: Request, res: Response): void
```

**Response shape:**
```json
{
  "asOfDate": "2026-08-19",
  "accounts": [
    {
      "account_code": "1000",
      "account_name": "Cash",
      "account_type": "asset",
      "total_debit": 50000,
      "total_credit": 30000,
      "balance": 20000,
      "is_zero": false
    }
  ],
  "total_debit": 50000,
  "total_credit": 50000,
  "balanced": true,
  "note": "Built from chart_of_accounts..."
}
```

**Flutter model to create:**
```dart
class TrialBalanceAccount {
  final String accountCode;
  final String accountName;
  final String accountType;
  final num totalDebit;
  final num totalCredit;
  final num balance;
  final bool isZero;
}

class TrialBalanceReport {
  final String asOfDate;
  final List<TrialBalanceAccount> accounts;
  final num totalDebit;
  final num totalCredit;
  final bool balanced;
  final String note;
}
```

**l10n keys to add:**
- `reportsTrialbalance` → "Trial Balance"
- `reportsAccountcode` → "Account Code"
- `reportsAccountname` → "Account Name"
- `reportsAccounttype` → "Account Type"
- `reportsTotaldebit` → "Total Debit"
- `reportsTotalcredit` → "Total Credit"
- `reportsBalanced` → "Balanced"

**CSV builder:** Yes (grid-based)

---

### 4.2 General Ledger

**Server endpoint:** `GET /reports/general-ledger`  
**Query params:** `startDate` (required), `endDate` (required)  
**Category:** Accounting (NEW)

**Server function signatures:**
```typescript
// server/src/models/Reports.ts:753
function getGeneralLedger(startDate: string, endDate: string, db: Database.Database)

// server/src/controllers/reportsController.ts:250
function getGeneralLedgerReport(req: Request, res: Response): void
```

**Response shape:** Returns `customer_ledger` rows:
```json
[
  {
    "id": 1,
    "customer_id": 1,
    "transaction_type": "INVOICE",
    "reference_no": "INV-001",
    "debit": 1000,
    "credit": 0,
    "balance": 1000,
    "transaction_date": "2026-08-01",
    "remarks": "Sale to customer"
  }
]
```

**Flutter model to create:**
```dart
class GeneralLedgerRow {
  final int id;
  final int? customerId;
  final String transactionType;
  final String referenceNo;
  final num debit;
  final num credit;
  final num balance;
  final String transactionDate;
  final String? remarks;
}
```

**l10n keys to add:**
- `reportsGeneralledger` → "General Ledger"
- `reportsDebit` → "Debit"
- `reportsCredit` → "Credit"
- `reportsReferenceno` → "Reference No"
- `reportsTransactiontype` → "Transaction Type"

**CSV builder:** Yes (grid-based)

---

### 4.3 Income Statement

**Server endpoint:** `GET /reports/income-statement`  
**Query params:** `startDate` (required), `endDate` (required)  
**Category:** Accounting (NEW)

**Server function signatures:**
```typescript
// server/src/models/Reports.ts:694
function getIncomeStatement(startDate: string, endDate: string, db: Database.Database)

// server/src/controllers/reportsController.ts:265
function getIncomeStatementReport(req: Request, res: Response): void
```

**Response shape:**
```json
{
  "startDate": "2026-01-01",
  "endDate": "2026-08-19",
  "revenue": 100000,
  "cogs": 60000,
  "expenses": 20000,
  "netIncome": 20000,
  "grossProfit": 40000
}
```

**Flutter model to create:**
```dart
class IncomeStatementReport {
  final String startDate;
  final String endDate;
  final num revenue;
  final num cogs;
  final num expenses;
  final num netIncome;
  final num grossProfit;
}
```

**l10n keys to add:**
- `reportsIncomestatement` → "Income Statement"
- `reportsRevenue` → "Revenue"
- `reportsCogs` → "Cost of Goods Sold"
- `reportsNetincome` → "Net Income"

**CSV builder:** No (card-based, not grid)

---

### 4.4 Tax Summary

**Server endpoint:** `GET /reports/tax-summary`  
**Query params:** `startDate` (required), `endDate` (required)  
**Category:** Accounting (NEW)

**Server function signatures:**
```typescript
// server/src/models/Reports.ts:790
function getTaxSummary(startDate: string, endDate: string, db: Database.Database)

// server/src/controllers/reportsController.ts:273
function getTaxSummaryReport(req: Request, res: Response): void
```

**Response shape:**
```json
{
  "total_tax": 15000
}
```

**Flutter model to create:**
```dart
class TaxSummaryReport {
  final num totalTax;
}
```

**l10n keys to add:**
- `reportsTaxsummary` → "Tax Summary"
- `reportsTotaltax` → "Total Tax"

**CSV builder:** No (single value, not grid)

---

### 4.5 Batch Traceability

**Server endpoint:** `GET /reports/batch-traceability/:itemId`  
**Query params:** `itemId` (path param, required)  
**Category:** Inventory Reports (add to existing)

**Server function signatures:**
```typescript
// server/src/models/Reports.ts:426
function getBatchTraceability(db: Database.Database, itemId: number)

// server/src/controllers/reportsController.ts:311
function getBatchTraceabilityReport(req: Request, res: Response): void
```

**Response shape:**
```json
{
  "item": {
    "id": 1,
    "item_code": "ITEM-001",
    "item_name": "Widget",
    "unit_of_measure": "pcs"
  },
  "currentStock": [
    { "warehouse_id": 1, "quantity": 100 }
  ],
  "movements": [
    {
      "movement_no": "MOV-001",
      "movement_type": "IN",
      "quantity": 50,
      "movement_date": "2026-08-01",
      "reference_doctype": "PURCHASE",
      "reference_docno": "PO-001",
      "remarks": "Received",
      "warehouse_name": "Main Warehouse"
    }
  ],
  "summary": {
    "warehousesWithStock": 2,
    "recentMovements": 10
  }
}
```

**Flutter model to create:**
```dart
class BatchTraceabilityItem {
  final int id;
  final String itemCode;
  final String itemName;
  final String unitOfMeasure;
}

class BatchTraceabilityStock {
  final int warehouseId;
  final num quantity;
}

class BatchTraceabilityMovement {
  final String movementNo;
  final String movementType;
  final num quantity;
  final String movementDate;
  final String referenceDoctype;
  final String referenceDocno;
  final String? remarks;
  final String warehouseName;
}

class BatchTraceabilityReport {
  final BatchTraceabilityItem item;
  final List<BatchTraceabilityStock> currentStock;
  final List<BatchTraceabilityMovement> movements;
  final int warehousesWithStock;
  final int recentMovements;
}
```

**l10n keys to add:**
- `reportsBatchtraceability` → "Batch Traceability"
- `reportsWarehouseswithstock` → "Warehouses with Stock"
- `reportsRecentmovements` → "Recent Movements"

**CSV builder:** Yes (grid-based for movements)

---

## 5. Final Report Structure

After cleanup, the reports section will have **15 reports** across **7 categories**:

### 5.1 Financial Reports (4)
- profit-loss
- balance-sheet
- cash-flow
- cash-reconciliation

### 5.2 Accounts Receivable (5)
- ar-summary
- ar-aging
- customer-statements
- top-debtors
- dso

### 5.3 Accounts Payable (1)
- ap-aging

### 5.4 Inventory Reports (1)
- batch-traceability (NEW)

### 5.5 Accounting Reports (NEW — 4)
- trial-balance (NEW)
- general-ledger (NEW)
- income-statement (NEW)
- tax-summary (NEW)

### 5.6 ~~Sales Reports~~ (REMOVED — 0)
### 5.7 ~~Purchase Reports~~ (REMOVED — 0)
### 5.8 ~~Production Reports~~ (REMOVED — 0)

---

## 6. Implementation Checklist

### Phase 1: Remove Duplicate Reports

For each of the 12 reports:

- [ ] Delete `lib/features/reports/<report>_screen.dart`
- [ ] Delete `lib/features/reports/<report>_detail_dialog.dart` (if exists)
- [ ] Remove provider from `lib/features/reports/report_providers.dart`
- [ ] Remove from `lib/features/reports/reports_dashboard_screen.dart` (reportTitles + _ReportEntry)
- [ ] Remove from `lib/app.dart` (router case + import)
- [ ] Remove CSV builder from `lib/core/utils/csv_export.dart`
- [ ] Remove unused imports from `lib/core/utils/csv_export.dart`
- [ ] Remove model classes from `lib/data/models/report.dart`
- [ ] Remove repository method from `lib/data/repositories/report_repository.dart`
- [ ] Remove route from `server/src/routes/reports.ts`
- [ ] Remove controller function from `server/src/controllers/reportsController.ts`
- [ ] Remove model function from `server/src/models/Reports.ts`
- [ ] Remove from `server/src/models/Reports.ts` export list
- [ ] Remove from `server/src/controllers/reportsController.ts` export list
- [ ] Remove date range providers from `_reportRangePairs` in `lib/features/reports/report_providers.dart`
- [ ] Remove unused l10n keys from `lib/l10n/en.arb`
- [ ] Remove unused l10n keys from `lib/l10n/ur.arb`
- [ ] Run `flutter gen-l10n`
- [ ] Run `flutter analyze`
- [ ] Run `cd server && npx tsc --noEmit`

### Phase 2: Port Missing Reports

For each of the 5 reports:

- [ ] Add model classes to `lib/data/models/report.dart`
- [ ] Add repository method to `lib/data/repositories/report_repository.dart`
- [ ] Add provider to `lib/features/reports/report_providers.dart`
- [ ] Create screen in `lib/features/reports/`
- [ ] Add CSV export builder to `lib/core/utils/csv_export.dart` (if grid-based)
- [ ] Register in `lib/app.dart` (router case + import)
- [ ] Register in `lib/features/reports/reports_dashboard_screen.dart` (reportTitles + _ReportEntry)
- [ ] Add l10n keys to `lib/l10n/en.arb`
- [ ] Add l10n keys to `lib/l10n/ur.arb`
- [ ] Run `flutter gen-l10n`
- [ ] Run `flutter analyze`

### Phase 3: Update Dashboard

- [ ] Remove empty categories (Sales, Purchase, Production)
- [ ] Add Accounting category with 4 reports
- [ ] Add batch-traceability to Inventory Reports
- [ ] Verify final category structure matches Section 5

### Phase 4: Verification

- [ ] `flutter analyze` — clean
- [ ] `flutter test` — all pass
- [ ] `cd server && npx tsc --noEmit` — clean
- [ ] `cd server && npx jest --forceExit` — all pass
- [ ] Manual testing: navigate to each report, verify data loads
- [ ] Manual testing: CSV export works on grid-based reports

---

## 7. Files Summary

### Files to DELETE (22 files)

**Flutter files (22):**
- `lib/features/reports/sales_summary_report_screen.dart`
- `lib/features/reports/sales_by_customer_report_screen.dart`
- `lib/features/reports/sales_by_customer_detail_dialog.dart`
- `lib/features/reports/sales_by_item_report_screen.dart`
- `lib/features/reports/sales_by_item_detail_dialog.dart`
- `lib/features/reports/stock_level_report_screen.dart`
- `lib/features/reports/stock_level_detail_dialog.dart`
- `lib/features/reports/low_stock_report_screen.dart`
- `lib/features/reports/low_stock_detail_dialog.dart`
- `lib/features/reports/stock_valuation_report_screen.dart`
- `lib/features/reports/stock_valuation_detail_dialog.dart`
- `lib/features/reports/inventory_movement_report_screen.dart`
- `lib/features/reports/inventory_movement_detail_dialog.dart`
- `lib/features/reports/purchase_summary_report_screen.dart`
- `lib/features/reports/purchase_summary_detail_dialog.dart`
- `lib/features/reports/supplier_analysis_report_screen.dart`
- `lib/features/reports/supplier_analysis_detail_dialog.dart`
- `lib/features/reports/production_summary_report_screen.dart`
- `lib/features/reports/production_summary_detail_dialog.dart`
- `lib/features/reports/bom_usage_report_screen.dart`
- `lib/features/reports/bom_usage_detail_dialog.dart`
- `lib/features/reports/expenses_report_screen.dart`

### Files to CREATE (5 files)

- `lib/features/reports/trial_balance_report_screen.dart`
- `lib/features/reports/general_ledger_report_screen.dart`
- `lib/features/reports/income_statement_report_screen.dart`
- `lib/features/reports/tax_summary_report_screen.dart`
- `lib/features/reports/batch_traceability_report_screen.dart`

### Files to MODIFY (8 files)

- `lib/data/models/report.dart` — remove 12 model classes, add 5 new model classes
- `lib/data/repositories/report_repository.dart` — remove 12 methods, add 5 new methods
- `lib/features/reports/report_providers.dart` — remove 12 providers, add 5 new providers
- `lib/features/reports/reports_dashboard_screen.dart` — update reportTitles + _reportCategories
- `lib/app.dart` — remove 12 router cases + imports, add 5 new router cases + imports
- `lib/core/utils/csv_export.dart` — remove 12 CSV builders, add 3 new CSV builders
- `lib/l10n/en.arb` — remove ~60 keys, add ~30 new keys
- `lib/l10n/ur.arb` — remove ~60 keys, add ~30 new keys

### Server Files to MODIFY (3 files)

- `server/src/routes/reports.ts` — remove 12 route registrations
- `server/src/controllers/reportsController.ts` — remove 12 controller functions
- `server/src/models/Reports.ts` — remove 12 model functions + update exports
