# Graph Report - /media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server  (2026-08-24)

## Corpus Check
- 176 files · ~180,067 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1246 nodes · 2203 edges · 88 communities detected
- Extraction: 64% EXTRACTED · 36% INFERRED · 0% AMBIGUOUS · INFERRED: 800 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Community 0|Community 0]]
- [[_COMMUNITY_Community 1|Community 1]]
- [[_COMMUNITY_Community 2|Community 2]]
- [[_COMMUNITY_Community 3|Community 3]]
- [[_COMMUNITY_Community 4|Community 4]]
- [[_COMMUNITY_Community 5|Community 5]]
- [[_COMMUNITY_Community 6|Community 6]]
- [[_COMMUNITY_Community 7|Community 7]]
- [[_COMMUNITY_Community 8|Community 8]]
- [[_COMMUNITY_Community 9|Community 9]]
- [[_COMMUNITY_Community 10|Community 10]]
- [[_COMMUNITY_Community 11|Community 11]]
- [[_COMMUNITY_Community 12|Community 12]]
- [[_COMMUNITY_Community 13|Community 13]]
- [[_COMMUNITY_Community 14|Community 14]]
- [[_COMMUNITY_Community 15|Community 15]]
- [[_COMMUNITY_Community 16|Community 16]]
- [[_COMMUNITY_Community 17|Community 17]]
- [[_COMMUNITY_Community 18|Community 18]]
- [[_COMMUNITY_Community 19|Community 19]]
- [[_COMMUNITY_Community 20|Community 20]]
- [[_COMMUNITY_Community 21|Community 21]]
- [[_COMMUNITY_Community 22|Community 22]]
- [[_COMMUNITY_Community 23|Community 23]]
- [[_COMMUNITY_Community 24|Community 24]]
- [[_COMMUNITY_Community 25|Community 25]]
- [[_COMMUNITY_Community 26|Community 26]]
- [[_COMMUNITY_Community 27|Community 27]]
- [[_COMMUNITY_Community 28|Community 28]]
- [[_COMMUNITY_Community 29|Community 29]]
- [[_COMMUNITY_Community 30|Community 30]]
- [[_COMMUNITY_Community 31|Community 31]]
- [[_COMMUNITY_Community 32|Community 32]]
- [[_COMMUNITY_Community 33|Community 33]]
- [[_COMMUNITY_Community 34|Community 34]]
- [[_COMMUNITY_Community 35|Community 35]]
- [[_COMMUNITY_Community 36|Community 36]]
- [[_COMMUNITY_Community 37|Community 37]]
- [[_COMMUNITY_Community 38|Community 38]]
- [[_COMMUNITY_Community 39|Community 39]]
- [[_COMMUNITY_Community 40|Community 40]]
- [[_COMMUNITY_Community 41|Community 41]]
- [[_COMMUNITY_Community 42|Community 42]]
- [[_COMMUNITY_Community 43|Community 43]]
- [[_COMMUNITY_Community 44|Community 44]]
- [[_COMMUNITY_Community 45|Community 45]]
- [[_COMMUNITY_Community 46|Community 46]]
- [[_COMMUNITY_Community 47|Community 47]]
- [[_COMMUNITY_Community 48|Community 48]]
- [[_COMMUNITY_Community 49|Community 49]]
- [[_COMMUNITY_Community 50|Community 50]]
- [[_COMMUNITY_Community 51|Community 51]]
- [[_COMMUNITY_Community 52|Community 52]]
- [[_COMMUNITY_Community 53|Community 53]]
- [[_COMMUNITY_Community 54|Community 54]]
- [[_COMMUNITY_Community 55|Community 55]]
- [[_COMMUNITY_Community 56|Community 56]]
- [[_COMMUNITY_Community 57|Community 57]]
- [[_COMMUNITY_Community 58|Community 58]]
- [[_COMMUNITY_Community 59|Community 59]]
- [[_COMMUNITY_Community 60|Community 60]]
- [[_COMMUNITY_Community 61|Community 61]]
- [[_COMMUNITY_Community 62|Community 62]]
- [[_COMMUNITY_Community 63|Community 63]]
- [[_COMMUNITY_Community 64|Community 64]]
- [[_COMMUNITY_Community 65|Community 65]]
- [[_COMMUNITY_Community 66|Community 66]]
- [[_COMMUNITY_Community 67|Community 67]]
- [[_COMMUNITY_Community 68|Community 68]]
- [[_COMMUNITY_Community 69|Community 69]]
- [[_COMMUNITY_Community 70|Community 70]]
- [[_COMMUNITY_Community 71|Community 71]]
- [[_COMMUNITY_Community 72|Community 72]]
- [[_COMMUNITY_Community 73|Community 73]]
- [[_COMMUNITY_Community 74|Community 74]]
- [[_COMMUNITY_Community 75|Community 75]]
- [[_COMMUNITY_Community 76|Community 76]]
- [[_COMMUNITY_Community 77|Community 77]]
- [[_COMMUNITY_Community 78|Community 78]]
- [[_COMMUNITY_Community 79|Community 79]]
- [[_COMMUNITY_Community 80|Community 80]]
- [[_COMMUNITY_Community 81|Community 81]]
- [[_COMMUNITY_Community 82|Community 82]]
- [[_COMMUNITY_Community 83|Community 83]]
- [[_COMMUNITY_Community 84|Community 84]]
- [[_COMMUNITY_Community 85|Community 85]]
- [[_COMMUNITY_Community 86|Community 86]]
- [[_COMMUNITY_Community 87|Community 87]]

