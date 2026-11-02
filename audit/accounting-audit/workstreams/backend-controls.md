# Backend accounting controls audit

Audit-only workstream B, 2026-10-25. No production or existing test files changed. No live database opened. All dynamic evidence uses newly created `accounting-audit/evidence/backend-run-*` databases and a SQLite-constructor path guard. Failed/incomplete initial probes are not passing evidence. Full server gates are owned by the lead.

## Discovery and evidence boundaries

Graph-first discovery used project `media-fawad-26F2EFA7F2EF7987-D-minierp-flutter`: 570 server/src file nodes; 50 classes; direct inbound trace of `AccountingService.postEntry` found 28 production callers. Scoped coverage query reports 62 parse-partial files (61 migrations and one test); SQL source is the authority. Graph edge absence is not proof of nonuse. Direct file inventory captures 325 non-test files in models/services/controllers/routes/migrations/boot/config/middleware/utils/types plus app.ts, including rollback migration scripts; hashes, dependency imports, transaction/accounting/permission references and SQL constraints are in `../evidence/backend-source-inventory.json`. This is exhaustive discovery for those directories, not a claim that every line or permutation was dynamically verified.

Instructions consulted: root AGENTS, nested models/controllers/routes AGENTS, CODING_STANDARDS, REVERSAL-RULES, API, DATABASE, DESIGN, FINDINGS-STATUS, DECISIONS, STRICT_NULL_CHECKS. Historical reports supply policy/triage context only. No historical dummy balances were re-audited.

Status vocabulary: **reviewed** = source path/control inspected; **mapped** = dependencies/control references inventoried, not full semantic verification; **API** = mounted authenticated HTTP scenario run in this workstream; **peer** = independent lifecycle work owned by financial-oracle, see its evidence; **unrun** = no new dynamic evidence here. GL status always distinguishes a source mapping from an actual journal assertion.

## Accounting policy and dependency map

```
authenticated route + permission + body validation
  -> controller orchestration
  -> model / command service transaction
  -> source document + allocations + authoritative subledger/batch rows
  -> AccountingService.postEntry / postLegacyStockEntry
  -> journal_entries header + journal_lines canonical amounts
  -> GL reports and cash guards
```

`AccountingService.postEntry` (accountingService.ts:308) normalizes amounts to integer cents, rejects negative/both-sided/zero lines, checks balance and account existence, checks closed periods, auto-opens a missing calendar month, then atomically inserts header and lines. `postLegacyStockEntry` applies currency rounding and its own closed-period guard, resolves text codes, and inserts both stores transactionally. The database adds deferred balance-FK triggers (`add-journal-balance-commit-guard.sql`) so a committed unbalanced group fails even when service code is bypassed. The constraints establish balance, not economic account selection, dates, valuation or recognition: F-020/F-021/F-022 can remain double-entry balanced.

DB boundary: config/database.ts:54 fails closed for tests without DATABASE_PATH; 59–60 treats the variable as a directory and appends erp.db. Foreign keys ON, WAL, busy timeout and migration ledger/checksums are configured. Import opens a connection but explicit `applyPendingMigrations()` performs schema initialization. Harness boot applied those migrations only to fresh disposable DBs. Migration replay/backfill behavior on historical databases was not re-executed.

