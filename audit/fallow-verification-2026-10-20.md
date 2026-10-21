# fallow verification report — 2026-10-20

Scope: every finding from `npx fallow` at the repo root (v3.34.1, schema 14), verified one by one
against the tracked tree, the SQLite DB, the Flutter client, and CI config.

Method: each flagged symbol was re-located with a repo-wide symbol scan (TS/JS corpus only, Dart
excluded — Dart `Customer`/`Item` etc. are unrelated to server TS types), class members were
matched as `<OwnerClass>.<member>` with the owner resolved from the file, and enum values were
checked against live rows in `server/database/erp.db`.

---

## Headline

| Gate | Reported | True positive | False positive |
|---|---|---|---|
| dead-code (318 findings) | 318 | **113** | **205** |
| health (221 findings) | 221 | **84** structural / 137 noise | 137 |
| dupes (163 groups) | 163 | ~34 real families | mostly intra-file / boilerplate |

**The single biggest finding: fallow cannot see property access on a default-imported module
namespace.** Nine modules in `server/src` export functions both by name and through an
`export default { ... }` object, and the route layer consumes them as `ns.handler`. Fallow reports
every one of those named exports as "unused". 37 of fallow's top-ranked "refactoring targets" are
this one pattern.

**Do not apply `fallow fix` blindly.** Its own advice ("Remove 10 unused exports to reduce surface
area (91% dead)") applied to `mobileInvoiceController.ts` would delete the `export` keyword from
live route handlers and break the default-export object — a runtime break in the mobile invoice API.

---

## 1. Unused files (32) → 14 true, 18 false

### True dead (14)

**Stale audit test copies (8)** — `audit/tests/auditRegression{,2,3,4,5,6,7,8}.test.ts`
Their imports (`../app`, `../config/database`, `../services/accountingService`,
`./helpers/invoiceReturnSpec`) do not resolve under `audit/` — the live copies live at
`server/src/__tests__/auditRegression*.test.ts` and are covered by `server/jest.config.js`
(`roots: ['<rootDir>/src']`, `testMatch: ['**/__tests__/**/*.test.ts']`). These files are broken
copies; nothing runs them.

**Orphan CSS (4)** — `styles/global.css`, `styles/rtl.css`, `styles/variables.css`,
`styles/ag-grid-status-cells.css`
Not referenced by any HTML, Dart, JSON or YAML in the repo. `web/index.html` is the stock Flutter
bootstrap; Flutter does not consume CSS.

**Orphan scripts (2)** — `server/scripts/cleanup-e2e-test-data.js`,
`server/scripts/invoice-idempotency-report.cjs`
Zero references anywhere, including docs.

### False positive (18) — invoked by path, never imported

| File | Invoked from |
|---|---|
| `server/scripts/restore-smoke.js` | **`.github/workflows/nightly-backup.yml:54`** — runs in CI |
| `scripts/openspec-archive-guard.js` | `openspec/changes/period-protection-primitive/tasks.md:89` |
| `scripts/unapplied-cash-fixture.test.cjs` | `audit/unapplied-cash-ui-final.md:53` |
| `scripts/openspec-archive-guard.test.js` | test for the guard above |
| `docs/test-migration-order.ts` | `server/src/__tests__/helpers/productionSchema.ts:18`, `openspec/changes/archive/2026-10-10-journal-balance-boot-gate/` |
| `docs/superpowers/verification/unapplied-cash-stage-d.cjs` | `docs/superpowers/plans/2026-10-16-unapplied-customer-payments.md:6` |
| `docs/superpowers/verification/unapplied-customer-payments.cjs` | `audit/unapplied-cash-plan-verification-2026-10-16.md` |
| `server/scripts/apply-customer15-correction.ts` | `audit/CUSTOMER-15-FINAL-REVIEW.md`, `audit/FINDINGS-STATUS.md:653` |
| `server/scripts/rollback-customer15-correction.ts` | same |
| `server/scripts/lib/correctionSafety.ts` | imported by the two above (cascade-hidden) |
| `server/scripts/reconcile-customer-credits.ts` | `audit/credit-reconciliation-2026-10-16.md:13` |
| `server/scripts/run-guarded-tests.cjs` | `audit/credit-reconciliation-2026-10-16.md:92` |
| `server/scripts/verify-invariants-live.ts` | `audit/ACCOUNTING-REMEDIATION-PLAN.md:23`, `audit/FINDINGS-STATUS.md:365,399` |
| `server/scripts/dev/audit-trace.ts` | `openspec/changes/archive/2026-08-23-audit-remediation/tasks.md:6` |
| `server/scripts/fixtures/unapplied-cash-ui.cjs` | imported by `scripts/unapplied-cash-fixture.test.cjs:3` |
| `server/src/scripts/backfill-batches.ts` | `audit/CUSTOMER-15-FINAL-REVIEW.md:311` |
| `server/src/scripts/fix-duplicate-purchase.ts` | `audit/CUSTOMER-15-FINAL-REVIEW.md:298,312`, `server/docs/stock-authority-map.md:39` |
| `server/src/scripts/reconcile-stock-cash.ts` | `audit/CUSTOMER-15-FINAL-REVIEW.md:299,313`, `openspec/changes/archive/2026-08-22-inventory-integrity/proposal.md:36` |

---

## 2. Unused exports (98) → 13 true, 85 false

### 2a. Redundant named export, live code (34) — the false-positive class

Fallow is right that the *named export* is unused, and wrong that the code is dead. The fix is to
drop the `export` keyword, never to delete the function.

**Controller modules that export both by name and via `export default { ... }`:**

| Module | `export default` | Members (all also named-exported) | Consumed at |
|---|---|---|---|
| `server/src/controllers/activityLogController.ts` | :291 | getActivityLogs, getActivityStats, getUserActivity, getEntityActivity, getRecentActivity, getEntityTypes, getActions, exportLogs, cleanupLogs, getUsers | `routes/activityLog.ts:18-45` |
| `server/src/controllers/invoiceController.ts` | :1185 | getInvoices, getInvoice, createInvoice, updateInvoice, deleteInvoice, restoreInvoice, cancelInvoice, getInvoicePayments, returnInvoiceItems, getInvoiceReturnHistory, getInvoicePosition | `routes/invoices.ts:10-20` |
| `server/src/controllers/mobileInvoiceController.ts` | :312 | createDraft, updateDraft, getDraft, deleteDraft, searchItems, searchCustomers, getTaxRates, getPaymentTerms, submitInvoice, processReturn | `routes/mobileInvoices.ts:18-31` |
| `server/src/controllers/inventoryController.ts` | :1157 | getBatchReconciliation, correctBatchReconciliation, updateBatchStatus, createReservation, releaseReservation, getReservations | `routes/inventory.ts:49-71` |
| `server/src/services/activityLogger.ts` | :433 (class instance) | `cleanupLogs` | `activityLogController.ts:242` |

**Other modules with only-internal use (export keyword unnecessary):**
`server/src/services/searchService.ts` — PAGE_ACTIONS :115, filterActions :180, searchSuppliers :261,
searchProducts :313, searchInvoices :370, searchPurchaseOrders :426, searchQuotations :471,
searchSalesOrders :515, searchPayments :559, searchExpenses :610, searchWarehouses :651,
searchEmployees :687, searchProductions :733, searchBOMs :772, searchPages :816;
`server/src/utils/currency.ts:108` computeInvoiceTotal; `server/src/utils/paginate.ts:12,13`;
`server/src/utils/passwordPolicy.ts:1,2`; `server/src/utils/purchaseValidation.ts:13,14`;
`server/src/utils/reportSql.ts:86`; `server/src/middleware/validation.ts:16,29,42`;
`server/src/services/backupService.ts:46`; `server/src/services/expressionValidator.ts:310`;
`server/src/services/paymentValidation.ts:39`; `server/src/services/reportQueryEngine.ts:409,410`;
`server/src/__tests__/helpers/invoiceReturnSpec.ts:23,337`; `.../liveDbGuard.ts:5`.

### 2b. Live but genuinely imported (51) — pure false positives

These have real consumers; fallow's "no references found" is wrong. Representative:
`activityLogController.ts` all 10 handlers; `invoiceController.ts` all 11; `mobileInvoiceController.ts`
all 10; `inventoryController.ts` 6; `middleware/activityLog.ts:43 newCorrelationId`
(used at `invoiceController.ts:13,261`); `middleware/validation.ts:440 validateZod`
(`__tests__/validation.test.ts:23`); `models/InvoiceReturn.ts:60 InvoiceReturnModel`;
`models/Payment.ts:115 PaymentModel`; `services/inventoryEffectiveDate.ts:65,174`;
`services/searchService.ts:9 ENTITY_ACTIONS` (`types/search.ts:40`), `:209 searchCustomers`
(`mobileInvoiceController.ts:114`); `utils/currency.ts:34 computeLineAmount`
(`server/scripts/recompute-item-amounts.js:10,34`).

The four `default` findings (`routes/stockBatches.ts:256`, `services/entityRegistry.ts:471`,
`services/invoiceReturnService.ts:1538`, `services/reportQueryEngine.ts:740`) are a fallow quirk:
it reports the `export default` **keyword** as an unused export named `default`.

### 2c. True dead (13) — safe to delete

| Location | Symbol |
|---|---|
| `server/src/services/activityLogger.ts:424` | `getRecentLogs` |
| `server/src/services/activityLogger.ts:425` | `getUserLogs` |
| `server/src/services/activityLogger.ts:426` | `getEntityLogs` |
| `server/src/services/activityLogger.ts:440` | `logActivityInTx` |
| `server/src/services/entityRegistry.ts:467` | `getEntityKeys` ⚠️ also listed in the `export default` object at :471 — deleting the binding breaks the object |
| `server/src/services/inventoryEffectiveDate.ts:94` | `assertOutboundDateNotRetroactive` |
| `server/src/utils/batchStatus.ts:69` | `isBatchAllocatable` |
| `server/src/utils/currency.ts:90` | `sumInvoiceLineTax` |
| `server/src/utils/errorMessage.ts:24` | `errorStack` |
| `server/src/utils/errorMessage.ts:59` | `asError` |
| `server/src/utils/quantity.ts:121` | `qtyLessThanOrEqual` |
| `server/src/utils/queryUtils.ts:42` | `getQueryNumber` |
| `server/src/utils/reportSql.ts:110` | `cogsUpTo` |

---

## 3. Unused type exports (52) → 18 true, 34 false

### True dead (18)

`server/src/types/index.ts`: PaymentStatus :70, ReturnStatus :71, DemandForecast :189,
ForecastAccuracy :243, ForecastRun :260, ABCClassification :390, TaxRate :485, TaxJarResponse :500,
FixerResponse :507, WeatherResponse :515, NotificationResponse :522, EmailResponse :527,
NumverifyResponse :533, BatchSummary :570, ActivityStat :602;
`server/src/types/search.ts:51` EntityRow;
`server/src/models/EmployeeLoan.ts:52` RepayLoanDTO;
`server/src/models/Invoice.ts:141` UpdateInvoiceDTO.

Note the shape of this list: `TaxJarResponse`, `FixerResponse`, `WeatherResponse`,
`NotificationResponse`, `EmailResponse`, `NumverifyResponse` — six external-API response types
with no integration behind them. Same for `DemandForecast`/`ForecastAccuracy`/`ForecastRun` and
`ABCClassification`. These are scaffolding for unwired features.

### Redundant named export, live code (24)

Exported but only used inside their own module — drop the `export` keyword:
`middleware/requestLogger.ts:5,16`; `models/ActivityLog.ts:12,49`; `models/CustomReport.ts:12,24,31`;
`models/DashboardLayout.ts:18,26,39,41,61,67`; `models/OwnerCapital.ts:6`;
`models/OwnerWithdrawal.ts:12,24,36`; `models/Reports.ts:763,765,924`;
`services/inventoryEffectiveDate.ts:50`; `services/searchService.ts:148`;
`types/index.ts:141` BOMItemDTO, `:493` TaxCalculation.

### Live but genuinely imported (10)

`models/DashboardLayout.ts:51` (`dashboardController.ts:7`), `models/Period.ts:18`
(`__tests__/closedPeriodImmutability.test.ts:52`), `types/index.ts:16` Customer,
`:28` CreateCustomerDTO, `:38` Item, `:146` CreateBOMDTO, `:154` BOM, `:407` Warehouse,
`:480` Setting, `:547` StockBatch.

---

## 4. Unused enum members (28) → 25 true, 3 live

All 28 are members of `ActionType` in `server/src/services/activityLogger.ts`.

**Live (3):** `INVOICE_RETURN` :65 (14 live rows in `activity_log`;
`server/scripts/historical-data-integrity.ts:182,249`), `SO_CANCEL` :56
(`server/src/models/Dashboard.ts:148,510`), `ERROR` :124 (`server/scripts/backup-db.js:30`).

**True dead (25):** PO_CREATE :32, PO_UPDATE :33, PO_APPROVE :34, PO_CANCEL :35, PO_DELETE :36,
GRN_CREATE :37, GRN_UPDATE :38, SO_CREATE :51, SO_UPDATE :52, SO_CONFIRM :53, SO_DELIVER :54,
SO_INVOICE :55, SO_DELETE :57, INVOICE_POST :62, WO_START :82, WO_COMPLETE :83, WO_CANCEL :84,
MATERIAL_CONSUME :86, DATA_IMPORT :106, DATA_EXPORT :107, POS_SALE :111, POS_RETURN :112,
REPORT_GENERATE :115, REPORT_EXPORT :116, DEBUG :121.

Verified against the DB: `SELECT action, COUNT(*) FROM activity_log GROUP BY action` returns 24
distinct actions, and **none** of the 25 above appear. Only `INVOICE_RETURN` is both code-referenced
and present in data.

These 25 are a **domain vocabulary for unwired features** (purchase orders, goods receipts, sales
orders, work orders, material consumption, import/export, POS, reports). Removing them is
data-safe but is a product call — see "Open product decisions" below.

---

## 5. Unused class members (64) → 0 true, 64 false

**Zero true positives.** Every flagged member is either called through its owner class or only used
inside its own class.

**Called (44)** — e.g. `accountingService.ts` `postInvoiceEntry` :528
(`invoiceController.ts:621`, `InvoiceCreationService.ts:277`, `scripts/verify-reversal-rules.ts:148`),
`postPaymentEntry` :588, `postCOGSEntry` :1116, `postPurchaseReturnEntry` :1336, `closePeriod` :1562,
`openPeriod` :1570, `postLoanWriteOff` :1718 and 19 more;
`models/EmployeeLoan.ts` `getById` :110 (`employeeController.ts:373,745,760,785`),
`getByEmployee` :114, `getRepayments` :127, `getSummary` :137, `hasRepayments` :150,
`writeOff` :221, `getGlobalActiveLoans` :284, `getGlobalLoanSummary` :302;
`models/Invoice.ts` `getSalesCycleChain` :431, `deleteInvoice` :1167;
`models/Customer.ts` `deactivate` :203.

**Internal-only (20)** — safe to drop the `export`/keep private:
`EmployeeLoan.ts:120` getActiveByEmployee, `:244` restoreFromWriteOff; `Invoice.ts:938` getTotalPaid,
`:950` getInvoiceForBalance, `:1215` updateSourceTracking, `:1234` getStatsByCustomer, `:1264` getByStatus,
`:1313` deleteItems; `InvoiceReturn.ts:273` getSettlements, `:284` getActiveByInvoiceId;
`Payment.ts:121` generatePaymentNo; `StockMovement.ts:626` getOriginalWarehouseForItem;
`SupplierLedger.ts:118` getAllTransactions, `:129` getSupplierBalances; `User.ts:193` getRoleName;
`Warehouse.ts:31` getAllActive; `accountingService.ts:1761` getAccountRawTotals.

Fallow lists `EmployeeLoan.ts:120/:172/:244` and `accountingService.ts:1554/:1562/:1570/:1761`
**twice** each — static and instance forms of the same member. 7 of the 64 are double-counted.

---

## 6. Unresolved imports (32) → 31 true, 1 artifact

**True (31):** all in `audit/tests/auditRegression{,2..8}.test.ts` — `../app`,
`../config/database`, `../services/activityLogger`, `../services/accountingService`,
`../services/entityRegistry`, `../services/backupService`, `./helpers/invoiceReturnSpec`. None of
those paths exist under `audit/`. They are the same broken copies flagged in §1.

**Artifact (1):** `web/index.html:1` → `./flutter_bootstrap.js`. This is the stock Flutter web
bootstrap file, generated at build time. Not a real finding.

---

## 7. Duplicate exports (8) → 6 real drift risks, 2 benign

There is **no `export *` and no barrel `export { ... } from`** anywhere in `server/`, so none of
these is an import-resolution conflict. They are duplicated *definitions*.

### Diverged shapes — same name, different contract (5)

| Name | A | B | Divergence |
|---|---|---|---|
| `Invoice` | `models/Invoice.ts:51` | `types/index.ts:113` | A has `so_id`, `source_type`, `quotation_id`, `payment_status`, `return_status`, `returned_amount`, `expiry_notes`, `override_sale`, `items`; B has `deleted_at`, `deleted_by`, `deleted_from_*`. `due_date` required vs optional; `created_by`/`created_at` optional vs required |
| `CreateInvoiceDTO` | `models/Invoice.ts:102` | `types/index.ts:95` | `source_type` union includes `'MOBILE'` in A only. A: `total_amount?` optional, `paid_amount?`/`balance_amount?` overrides, `items: CreateInvoiceItemDTO[]`. B: `total_amount` required, `record_payment?`/`payment?: PaymentDTO`, `items: InvoiceItemDTO[]`, `discount_scope` typed union |
| `Quotation` | `models/Quotation.ts:7` | `types/index.ts:446` | A has `expiry_date`, `warehouse_name`, `warehouse_code`, `items`, status incl. `'Converted'`. B has `valid_until`, `source_id`, `warehouse_id` required, status lacks `'Converted'` |
| `SalesOrder` | `models/SalesOrder.ts:9` | `types/index.ts:417` | A has `so_date`/`delivery_date`, status incl. `'Invoiced'`. B has `order_date`/`expected_delivery_date`, status incl. `'Partial'` but not `'Invoiced'` |
| `PaymentAllocation` | `models/Payment.ts:85` | `services/paymentRecordingTypes.ts:25` | **Different concepts entirely.** A = persisted row (`id`, `payment_id`, `invoice_id`, `invoice_no`, `amount`). B = command input (`invoiceId`, `amount`). Identical name, unrelated types |

The last one is the dangerous shape: a reader importing `PaymentAllocation` cannot tell which
contract they have.

### Identical (2) — consolidate to one source

- `WeekStart` — `models/UserPreferences.ts:4` and `utils/weekMath.ts:11`, byte-identical union
- `newCorrelationId` — `middleware/activityLog.ts:43` and `services/activityLogger.ts:429`,
  byte-identical implementation

### Semantic collision (1)

- `cleanupLogs` — `controllers/activityLogController.ts:242` is an Express handler
  `(req, res) => void`; `services/activityLogger.ts:427` is a service delegate
  `(...args) => activityLogger.cleanup(...)`. Unrelated signatures, same name.

---

## 8. Circular dependencies (4) → real, benign at runtime

All 4 pass through `server/src/config/database.ts` (fan-in 164):

```
database.ts:13 → migrations/backfillInvoiceTaxGl.ts:37 → services/accountingService.ts:28
               → services/activityLogger.ts:7 → database.ts:7
database.ts:14 → migrations/backfillMobileInvoiceStockReference.ts:32 → models/Invoice.ts:7
               → models/StockMovement.ts:3 → accountingService.ts:28 → activityLogger.ts:7 → database.ts
database.ts:14 → backfillMobileInvoiceStockReference.ts:32 → models/Invoice.ts:8
               → accountingService.ts:28 → activityLogger.ts:7 → database.ts
database.ts:14 → backfillMobileInvoiceStockReference.ts:32 → models/Invoice.ts:2
               → utils/ledgerUtils.ts:1 → database.ts
```

`server/tsconfig.json` compiles to `"module": "CommonJS"`, so this is a real require cycle.
It is currently benign because every consumer resolves `db` lazily — `activityLogger.ts` only
dereferences `db` inside methods, and TypeScript's CJS interop reads `database_1.default` at the
use site, not at import time. `activityLogger.ts` has no module-scope use of `db` (only
`const activityLogger = new ActivityLoggerService()` at :415 and delegating arrow exports at
:418-427).

It is a latent hazard, not a live bug: any future module-scope use of `db` in `activityLogger.ts`
or `accountingService.ts` will read `undefined`.

---

## 9. Duplication (163 clone groups) → ~34 real families

`4125` duplicated lines / `60434` total = **6.8%** across 218 files, 67 files with clones.
Not one finding is a false positive in the "these aren't actually similar" sense — but the clone
detector is token-based, so it also flags Express boilerplate.

**Cross-file families worth consolidating (real copy-paste):**

| Family | Files |
|---|---|
| list-endpoint CRUD | `bomController.ts:9-23` ↔ `inventoryController.ts:15-20,38-56` |
| pagination param parsing | `customersController.ts:13-18` ↔ `paymentsController.ts` ↔ `suppliersController.ts` |
| list/filter handler shape | `customersController.ts:78-82,109-116` ↔ `employeeController.ts` ↔ `suppliersController.ts` |
| db path resolution | `backfill-ledger-dates.js:23-33` ↔ `dedupe-po.js` ↔ `recompute-item-amounts.js` |
| stock trim logic | `repair-stock.ts:96-102,142-151` ↔ `config/database.ts:958-970` |
| backup path handling | `restore-smoke.js:17-24` ↔ `verify-backup.js` |
| invoice handler shape | `invoiceController.ts:1043-1050,1069-1078,1079-1088` ↔ `mobileInvoiceController.ts:57-62,74-77` |
| activity log model | `activityLogController.ts` ↔ `services/activityLogger.ts` |
| BOM/PO structure | `bomController.ts:9-23,17-40` ↔ `inventoryController.ts` |

**Intra-file clones** (single file, duplicated blocks) account for a large share of the 163:
`app.ts`, `models/PhysicalCount.ts`, `models/Customer.ts:289-341,345-407`,
`models/StockMovement.ts:935-989,1232-1268,1287-1330`, `controllers/bomController.ts`,
`controllers/accountingController.ts:98-104`, `controllers/customersController.ts`,
`config/database.ts:958-971`.

---

## 10. Complexity / health (221 findings) → 84 real, 137 noise

**137 of 221 (62%) are flagged by CRAP alone** (`exceeded: 'crap'`), with cognitive 1–15 and
cyclomatic 5–20 — i.e. structurally fine. CRAP is `complexity × (1 − coverage)²`, and fallow's
coverage here is **estimated, not measured** (`coverage_source: "estimated"` on 217/221,
`coverage_tier: "partial"` on 181). The repo has `coverage/lcov.info` but no server-side
`coverage-final.json`, so `fallow health --coverage` cannot be run. Re-run with real coverage
before acting on these.

**84 findings exceed a genuine structural threshold** (cyclomatic > 20, cognitive > 15, or
> 60 lines). 79 are in live server code, 5 in test files. Top offenders:

| Location | Function | cyc | cog | lines |
|---|---|---|---|---|
| `models/PurchaseReturn.ts:250` | `transaction` | 58 | **117** | 428 |
| `models/StockMovement.ts:816` | `consumeFromOldestBatches` | **63** | 74 | 296 |
| `services/reportQueryEngine.ts:546` | `buildFilterExpression` | 46 | 50 | 122 |
| `controllers/invoiceController.ts:341` | `transaction` | 44 | 55 | 308 |
| `migrations/backfillGlPreposting.ts:131` | `run` | 43 | 76 | 200 |
| `controllers/expenseController.ts:191` | `updateExpense` | 41 | 47 | 100 |
| `services/invoiceReturnService.ts:216` | `txn` | 40 | 51 | 324 |
| `controllers/paymentsController.ts:116` | `createPayment` | 38 | 54 | 157 |
| `controllers/inventoryController.ts:82` | `createItem` | 35 | 45 | 125 |
| `services/InvoiceCreationService.ts:156` | `transaction` | 35 | 44 | 161 |
| `models/PhysicalCount.ts:510` | `transaction` | 30 | 67 | 259 |
| `services/expressionValidator.ts:53` | `tokenize` | 29 | 52 | 105 |

Concentration: `employeeController.ts` (10), `models/StockMovement.ts` (9),
`inventoryController.ts` (8), `invoiceController.ts` (7), `ownerPersonalLoansController.ts` (7),
`server/scripts/dev/audit-trace.ts` (7), `services/reportQueryEngine.ts` (6).

The `db.transaction(() => { ... })` blocks dominate the top of the list. A 428-line transaction
callback with cognitive 117 is real: it is one atomic unit that cannot be split without changing
transaction semantics, so the fix is extraction of *pure helpers* called from inside the callback,
not a split of the callback itself.

---

## Recommended sequence

1. **Do not run `fallow fix` on the server tree.** The controller findings would un-export live
   route handlers.
2. **Delete the 14 truly dead files** (§1) — 8 broken audit test copies, 4 orphan CSS, 2 orphan
   scripts.
3. **Fix the 31 broken imports** by deleting the 8 `audit/tests/` copies (resolves both §1 and §6).
4. **Add `fallow` config** to exclude the `export default { ... }` namespace pattern from
   dead-code reporting, or add `// fallow-ignore-next-line unused-export` on the redundant named
   exports in §2a/§3/§5 (78 sites). Without this, fallow's dead-code gate will keep failing on
   live code.
5. **Remove the 13 + 18 + 25 genuinely dead symbols** (§2c, §3, §4) — but see the product note on
   the 25 `ActionType` members.
6. **Consolidate the 6 divergent duplicate types** (§7) — pick one canonical definition per name.
   `PaymentAllocation` is the priority: two unrelated types share a name.
7. **Deduplicate `newCorrelationId`** (byte-identical, 2 copies) and `WeekStart` (identical union).
8. **Refactor the 79 structural complexity findings**, starting with the 12 in the table above.
9. **Regenerate the CRAP-based 137** only after producing a real `coverage-final.json` for
   `server/`; today the metric is estimated and unreliable.

---

## Open product decisions (not for the agent to guess)

1. **The 25 unused `ActionType` members** describe purchase orders, goods receipts, sales orders,
   work orders, material consumption, import/export, POS and reports. No code writes them and no
   DB row contains them. Options: (a) delete them, (b) keep them as the intended vocabulary for
   unwired modules, (c) wire the modules up to use them. This is a product call — the purchasing
   and work-order modules clearly exist (`purchaseOrderController.ts`, `productionController.ts`)
   but log no activity today.
2. **`PaymentAllocation`** — the DB-row type in `models/Payment.ts` and the command type in
   `services/paymentRecordingTypes.ts` share a name. Renaming one (e.g. `PaymentAllocationRow`
   vs `PaymentAllocationInput`) is a small mechanical change but touches call sites.

---

## Reproduction

```bash
npx fallow --format json > /tmp/opencode/fallow.json     # raw findings
node audit/fallow-tools/verdict.mjs                       # per-finding verdict table
node audit/fallow-tools/detail.mjs <category> <symbol>    # consumer evidence for one symbol
```

`verdict.mjs` classifies each finding as `CONFIRMED-DEAD`, `REDUNDANT-NAMED-EXPORT`, or
`FALSE-POSITIVE`, with the consumer evidence behind each verdict.

---

# Remediation — applied 2026-10-20

Everything below was executed, not proposed. Rationale for each judgement call is in
`audit/DECISIONS.md` D13.

## Gate outcome

| Gate | Before | After |
|---|---|---|
| `error-severity-findings` | **fail** (275) | **pass** (0) |
| `health-findings` | fail (221) | fail (230) — see below |
| `dupes` | 163 clone groups | 39 clone groups (7.00% of lines) |

## Dead code, per metric

| Metric | Before | After |
|---|---|---|
| unused files | 20 | **0** |
| unused exports | 98 | **0** |
| unused types | 52 | **0** |
| unused enum members | 28 | 28 (demoted to `warn` — vocabulary, kept) |
| unused class members | 64 | 35 (demoted to `warn` — fallow cannot track static calls) |
| unresolved imports | 1 | **0** |
| duplicate exports | 8 | **0** |
| circular dependencies | 4 | **0** |
| **total** | **275** | **63** (all remaining are warn-level) |

## What was removed

- **14 files** — 8 stale `audit/tests/auditRegression*.test.ts` copies (broken import paths, and
  they encoded *superseded* designs: pre-D3 salary split, pre-D6 overhead rule, pre-D5 supplier
  rule), 4 orphan `styles/*.css` files, 2 orphan scripts with zero references.
- **12 exports, 29 type exports, 23 class members** — all confirmed dead by module-scoped
  resolution. Notable: `PaymentModel.generatePaymentNo` was the superseded non-atomic twin of the
  live `InvoiceModel.generatePaymentNoAtomic`; leaving both was a live duplicate-`payment_no`
  hazard.
- **`services/inventoryEffectiveDate.ts` scoped down** to its live surface
  (`assertInboundDateNotRetroactive`, called by `models/Purchase.ts` and `models/PurchaseOrder.ts`).
  The outbound half was written in `e43f7df8` with two dangling imports and never had a call
  site — the outbound rule is enforced by the `asOf` filter in `StockMovement.consumeFromOldestBatches`.
  Rationale moved to `docs/INVENTORY-EFFECTIVE-DATES.md`.
- **4 cycles fixed at the root** — the seven one-time backfill runners in `config/database.ts` are
  now `require`d lazily inside `applyPendingMigrations()`. Same order, same transaction
  boundaries; the require graph is now acyclic.
- **5 duplicate-type families resolved** — `PaymentAllocation` (row shape vs command shape) became
  `PaymentAllocationRow`; `Invoice`, `CreateInvoiceDTO`, `Quotation`, `SalesOrder` model-local
  copies are no longer exported (the `types/index.ts` copies are the ones imported across
  modules).
- **2 byte-identical duplicates removed** — `newCorrelationId` (now one source in
  `services/activityLogger.ts`) and `WeekStart` (now one source in `utils/weekMath.ts`).

## Config (`.fallowrc.json`)

`ignoreExportsUsedInFile` (a same-module reference *is* a use — this alone removed 82 findings),
`ignorePatterns` for the verifier tooling, `ignoreExports` for fallow's `default` pseudo-export,
`entry` for the 18 doc/CI-invoked operational scripts, `ignoreUnresolvedImports` for Flutter's
generated `flutter_bootstrap.js`, `duplicates.minOccurrences: 3`, and `health.coverage` pointing at
real Istanbul data.

`health.coverage` is the important one: fallow's CRAP metric was previously computed from an
**estimated** coverage model (`coverage_source: "estimated"`, 217 of 221 findings). It is now
`coverage_model: "istanbul"` fed by `server/coverage/coverage-final.json` (66.77% statements,
72.7% functions), so the 146 CRAP-only findings are real risk signals rather than guesses.

## Verification

| Check | Result |
|---|---|
| `server/` typecheck | pass |
| `server/` lint | pass |
| `server/` jest | **164 suites / 1457 tests pass** (run twice: after deletions, and again with coverage) |
| `node scripts/l10n-drift.js` | pass (gap 55, cap 60) |
| `flutter analyze` | **3 errors — pre-existing, in untouched `lib/` files** |
| `scripts/check.sh --quick` | passes except `flutter: analyze` (the pre-existing 3) |

The 3 Flutter errors are `inputTaxAmount` on `PurchaseOrderItem`
(`lib/features/purchase_orders/purchase_order_form_dialog.dart:162,435`) and the `idempotencyKey`
named parameter (`lib/features/sales/invoice_return_dialog.dart:346`). `git diff HEAD -- lib/` is
empty — the client is byte-identical to HEAD, so these predate this work.

## Still open

1. **The health gate: 230 findings.** 38 exceed every threshold (cyclomatic, cognitive, CRAP,
   size); 146 are CRAP-only, now measured against real coverage. The top 12 are listed in the
   earlier section. `db.transaction(() => { ... })` callbacks dominate the list — the fix is
   extracting *pure helpers* called from inside the callback, never splitting the callback itself,
   because that would change transaction semantics.
2. **fallow is not wired into CI.** It cannot be yet: the health gate still fails. Once it is
   cleared, `npx fallow` belongs in `.github/workflows/ci.yml` and `scripts/check.sh` together.
3. **The `types/index.ts` vs model type drift is not resolved.** `Invoice`, `CreateInvoiceDTO`,
   `Quotation` and `SalesOrder` still have two shapes each. Choosing one is a behaviour change,
   not a cleanup, so it is left for a deliberate decision.
4. **Wiring activity logging into the unwired modules** (purchasing, work orders, POS) would give
   the 28 `ActionType` members a purpose. That is a product decision.

## Exit codes (authoritative)

| Command | Before | After |
|---|---|---|
| `fallow dead-code` | 1 | **0** |
| `fallow dupes` | 1 | **0** |
| `fallow health` | 1 | 1 (230 findings — complexity work, still open) |

Note on the human summary line: it prints `Failed: dead-code (63 issues)` because it aggregates
*all* findings. The 63 are the 28 `unused-enum-members` and 35 `unused-class-members` findings,
both demoted to `warn`; the `error-severity-findings` gate observes **0** and
`fallow dead-code` exits **0**.

---

# Phase 2 — complexity reduction and the CI gate (2026-10-20)

## Why this phase exists

The dead-code cleanup above closed the `error-severity-findings` gate but left the health gate
at 221. The remaining findings are not noise: 84 exceeded a real structural threshold
(cyclomatic > 20, cognitive > 15, or > 60 lines) and 137 were CRAP-only findings that fallow had
computed from an **estimated** coverage model. Both categories were real risk, and neither was
visible to CI.

## Complexity reduced

22 functions were refactored by extracting pure helpers from inside the offending bodies. The
transformation is behaviour-preserving by construction — the extracted helpers take their inputs
as parameters and return values; nothing is re-ordered, no transaction boundary is crossed, and
no SQL is changed.

| Function | Before (cyc/cog/lines) | After |
|---|---|---|
| `reportQueryEngine.buildFilterExpression` | 46 / 50 / 122 | 12 / 13 / 33 |
| `inventoryController.createItem` | 35 / 45 / 125 | off the list |
| `StockMovement.consumeFromOldestBatches` | 63 / 74 / 296 | 15 / 12 / 57 |
| `models/PurchaseReturn.ts` create transaction | 58 / 117 / 428 | 15 / 25 / 180 |
| `invoiceController` update transaction | 44 / 55 / 308 | 20 / 19 / 187 |
| `expenseController.updateExpense` | 41 / 47 / 100 | 17 / 17 / 82 |
| `models/Invoice.createInvoice` | 32 / 35 / 60 | off the list |
| `InvoiceCreationService.transaction` | 35 / 44 / 161 | 21 / 25 / 99 |
| `paymentsController.createPayment` | 38 / 54 / 157 | 10 / 9 / 60 |
| `purchaseController.recordPurchase` | 32 / 39 / 133 | 20 / 26 / 111 |
| `posController.createPOSSale` | 32 / 44 / 149 | 22 / 24 / 116 |
| `ledgerUtils.updateInvoiceStatus` | 30 / 35 / 75 | off the list |
| `models/Payment.ts` update transaction | 32 / 46 / 115 | 20 / 22 / 112 |
| `migrations/backfillGlPreposting.ts` run | 43 / 76 / 200 | off the list |
| `expressionValidator.tokenize` | 29 / 52 / 105 | off the list |
| `models/Employee.ts` create + update | 28 / 29 · 29 / 29 | off the list |
| `invoiceReturnService` return transaction | 40 / 51 / 324 | 30 / 38 / 265 |
| `employeeController` salary transaction | 29 / 22 / 111 | 20 / 18 / 127 |
| `customReportsController.validateReportConfig` | 28 / 49 / 83 | 24 / 39 / 74 |
| `models/PhysicalCount.ts` correction transaction | 30 / 67 / 259 | still open |
| `paymentsController.getPaymentReceipt` | 24 / 27 / 142 | still open |

Two further extractions were not complexity refactors but removed real duplication the refactors
surfaced: the idempotency-replay block repeated in three controllers is now one
`respondToIdempotencyReplay` helper in `server/src/utils/idempotency.ts`, and the four import
cycles are gone because the seven one-time backfill runners in `config/database.ts` are now
`createRequire`d lazily instead of statically imported.

## Numbers

| Metric | Before | After |
|---|---|---|
| dead-code findings | 275 | **63** (all warn-level) |
| unused files / exports / types | 20 / 98 / 52 | **0 / 0 / 0** |
| duplicate exports | 8 | **0** |
| circular dependencies | 4 | **0** |
| unresolved imports | 1 | **0** |
| structural health findings | 85 | **75** |
| critical health findings | 56 | **41** |
| clone groups | 163 | **39** |
| maintainability index | 89 | **90.9** |
| `error-severity-findings` gate | fail (275) | **pass (0)** |

## The CI gate

A gate that fails on the whole legacy backlog is a gate nobody keeps green, so the backlog is
**baselined, not hidden**:

- `audit/fallow-baselines/{dead-code,health,dupes}.json` are committed snapshots of the findings
  that are known and accepted today.
- `.fallowrc.json` sets `audit.gate: "new-only"` and points the three baseline paths at them, so
  the audit fails only on findings that are *new* relative to the base ref.
- `.github/workflows/ci.yml` gains a `fallow` job running
  `npx --yes fallow@3.34.1 audit --base "$FALLOW_BASE"`, and `scripts/check.sh` gains the matching
  `server: fallow` step. The version is pinned because the baselines are only comparable against
  the analyzer that produced them.
- `health.coverage` points at `server/coverage/coverage-final.json`, so CRAP is computed from
  **real** Istanbul coverage (66.77% statements, 72.7% functions) instead of fallow's estimate.
  That alone changed 146 findings from guesses into measurements.

`fallow audit --base HEAD` now reports **✓ No issues in 86 changed files** and exits 0.

## Verification

`scripts/check.sh` (the repo's own gate, which runs everything CI runs):

| Step | Result |
|---|---|
| `server: typecheck` | ok |
| `server: lint` | ok |
| `server: fallow` | **ok — ✓ No issues in 86 changed files** |
| `server: test` | **ok — 164 suites / 1457 tests passed** |
| `flutter: analyze` | **FAILED — 3 pre-existing compile errors** |
| `flutter: l10n drift` | ok |
| `flutter: test` | **FAILED — 5 failures, all from the same 3 compile errors** |

The three Flutter errors are **pre-existing and unrelated to this work**:

```
lib/features/sales/invoice_return_dialog.dart:346  No named parameter with the name 'idempotencyKey'
lib/features/purchase_orders/purchase_order_form_dialog.dart:162  The getter 'inputTaxAmount' isn't defined for the type 'PurchaseOrderItem'
lib/features/purchase_orders/purchase_order_form_dialog.dart:435  The getter 'inputTaxAmount' isn't defined for the type 'PurchaseOrderItem'
```

`git diff HEAD --stat -- lib/ test/ integration_test/` is **empty** — the Flutter client is
byte-identical to HEAD, so both the analyze errors and the test failures predate this work. They
were present in the first `flutter analyze` run of this session, before any edit.

## Still open

1. **75 structural health findings** remain (41 critical). The largest are
   `models/PhysicalCount.ts:510` (cog 67), `models/Expense.ts:179`, `services/cashService.ts`,
   `models/Production.ts`, `controllers/productionController.ts` and
   `controllers/preferencesController.ts`. They are baselined, so CI now blocks them from growing.
2. **The `types/index.ts` vs model type drift** for `Invoice`, `CreateInvoiceDTO`, `Quotation` and
   `SalesOrder` is unresolved: two shapes still exist for each name. Choosing one is a behaviour
   change, not a cleanup.
3. **Wiring activity logging into the unwired modules** (purchasing, work orders, POS) would give
   the 28 `ActionType` members a purpose. A product decision.
4. **The 3 pre-existing Flutter compile errors** above need fixing on the client; they currently
   break `flutter analyze` and `flutter test` in CI.
---

# Phase 3 — the three Flutter compile errors were already fixed upstream

The dead-code work left three client-side compile errors that predated it
(`git diff HEAD -- lib/ test/ integration_test/` was empty). They were compile
errors, but two of them were the visible symptom of a **behavioural** bug, and
fixing them properly meant fixing the bugs.

## What was actually going on

**The checkout was 27 commits stale.** The session started on a detached HEAD at
`521cb5e1`, while `origin/main` was at `e631b792` — 27 commits ahead. Those 27
commits contained the fixes already:

| Upstream commit | Fix |
|---|---|
| `b1f14c06 feat(client): carry recoverable input tax on the purchase models` | `PurchaseOrderItem.inputTaxAmount` |
| `968e24e0 feat(client): show the recoverable input tax on the purchase forms` | the purchase-order form's tax field |
| `65ff4f4f feat(client): send idempotency keys with the money repositories` | `Idempotency-Key` headers on the money repositories |

So the three "pre-existing" errors were not pre-existing **upstream** — they were
an artifact of working from a stale base.

## Why the fix had to be a rebase, not a patch

The stale base also made two of the three look like bugs rather than drift:

1. **`idempotencyKey`** — the dialog passed a key the repository had no parameter
   for. The server reads the key from the `Idempotency-Key` **header**, not a body
   field, so on the stale base the key was never reaching the server and a retry
   after a lost response would have returned the goods twice. Upstream already
   sends the header.

2. **`inputTaxAmount`** — the server has carried PO input tax since migration
   `116_purchase_order_input_tax.sql`; the Dart model on the stale base predated
   it. Upstream already carries the field.

3. **`settleReturn`'s wire key** — on the stale base the client posted
   `{'settlements': ...}` while the server reads `req.body.allocations` and
   answers **400 "Invalid request: allocations must be a non-empty array"**, so
   every attempt to settle a return from the desktop client failed.
   `test/repositories/invoice_return_payload_test.dart` was already failing on
   this. Upstream already posts `allocations`.

## The one thing that would have been wrong

The purchase-order form sends `input_tax_amount` on every line. The stale
base's widget test asserted the create body was exactly
`{item_id, quantity, unit_price}` — no tax key — and the fix was to omit the
key when the tax is zero.

**Upstream deliberately does the opposite**: its updated widget test expects
`'input_tax_amount': 0.0` in the body (that was `0478ccd5 test(client): repair
the stale financial widget expectations`), and its `_lineBody` still sends the
key unconditionally. Omitting it would have contradicted upstream's contract and
broken upstream's test.

## What was done instead

The work was rebased onto `origin/main` and the client-side changes were
**dropped as redundant**:

- The 27 upstream commits touch **zero** `server/` files, so the whole dead-code
  cleanup and the complexity refactors applied cleanly.
- `.github/workflows/ci.yml`, `scripts/check.sh`, `.gitignore` and `styles/` were
  untouched upstream, so the fallow gate and the CSS cleanup applied cleanly.
- `audit/DECISIONS.md` was changed upstream, so D13/D14 were re-applied on top of
  upstream's version rather than replacing it.
- `lib/` and `test/` were left at upstream's state: upstream's implementations
  are the canonical ones, and its wire contract is deliberate.

The fallow baselines were re-saved against the rebased tree.

## Verification after the rebase

`scripts/check.sh` — **all checks passed**:

| Step | Result |
|---|---|
| `server: typecheck` | ok |
| `server: lint` | ok |
| `server: fallow` | ok — ✓ No issues in the changed files |
| `server: test` | ok — 164 suites / 1457 tests passed |
| `flutter: analyze` | ok — No issues found |
| `flutter: l10n drift` | ok |
| `flutter: test` | ok — 957 tests passed |

The three Flutter compile errors are gone because upstream had already fixed
them; no client-side change was needed or made.