## God Nodes (most connected - your core abstractions)
1. `run()` - 159 edges
2. `getQueryParam()` - 45 edges
3. `log()` - 41 edges
4. `logCRUD()` - 41 edges
5. `InvoiceModel` - 35 edges
6. `AccountingService` - 27 edges
7. `PurchaseOrderModel` - 20 edges
8. `getQueryInteger()` - 19 edges
9. `sanitizeSortParams()` - 19 edges
10. `getRouteParam()` - 18 edges

## Surprising Connections (you probably didn't know these)
- `repairUnbatchedStock()` --calls--> `run()`  [INFERRED]
  /media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/scripts/repair-stock.ts → /media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/src/__tests__/glPoCommitment.test.ts
- `repairOrphanedBatches()` --calls--> `run()`  [INFERRED]
  /media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/scripts/repair-stock.ts → /media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/src/__tests__/glPoCommitment.test.ts
- `runStockCoverageReconciliation()` --calls--> `run()`  [INFERRED]
  /media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/src/config/database.ts → /media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/src/__tests__/glPoCommitment.test.ts
- `runProductionBOMIdMigration()` --calls--> `run()`  [INFERRED]
  /media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/src/config/database.ts → /media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/src/__tests__/glPoCommitment.test.ts
- `runProductionOverheadMigration()` --calls--> `run()`  [INFERRED]
  /media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/src/config/database.ts → /media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/src/__tests__/glPoCommitment.test.ts

## Communities

### Community 0 - "Community 0"
Cohesion: 0.02
Nodes (35): createFixture(), CustomerModel, safeSortBy(), deleteCustomer(), seedBalance(), seedBatch(), seedCustomer(), seedExpense() (+27 more)

### Community 1 - "Community 1"
Cohesion: 0.03
Nodes (76): logCRUD(), newCorrelationId(), createCustomer(), getCustomer(), getCustomerStatement(), recalculateAllBalances(), updateCustomer(), addEmployeeDocument() (+68 more)

### Community 2 - "Community 2"
Cohesion: 0.03
Nodes (29): ActivityLogModel, localDateToUtcBound(), cleanupLogs(), exportLogs(), getActivityLogs(), getActivityStats(), getEntityActivity(), getRecentActivity() (+21 more)