| Event | Intended debit | Intended credit | Source/recognition |
|---|---|---|---|
| Cash/bank funding | 1000 Cash /1010 Bank or mobile-money account | 3200 Owner capital | OwnerCapital create; account routing is shared |
| Sale | 1100 AR | 4000 sales + output tax liability | Invoice creation on document date; COGS separate |
| Cash receipt | Cash/bank | 1100 AR | PaymentRecordingService allocations |
| Customer unused receipt | Cash/bank | 2110 customer unapplied liability | UnappliedCashService; applying clears liability into AR, refund clears into cash |
| Customer return pool | return/reversal accounts, as settlement dictates | 1110 customer credit | Distinct from legacy negative customer-ledger credit; pool consumption Dr1110/Cr1100 |
| Direct purchase / goods received | 1200 inventory +1320 recoverable input tax | Cash or2000 AP | Purchase / receipt recognition; PO submission is commitment, not receipt expense |
| Supplier bill | 6000 expense +1320 input tax | 2000 AP | SupplierBill.create; bill total=net+tax |
| Supplier payment | 2000 AP | Cash/bank | Shared SupplierPaymentService |
| Supplier prepayment | 1330 supplier advance asset | Cash/bank | Separate asset, apply DrAP/Cradvance; not expense |
| Credit expense | mapped expense (default6000) | 2115 accrued expense payable | Recorded status; settlement Dr2115/Crcash |
| Salary | 6100 wages | Cash/bank | Current salary portion |
| Salary excess | 1310 salary advances | Cash/bank | Next pay-period linked advance; **recognition defect F-020** |
| Employee loan | 1300 employee loan receivable | Cash/bank | Disbursement; repayment DrCash/Cr1300; write-off Drloss/Cr1300 |
| Owner cash drawings | 3300 owner drawings equity | Cash/bank | No P&L expense |
| Owner goods drawings | 3300 owner drawings equity | Inventory | Actual consumed batch cost, not sales value |
| Production material consume | 7000 production clearing | Inventory | Actual FIFO/FEFO input costs |
| Production overhead | production clearing | 2200 production overhead payable | Attributable unpaid overhead capitalized once; no duplicate expense |
| Production outputs | Inventory | production clearing | Relative sales-value allocation; quantity fallback; final residual |
| Count gain/loss; write-off | Inventory or adjustment/loss | adjustment/inventory | Costed batches; stock and GL in transaction |
| Warehouse transfer / expiry relocation | no value recognition | no value recognition | Physical relocation retains batch value; write-off is separate |
| Owner personal loans | no business GL | no business GL | Separate personal memorandum ledger; see scope below |

Exact seeded chart (including subsidiary cash account and tax codes) is captured from each fresh DB in results.json `accounts`; this table is a workflow map, not a substitute for that schema artifact.

Owner personal loans (`ownerPersonalLoansController`) are explicitly separate from business employee-loan/equity postings. Source create/repay update only personal loan/borrower tables, with their own currency column. Absence from business GL is an observed design boundary, not a defect inferred merely because the feature is under Owner Equity. Multi-currency conversion and business-funded personal lending were not exercised.

## Financial workflow coverage register