### Community 3 - "Community 3"
Cohesion: 0.03
Nodes (26): addColumnIfMissing(), backfillPaymentsPurchaseOrderId(), columnExists(), createDefaultUser(), createDefaultWarehouse(), ensureMigrationsTable(), fileChecksum(), getStockDiscrepancies() (+18 more)

### Community 4 - "Community 4"
Cohesion: 0.06
Nodes (49): ActivityLoggerService, capSnapshot(), cleanupLogs(), disposeLogger(), flushLogs(), getEntityLogs(), getRecentLogs(), getUserLogs() (+41 more)

### Community 5 - "Community 5"
Cohesion: 0.04
Nodes (17): ProductionModel, PurchaseReturnModel, voidPurchaseReturn(), QuotationModel, cancelSalesOrder(), deleteQuotation(), deleteSalesOrder(), getInvoicesByQuotation() (+9 more)

### Community 6 - "Community 6"
Cohesion: 0.07
Nodes (43): getUserActivity(), create(), createTemplate(), duplicate(), findById(), findByUser(), getTemplates(), markRun() (+35 more)

### Community 7 - "Community 7"
Cohesion: 0.07
Nodes (53): deleteSeasonalEventHandler(), generateForecasts(), getAccuracyData(), getAccuracyDetail(), getDashboard(), getDemand(), getExport(), getModelConfigHandler() (+45 more)

### Community 8 - "Community 8"
Cohesion: 0.09
Nodes (38): getAllBOMs(), getCustomerLedger(), getCustomers(), getExpenses(), getItems(), getPhysicalCounts(), getStockBalances(), getStockMovements() (+30 more)

### Community 9 - "Community 9"
Cohesion: 0.06
Nodes (16): getCustomerBalance(), getInvoicePayments(), getPurchasePayments(), PurchaseOrderModel, addLineItem(), createGoodsReceipt(), deleteLineItem(), deletePurchaseOrder() (+8 more)

### Community 10 - "Community 10"
Cohesion: 0.13
Nodes (34): closePeriod(), getAccount(), getAccountBalance(), getCurrentPeriod(), getPeriod(), getReconciliation(), isValidIsoDate(), listAccountBalances() (+26 more)

### Community 11 - "Community 11"
Cohesion: 0.08
Nodes (30): getCashAccountTotals(), getCashPosition(), columnExistsSafe(), computeAPAging(), getAPAgingReport(), getBalanceSheet(), getBatchTraceability(), getCashReconciliation() (+22 more)

### Community 12 - "Community 12"
Cohesion: 0.07
Nodes (12): collectFlows(), getOpeningBalances(), isValidPaymentMethod(), normalizeCashMethod(), saveOpeningBalance(), getCashOpeningBalances(), getKPI(), getKPIBatch() (+4 more)

### Community 13 - "Community 13"
Cohesion: 0.09
Nodes (27): createCategory(), deleteCategory(), deleteExpense(), generateExpenseNo(), getAllCategories(), getByCategory(), getByDateRange(), getById() (+19 more)

### Community 14 - "Community 14"
Cohesion: 0.1
Nodes (15): activityLogBackstop(), newCorrelationId(), authenticateToken(), generateToken(), requireAdmin(), BOMModel, createBOM(), deleteBOM() (+7 more)

### Community 15 - "Community 15"
Cohesion: 0.11
Nodes (17): getExpenseSummary(), getSalesSummary(), periodWhereClause(), todayISO(), getPreferences(), isIsoDate(), requireUser(), updatePreferences() (+9 more)

### Community 16 - "Community 16"
Cohesion: 0.17
Nodes (2): AccountingService, getGlBalances()

### Community 17 - "Community 17"
Cohesion: 0.13
Nodes (8): UserModel, createUser(), deleteUser(), getUser(), getUsers(), resetPassword(), toggleUserStatus(), updateUser()

### Community 18 - "Community 18"
Cohesion: 0.1
Nodes (13): createDraft(), deleteDraft(), getDraftById(), getDraftBySession(), getInvoiceWithCustomer(), updateDraft(), createDraft(), deleteDraft() (+5 more)

### Community 19 - "Community 19"
Cohesion: 0.14
Nodes (14): addCurrency(), computeInvoiceTotal(), computeLineAmount(), decomposeLineAmount(), multiplyCurrency(), parseCurrency(), roundCurrency(), subtractCurrency() (+6 more)

### Community 20 - "Community 20"
Cohesion: 0.12
Nodes (7): getProductionSummaryByItem(), PurchaseModel, getPurchase(), getPurchaseSummaryByDateRange(), getPurchaseSummaryByItem(), getTopSuppliers(), voidPurchase()

### Community 21 - "Community 21"
Cohesion: 0.18
Nodes (17): getSearch(), resolvePermissionContext(), search(), searchBOMs(), searchCustomers(), searchEmployees(), searchExpenses(), searchInvoices() (+9 more)

### Community 22 - "Community 22"
Cohesion: 0.16
Nodes (15): create(), deleteRole(), getAllPermissions(), getById(), getByName(), getPermissionsForRole(), update(), updatePermissions() (+7 more)

### Community 23 - "Community 23"
Cohesion: 0.16
Nodes (12): buildIntegrationStatus(), getByKey(), getIntegrationKeys(), updateBulk(), updateIntegrationSetting(), upsert(), getIntegrationSettings(), getSetting() (+4 more)

### Community 24 - "Community 24"
Cohesion: 0.27
Nodes (10): createLayout(), deactivateAll(), deleteLayout(), duplicateLayout(), getActiveLayout(), getLayoutById(), parseRow(), renameLayout() (+2 more)

### Community 25 - "Community 25"
Cohesion: 0.22
Nodes (0): 

### Community 26 - "Community 26"
Cohesion: 0.67
Nodes (5): computeLineAmount(), main(), parseCurrency(), resolveDbPath(), roundCurrency()

### Community 27 - "Community 27"
Cohesion: 0.53
Nodes (5): ensureBackupDir(), lastBackupAgeMs(), pruneRetention(), runBackup(), startBackupScheduler()

### Community 28 - "Community 28"
Cohesion: 0.7
Nodes (4): validateZod(), validateZodBody(), validateZodParams(), validateZodQuery()

### Community 29 - "Community 29"
Cohesion: 0.5
Nodes (2): shutdownRateLimiters(), globalTeardown()

### Community 30 - "Community 30"
Cohesion: 0.5
Nodes (0): 

### Community 31 - "Community 31"
Cohesion: 0.67
Nodes (0): 

### Community 32 - "Community 32"
Cohesion: 0.67
Nodes (0): 

### Community 33 - "Community 33"
Cohesion: 0.67
Nodes (0): 

### Community 34 - "Community 34"
Cohesion: 0.67
Nodes (0): 

### Community 35 - "Community 35"
Cohesion: 0.67
Nodes (0): 

### Community 36 - "Community 36"
Cohesion: 0.67
Nodes (0): 

### Community 37 - "Community 37"
Cohesion: 1.0
Nodes (0): 

### Community 38 - "Community 38"
Cohesion: 1.0
Nodes (0): 

### Community 39 - "Community 39"
Cohesion: 1.0
Nodes (0): 

### Community 40 - "Community 40"
Cohesion: 1.0
Nodes (0): 

### Community 41 - "Community 41"
Cohesion: 1.0
Nodes (0): 

### Community 42 - "Community 42"
Cohesion: 1.0
Nodes (0): 

### Community 43 - "Community 43"
Cohesion: 1.0
Nodes (0): 

### Community 44 - "Community 44"
Cohesion: 1.0
Nodes (0): 

### Community 45 - "Community 45"
Cohesion: 1.0
Nodes (0): 

### Community 46 - "Community 46"
Cohesion: 1.0
Nodes (0): 

### Community 47 - "Community 47"
Cohesion: 1.0
Nodes (0): 