| Workflow / lifecycle | Backend implementation / dependency | Static | Dynamic here | GL evidence / residual |
|---|---|---|---|---|
| Chart, account balances, reconciliation | accountingController; AccountingService; cashService | reviewed | account snapshot | exact chart captured; reconciliation peer/lead |
| Open/close periods; reject closed posting | Period; accountingController; postEntry | reviewed | cross-period settlement probe | F-023 below; general closed posting peer |
| Opening cash/change opening | Settings; cashService.syncOpeningBalancesToGl | mapped | unrun | mapped; lead suite only |
| Customer create/update opening/soft-delete | Customer; customersController; ledgerUtils | mapped | peer | no independent reassertion here |
| Supplier create/update opening/soft-delete | Supplier; SupplierLedger | mapped | fixture create | source only for opening/edit/delete |
| Item create/update/expiry/soft-delete | Item; inventoryController | reviewed batchExpiryDate | fixture create | no GL until stock transaction |
| Warehouse create/update/delete/system guards | Warehouse; inventoryController | mapped | unrun | no independent GL |
| Quotation create/edit/convert/delete | Quotation; salesController | mapped | unrun | nonposting until sales conversion |
| Sales order submit/edit/cancel | SalesOrder; reservations; Invoice | mapped | peer/unrun variants | cancellation boundary not independently executed |
| Invoice create/edit/cancel/delete/restore | InvoiceCreationService; Invoice; invoiceController | mapped | peer | credit/cash/tax/COGS peer evidence |
| POS/mobile invoice create/cancel | pos/mobile controllers; shared creation | mapped | unrun | independent channel parity unverified |
| Customer payment create/edit/reallocate/void | PaymentRecordingService; Payment | mapped | peer | receipt/reversal peer evidence |
| Unapplied customer receipt/apply/refund/reverse | UnappliedCashService/Model; replay keys | reviewed mapping | peer | liability/subledger peer evidence |
| Invoice return/refund/store-credit/write-off | invoiceReturnService; ReturnModel | mapped | peer | tax/cost/settled ceilings peer evidence |
| Direct purchase create/edit/void | Purchase; supplier ledger; batch create | reviewed recognition mapping | fixture 0.02 purchase | input tax dynamics peer; edit/void independent unrun |
| PO create/submit/edit/cancel | PurchaseOrder; supplier commitment | reviewed recognition mapping | peer/unrun variants | no blanket PO lifecycle pass |
| Goods receipt/create/void | PurchaseOrder; stock batches; postGoodsReceiptEntry | reviewed mapping | peer | receipt tax accrual peer |
| Purchase return/create/void | PurchaseReturn; batches; supplier credits | mapped | peer | independent cost residuals unrun here |
| Supplier refund/create/void | SupplierRefund; credit note settlement | mapped | peer | cash receipt & AP source mapping |
| Supplier payment/create/edit/void | SupplierPaymentService; Payment; validation | reviewed | peer; F-023 probe | source bill-date closed guard investigated |
| Supplier bill/create/pay/void | SupplierBill | reviewed | F-023 probe | 6000/1320/2000 posted; later pay blocked |
| Supplier advance/create/apply/void | SupplierPrepayment | reviewed | peer | separate asset; full variants unrun here |
| Expense draft/edit/record/cancel/delete | Expense; expenseController | reviewed | credit accrual fixture | 2115 payable capture; cancellation unrun here |
| Expense payment/create/void | ExpensePayment | reviewed | F-023 probe | settlement blocked by source period |
| Employee create/update/delete | Employee; employeeController | mapped | fixture create | deletion constraints unrun |
| Salary full/partial/advance/replay/void | employeeController; Employee; AccountingService | reviewed | F-020 two months | wages/advance/cash exact; replay/void unrun here |
| Employee loan create/repay/write-off/void | EmployeeLoan; employeeController | reviewed | F-021 create+repay | historical receivable becomes negative; other variants unrun |
| Owner capital/create/edit/void | OwnerCapital; ownerEquityController | reviewed | fixture funding | Bank10000 / equity10000; edit/void unrun |
| Owner drawings cash/goods/create/edit/void | OwnerWithdrawal; FIFO; cashTimeline | reviewed | API create+void cash/goods | exact cost/equity/reversal PASS extension; edit unrun |
| Owner personal loan create/edit/delete | ownerPersonalLoansController | reviewed | unrun | personal memorandum, no business GL observed |
| Owner personal repayment/create/delete; borrower merge | ownerPersonalLoansController | reviewed | unrun | balances in separate personal tables; economic scope not presumed |
| BOM create/edit/delete/version | BOM; bomController | mapped | unrun | recipe only; no GL until production |
| Production single/joint/cancel-delete | Production; StockMovement | reviewed | F-022 rounding; positive joint+delete API | ordinary allocation/reversal PASS extension; tiny residual defect persists |
| Production overhead accrual | Production.recordProduction | reviewed | API materials60+overhead30 | inventory130/payable30/clearing0, no extra expense; reversal neutral |
| Inventory adjustments in/out | StockMovement.recordMovement | mapped | peer/unrun | shared costing/postLegacy controls mapped |
| Transfers/create/reverse | StockMovement.recordTransfer/voidTransfer | reviewed mapping | peer/unrun | physical relocation; value neutrality unrun here |
| Expiry detection/transfer/batch status | boot/expiryDetection; StockMovement; Item | reviewed mapping | unrun | not automatic expense; write-off separate |
| Damage transfer/write-off | StockMovement.recordDamageTransfer/writeOffBatch | mapped | peer | peer confirmed scope ownership |
| Physical count/create/update/post/correct | PhysicalCount | reviewed | API10→8→9 and repeated correction | single-cost PASS; F024 mixed-cost correction500; F025 omitted-item shortage erased |
| Batch availability, FIFO/FEFO, location flag | StockMovement.consumeFromOldestBatches | reviewed | peer/default path | document-date passed; location-enabled variants unrun |
| Reservations create/release/availability | StockReservation; sales orders | mapped | unrun | no GL until fulfillment; oversell variants unrun |
| General ledger/trial balance/income/BS | Reports; reportsController | reviewed mapping | F-020 reports | salary asset/expense propagation captured |
| AR/AP aging/statements/as-of | arAging; Reports; subledger views | mapped | peer | backend ageing variants not independently run |
| Cash flow/reconciliation | cashService; Reports; dashboard | reviewed mapping | peer | cumulative income/outflow and reversal peer |
| Tax summary/input/output tax | Reports; account1320; purchase migrations115/116 | reviewed mapping | peer | not remittance/filing audit |
| Stock valuation/traceability/expiry | Reports; inventoryController | mapped | production snapshot | lot aggregation dynamics peer |
| Sales/purchase/production/dashboard summaries | Dashboard; Reports; controllers | mapped | peer/flutter | not every filter/group combination verified |
| Custom reports CRUD/run/preview/export | CustomReport; reportQueryEngine; entityRegistry; expressionValidator | reviewed core engine | unrun | generic report field selection is not automatic accounting policy |
| Forecasts/overrides, dashboard layouts | forecastService/controllers; DashboardLayout | mapped | unrun | planning/display; no posting calls inventoried |
| Permissions/auth/activity/audit logs | middleware/auth/requirePermission; Role; activityLogger | mapped | admin route auth exercised | non-admin deny matrix not repeated here |
| Database migrations/backfills/repair scripts | config/database; migrations | reviewed setup/guards, other files mapped | fresh boot only | historical replay intentionally not run |