### Community 48 - "Community 48"
Cohesion: 1.0
Nodes (0): 

### Community 49 - "Community 49"
Cohesion: 1.0
Nodes (0): 

### Community 50 - "Community 50"
Cohesion: 1.0
Nodes (0): 

### Community 51 - "Community 51"
Cohesion: 1.0
Nodes (0): 

### Community 52 - "Community 52"
Cohesion: 1.0
Nodes (0): 

### Community 53 - "Community 53"
Cohesion: 1.0
Nodes (0): 

### Community 54 - "Community 54"
Cohesion: 1.0
Nodes (0): 

### Community 55 - "Community 55"
Cohesion: 1.0
Nodes (0): 

### Community 56 - "Community 56"
Cohesion: 1.0
Nodes (0): 

### Community 57 - "Community 57"
Cohesion: 1.0
Nodes (0): 

### Community 58 - "Community 58"
Cohesion: 1.0
Nodes (0): 

### Community 59 - "Community 59"
Cohesion: 1.0
Nodes (0): 

### Community 60 - "Community 60"
Cohesion: 1.0
Nodes (0): 

### Community 61 - "Community 61"
Cohesion: 1.0
Nodes (0): 

### Community 62 - "Community 62"
Cohesion: 1.0
Nodes (0): 

### Community 63 - "Community 63"
Cohesion: 1.0
Nodes (0): 

### Community 64 - "Community 64"
Cohesion: 1.0
Nodes (0): 

### Community 65 - "Community 65"
Cohesion: 1.0
Nodes (0): 

### Community 66 - "Community 66"
Cohesion: 1.0
Nodes (0): 

### Community 67 - "Community 67"
Cohesion: 1.0
Nodes (0): 

### Community 68 - "Community 68"
Cohesion: 1.0
Nodes (0): 

### Community 69 - "Community 69"
Cohesion: 1.0
Nodes (0): 

### Community 70 - "Community 70"
Cohesion: 1.0
Nodes (0): 

### Community 71 - "Community 71"
Cohesion: 1.0
Nodes (0): 

### Community 72 - "Community 72"
Cohesion: 1.0
Nodes (0): 

### Community 73 - "Community 73"
Cohesion: 1.0
Nodes (0): 

### Community 74 - "Community 74"
Cohesion: 1.0
Nodes (0): 

### Community 75 - "Community 75"
Cohesion: 1.0
Nodes (0): 

### Community 76 - "Community 76"
Cohesion: 1.0
Nodes (0): 

### Community 77 - "Community 77"
Cohesion: 1.0
Nodes (0): 

### Community 78 - "Community 78"
Cohesion: 1.0
Nodes (0): 

### Community 79 - "Community 79"
Cohesion: 1.0
Nodes (0): 

### Community 80 - "Community 80"
Cohesion: 1.0
Nodes (0): 

### Community 81 - "Community 81"
Cohesion: 1.0
Nodes (0): 

### Community 82 - "Community 82"
Cohesion: 1.0
Nodes (0): 

### Community 83 - "Community 83"
Cohesion: 1.0
Nodes (0): 

### Community 84 - "Community 84"
Cohesion: 1.0
Nodes (0): 

### Community 85 - "Community 85"
Cohesion: 1.0
Nodes (0): 

### Community 86 - "Community 86"
Cohesion: 1.0
Nodes (0): 

### Community 87 - "Community 87"
Cohesion: 1.0
Nodes (0): 