## Control observations and limits

Server routes apply authentication and module permissions. Payroll routes use only generic object-body validation, and controllers supply detailed amount/method checks; they do not have equivalent date safeguards for every action. Frontend constraints cannot prevent F-021 because the backend accepts a crafted real POST. Salary payment carries an idempotency scope and transactionally claims it with both payment rows; source inspection does not substitute for retry proof.

Stock allocation now accepts an `asOfDate` argument (StockMovement.ts:1154); older audit D12 text describing no date parameter must not be repeated as current fact. Eligibility combines current remaining quantities with date filtering, so it is not a complete historical time-series inventory engine. Both batch-location feature branches exist; this audit does not claim independent dynamic coverage of both.

Custom report executeReport validates computed expression grammar, field names and aliases, resolves only registered joins, binds values, and caps rows; grouped count runs without main LIMIT. The engine does not turn arbitrary operational row totals into a certified financial report. Every report entity's default void filters, join multiplicity, custom formulas and currency semantics would require independent fixtures to certify; not completed in this workstream.

Closing a period should freeze original entries, not prohibit a later settlement in an open period. ExpensePayment and supplier bill validation assert the original source date as well as the new payment date: F-023 records the resulting workflow lockout.

No claim of a clean comprehensive accounting audit is made. Coverage status explicitly distinguishes evidence from inventory. The lead owns final integration, full-suite results and cross-workstream reconciliation.

## Consolidated dynamic result

Final invocation `node accounting-audit/tests/backend-controls.cjs` completed successfully with all four defects reproduced in `accounting-audit/evidence/backend-run-Lbw3la/results.json` and retained erp.db; console capture `backend-probes-verified.log`. F-020 reports and salary history, F-021 chronology, F-022 negative cost allocation, F-023 closed-source settlement block are documented in findings/F-020 through F-023. SQLite integrity was `ok`, FK violations empty. These controls passing does not contradict the economic defects.

Independent evidence verification invocation: `node accounting-audit/tests/backend-verify-evidence.cjs` reads the saved API result and opens only that disposable SQLite file read-only, checks exact economic outcomes, negative stock-batch cost, and zero unbalanced journal groups. Results are `accounting-audit/evidence/backend-verification.json`. Manifest: `.omo/evidence/backend-controls/evidence.json` and audit copy `accounting-audit/evidence/backend-validation.json`.

Early boot timeout and singular-route404 probes were setup failures; they are retained in earlier backend-run folders but excluded from the consolidated evidence claims. Full suites and static checks are performed by the leader; this workstream changed only audit material, so it did not independently rerun either full suite.

Inventory reproduction: `python3 accounting-audit/tests/backend-inventory.py`; binary observable: 325 discovered non-test source paths with nonempty SHA256, imports and control-reference arrays; artifact `accounting-audit/evidence/backend-source-inventory.json`, command result `backend-inventory.log`. Utility/middleware/type files are mapped support dependencies, not independently validated workflows.

## Risk-priority extension: positive controls

Invocation `node accounting-audit/tests/backend-extension.cjs`, successful final run `accounting-audit/evidence/backend-extension-run-OF2b8i`, log `backend-extension-verified.log`. Fresh guarded DB independent from original finding fixtures.

| Scenario | Independent expected result / binary assertions | Observed | Artifacts in run directory |
|---|---|---|---|
| BACKEND-EXT-PRODUCTION-OVERHEAD-REVERSE | Consume6 units@10; overhead30; output quantities2/3 at price30/10 allocate60/30; GL inventory130, overhead payable−30, clearing0; DELETE returns all accounts to initial; repeat404 | PASS exact assertions, return200 then404 | 01-before-production.json;02-production-overhead.json;03-production-reversed.json;results.json |
| BACKEND-EXT-OWNER-DRAWINGS | Withdraw3 goods at cost10, selling price100: drawings30/inventory−30, no expense; withdraw cash50: drawings80/bank950; void both returns original accounts and10 raw units | PASS exact assertions | 04-owner-goods.json;05-owner-cash.json;06-owner-reversed.json;results.json |
| BACKEND-EXT-PHYSICAL-COUNT-CORRECT |10 units@10 counted8 yields stock8/inventory80/loss20; correction9 yields stock9/inventory90/loss10; second correction rejects4xx unchanged | PASS, repeated correction400 per actual controller contract |07-count-completed.json;08-count-corrected.json;09-count-repeat-rejected.json;results.json |

Integrity_check=ok, foreign_key_check=[], unbalanced journal groups=[] after all three. These are specific ordinary-case passes, not certification of all cost layers/feature flags/edits. Initial extension expected409 for the repeated count, but controller explicitly returns400; that harness expectation was corrected and the full extension rerun. No production test or business guard was weakened.

## Additional count findings

Invocation `node accounting-audit/tests/backend-count-risk.cjs`, final fresh run `accounting-audit/evidence/backend-count-risk-run-ZBybHv`, log `backend-count-risk-verified.log`, completed=true. F-024: count shortage8 across5@10+5@20; correcting remaining quantity2→8 returns500 because restoring8 to first5-unit batch violates its capacity constraint; DB rollback preserves value40/loss110. F-025: correcting only one item reverses a second item's shortage too, restoring stock10 while count row remains8; inventory overstated20 and loss understated20. See findings/F-024 and F-025 for precise independent expectations and source mechanism.

Verification `python3 accounting-audit/tests/backend-verify-extension.py` asserts all3 positive scenario outcomes, both count defect observables, existence of each checkpoint artifact, then opens the2 saved disposable DBs read-only and confirms integrity/FK/journal-group balance. Artifact `accounting-audit/evidence/backend-extension-verification.json`, console `backend-extension-verification.log`. Remaining unrun modes: owner withdrawal edit, feature_batch_locations enabled variants, expiry/warehouse movement interactions, count-surplus correction and concurrent requests.