## Knowledge Gaps
- **Thin community `Community 37`** (2 nodes): `requirePermission.ts`, `requirePermission()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 38`** (2 nodes): `upload.ts`, `documentFilter()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 39`** (2 nodes): `toLocalDate()`, `activityLog.test.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 40`** (2 nodes): `fingerprint()`, `bootIdempotency.test.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 41`** (2 nodes): `search.test.ts`, `createFixture()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 42`** (2 nodes): `setup.ts`, `cleanupTestDb()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 43`** (1 nodes): `dbg-flush.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 44`** (1 nodes): `dbg-pay01.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 45`** (1 nodes): `eslint.config.js`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 46`** (1 nodes): `jest.config.js`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 47`** (1 nodes): `cleanup-e2e-test-data.js`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 48`** (1 nodes): `accounting.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 49`** (1 nodes): `activityLog.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 50`** (1 nodes): `adminHealth.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 51`** (1 nodes): `auth.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 52`** (1 nodes): `bom.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 53`** (1 nodes): `customers.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 54`** (1 nodes): `customReports.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 55`** (1 nodes): `dashboard.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 56`** (1 nodes): `employees.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 57`** (1 nodes): `expenses.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 58`** (1 nodes): `forecasts.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 59`** (1 nodes): `integrations.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 60`** (1 nodes): `inventory.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 61`** (1 nodes): `invoices.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 62`** (1 nodes): `mobileInvoices.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 63`** (1 nodes): `payments.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 64`** (1 nodes): `pos.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 65`** (1 nodes): `preferences.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 66`** (1 nodes): `production.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 67`** (1 nodes): `purchaseOrders.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 68`** (1 nodes): `purchaseReturns.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 69`** (1 nodes): `purchases.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 70`** (1 nodes): `reports.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 71`** (1 nodes): `roles.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 72`** (1 nodes): `sales.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 73`** (1 nodes): `search.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 74`** (1 nodes): `settings.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 75`** (1 nodes): `suppliers.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 76`** (1 nodes): `users.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 77`** (1 nodes): `fix-duplicate-purchase.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 78`** (1 nodes): `express.d.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 79`** (1 nodes): `index.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 80`** (1 nodes): `search.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 81`** (1 nodes): `logger.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 82`** (1 nodes): `backupWal.test.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 83`** (1 nodes): `cashTruth.test.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 84`** (1 nodes): `envHardening.test.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 85`** (1 nodes): `models.test.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 86`** (1 nodes): `userPreferences.test.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 87`** (1 nodes): `weekMath.test.ts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `run()` connect `Community 0` to `Community 1`, `Community 2`, `Community 3`, `Community 4`, `Community 5`, `Community 6`, `Community 7`, `Community 9`, `Community 10`, `Community 12`, `Community 13`, `Community 14`, `Community 15`, `Community 16`, `Community 17`, `Community 18`, `Community 19`, `Community 22`, `Community 23`, `Community 24`, `Community 27`?**
  _High betweenness centrality (0.519) - this node is a cross-community bridge._
- **Why does `getQueryParam()` connect `Community 8` to `Community 1`, `Community 2`, `Community 10`, `Community 12`, `Community 13`, `Community 18`, `Community 20`?**
  _High betweenness centrality (0.090) - this node is a cross-community bridge._
- **Why does `getNextSequenceNumber()` connect `Community 1` to `Community 0`, `Community 5`, `Community 12`, `Community 13`, `Community 14`, `Community 19`, `Community 20`?**
  _High betweenness centrality (0.071) - this node is a cross-community bridge._
- **Are the 158 inferred relationships involving `run()` (e.g. with `repairUnbatchedStock()` and `repairOrphanedBatches()`) actually correct?**
  _`run()` has 158 INFERRED edges - model-reasoned connections that need verification._
- **Are the 42 inferred relationships involving `getQueryParam()` (e.g. with `listAccountBalances()` and `getAccountBalance()`) actually correct?**
  _`getQueryParam()` has 42 INFERRED edges - model-reasoned connections that need verification._
- **Are the 37 inferred relationships involving `log()` (e.g. with `main()` and `run()`) actually correct?**
  _`log()` has 37 INFERRED edges - model-reasoned connections that need verification._
- **Are the 40 inferred relationships involving `logCRUD()` (e.g. with `openPeriod()` and `closePeriod()`) actually correct?**
  _`logCRUD()` has 40 INFERRED edges - model-reasoned connections that need verification._