# Audit findings status

## Phase 0 baseline

- Branch: `audit-fixes`, created from `46ea0c93` (current user fixes preserved).
- Audited reference: `87f1265b`; no rollback to the audited commit.
- Report: `audit/MiniERP — Accounting, Code and Architecture Audit.md`.
- Existing regression files are preserved, including the modified `auditRegression2.test.ts` and `auditRegression3Recovered.test.ts`.
- Historical Phase 0 baseline follows. Phase 0b classifications and current evidence are recorded below; a passing test alone does not establish that the root cause is fixed.
- Before importing tests: 129 suites passed; 1,150 tests passed. Evidence: `/tmp/minierp-phase0-before.json` (669.153 seconds).
- Added missing `auditRegression3.test.ts` through `auditRegression8.test.ts`, initially byte-identical to `audit/tests/`. Only the subsequently approved PAY-001 assertion, test name, and header in regression 3 differ from those copies. Existing regression files were not modified.
- Targeted regression run: `Test Suites: 6 failed, 3 passed, 9 total`; `Tests: 38 failed, 52 passed, 90 total`; `Time: 90.03 s`. Evidence: `/tmp/minierp-phase0-regressions.json` and `/tmp/minierp-phase0-regressions.log`.
- After-import full suite (`cd server && npx jest --silent`): `Test Suites: 6 failed, 129 passed, 135 total`; `Tests: 38 failed, 1167 passed, 1205 total`; `Snapshots: 0 total`; `Time: 633.747 s, estimated 787 s`. Evidence: `/tmp/minierp-phase0-full.log`.
- All 129 pre-existing suites still pass. All 38 failures are in the six imported regression files. Apart from the PAY-001 specification conflict below, failure triage belongs to Phase 0b; no root-cause fix is claimed here.
- The user approved correcting the imported PAY-001 test to match D3. Correction verification passed; Phase 0 is complete and Phase 0b awaits the user's "go".

### Regression baseline by file (before the approved correction)

| File | Passed | Failed |
|---|---:|---:|
| auditRegression.test.ts | 18 | 0 |
| auditRegression2.test.ts | 9 | 0 |
| auditRegression3Recovered.test.ts | 8 | 0 |
| auditRegression3.test.ts | 7 | 1 |
| auditRegression4.test.ts | 0 | 11 |
| auditRegression5.test.ts | 1 | 3 |
| auditRegression6.test.ts | 5 | 8 |
| auditRegression7.test.ts | 3 | 7 |
| auditRegression8.test.ts | 1 | 8 |

### Resolved specification conflict: PAY-001

Implementation initially stopped under user rule 2. The user subsequently approved the test correction; production code remains unchanged.
The original assertion at `server/src/__tests__/auditRegression3.test.ts:150` required a 1,500 wages debit for a 1,500 payment against a 1,000 salary. Actual wages debit: 1,000; the preceding assertion for a 1,500 bank outflow passed.
`audit/DECISIONS.md:28-30` requires the excess to be an employee advance/receivable. Making wages equal 1,500 would conflict with D3. The pre-existing `auditRegression3Recovered.test.ts` passes all eight tests.
Its PAY-001 test at lines 129-146 explicitly verifies a 1,500 bank outflow, 1,000 wages debit, 500 advance debit to account 1310, and linked payment rows.
Approved correction: retain the 1,500 bank-outflow assertion, require 1,000 wages, and additionally require a 500 debit to advance account 1310. The test name and PAY-001 header now describe that split. The original audit copy remains untouched. No production finding is claimed fixed by this baseline; PAY-001 awaits Phase 0b root-cause triage.

### Approved PAY-001 correction verification

- Specific file: `npx jest --silent --runTestsByPath src/__tests__/auditRegression3.test.ts`.
- `Test Suites: 1 passed, 1 total`; `Tests: 8 passed, 8 total`; `Time: 21.322 s`.
- Evidence: `/tmp/minierp-pay001-regression.log`.
- Full suite (`npx jest --silent`): `Test Suites: 5 failed, 130 passed, 135 total`; `Tests: 37 failed, 1168 passed, 1205 total`; `Snapshots: 0 total`; `Time: 623.262 s, estimated 632 s`.
- Evidence: `/tmp/minierp-pay001-full.log`. The 37 remaining failures are confined to `auditRegression4` through `auditRegression8` (later phases). All 129 pre-existing suites and the corrected regression 3 pass.
- No production code changed. Finding classifications and production-fix commit SHAs remain pending Phase 0b, rather than treating a specification correction as a new production fix.

### Environment checks

- `npm ci`: passed after preserving the old dependency directory. Initial attempts failed with `ENOTEMPTY` on the existing native SQLite build directory.
- `npm run typecheck`: passed before importing missing audit tests.
- `npm run typecheck`: also passed after importing missing audit tests.
- `npm run typecheck`: passed again after the approved PAY-001 correction (`/tmp/minierp-pay001-typecheck.log`).
- `npm run lint`: unavailable; `server/package.json` has no `lint` script. No lint configuration was added during the baseline phase.
- The first full-suite attempt exceeded a 200-second tool timeout; it provides no test verdict. The replacement run uses a longer timeout and saves Jest JSON results.
- Preserved dependency remnants: `/tmp/minierp-audit-phase0-node_modules-20261013-0612` and sibling directory `../minierp-audit-phase0-native-preserved-20261013` (outside the repository).

## Phase 0b triage (2026-10-13)

Branch `audit-fixes`, HEAD `e46fc432`. No source/test changes and no commits in this phase, as required by the playbook. Only this tracker is updated. User changes and pre-existing audit-folder moves remain untouched.

55 entries: **8 ALREADY-FIXED, 3 DIVERGED-ACCEPTED, 6 PARTIAL, 33 NOT-FIXED, 5 UNCLEAR**. These are triage classifications, not new fix claims. Existing commit SHAs identify retained implementations; partial rows do not imply that the entire finding was fixed by that commit. Source-only findings have not received new regression9 tests or runtime probes in this read-only phase.

### Findings

Paths in evidence are repository files: models under `server/src/models/`, controllers under `server/src/controllers/`, accounting/report/backup/cash guard services under `server/src/services/`, validation/auth/upload under `server/src/middleware/`, purchaseValidation/currency/businessRuleError under `server/src/utils/`, database under `server/src/config/`, routes under `server/src/routes/`, and Dart repositories under `lib/data/repositories/`. Regression names below refer to `server/src/__tests__/*.test.ts`; finding labels identify the corresponding describe/test group.

| ID | Status | Existing fix commit SHA | Test name / proof | Evidence | Action needed |
|---|---|---|---|---|---|
| ACCT-001 | ALREADY-FIXED | 8badf489 | auditRegression ACCT-001 | Reports.ts:495-504 re-signs contra-asset balances; regression passes. | Keep existing fix. |
| ACCT-002 | GREEN | 8badf489 | auditRegression ACCT-002, auditRegression4 PROD-001G | Reports.ts keeps dynamic P&L account selection; PROD-001G now passes once production relieves raw inventory. | Verified by targeted and full-suite runs. |
| ACCT-003 | ALREADY-FIXED | 8badf489 | auditRegression ACCT-003 | Invoice.ts:659-664 uses unrounded return ratio before quantity rounding; regression passes. | Keep existing fix. |
| ACCT-004 | ALREADY-FIXED | 8badf489 | auditRegression ACCT-004 | accountingService.ts:313-315 checks closed periods before creating them; regression passes. | Keep modern posting guard; legacy gaps tracked separately. |
| ACCT-005 | DIVERGED-ACCEPTED | 3cab5c7d | auditRegression2 ACCT-005 | Purchase.ts:132-143 and purchaseValidation.ts:28-62 require an active supplier; SupplierPaymentService.ts:77-83 guards settlement funds; regression2 passes. | Keep mandatory-supplier policy; skip supplierless cash-purchase patch. |
| ACCT-006 | NOT-FIXED | — | Source reasoning; later new (auditRegression9) | validation.ts:104-119 accepts nonempty date strings; InvoiceCreationService.ts:96-104 lacks consistent date validation. Source reasoning only. | Add independent regression9 tests; agree permitted future-date bounds. |
| ACCT-007 | NOT-FIXED | — | Source reasoning; later new | InvoiceCreationService.ts:96-104 checks sign but not finite/upper bounds; currency.ts:130-152 lacks percentage maximum. Source reasoning only. | Define business bounds, then regression9 red-first. |
| ACCT-008 | NOT-FIXED | — | Source reasoning; later new | InvoiceCreationService.ts:154-161,203-205 deduplicates only when input.idempotency exists. Source reasoning only. | Add no-key duplicate-submit specification and regression9. |
| ACCT-009 | UNCLEAR | — | Source reasoning; later decision | accountingService.ts:784-818 posts expenses against cash; report also requests accruals, bills, input tax and advances without acceptance decisions. | Confirm which product capabilities to implement or defer in Phase 3i. |
| ACCT-010 | PARTIAL | 8f3431ad | Source reasoning; later new | Reports.ts:7-37 handles null due dates, but uses current invoice balance without historical receipt reconstruction or invoice cutoff. Source reasoning only. | Preserve null-date fix; test and implement historical AR. |
| ACCT-011 | DIVERGED-ACCEPTED | 3cab5c7d | apSingleDerivation.test.ts:131-155 (PASS) | Reports.ts:343-414 derives AP aging from ledger entries filtered through as-of date; apSingleDerivation.test.ts:131-155 covers later purchases/credits and passes in full suite. | Keep existing ledger-based implementation. |
| ACCT-012 | ALREADY-FIXED | 8badf489 | auditRegression2 ACCT-012 | SupplierPaymentService.ts:63-73 and Purchase.ts:296 rebuild supplier balances; regression passes. | Keep existing fix. |
| ACCT-013 | PARTIAL | f9a72d63 | auditRegression3 ACCT-013 | cashBalanceGuard.ts:10-35 checks chronological balances; regression3 passes. SupplierRefund.ts:213-249 and supplierRefundController.ts:141-156 void cash receipts without this guard. | Keep capital/payment guards; add supplier-refund reversal regression9 and guard. |
| PO-001 | ALREADY-FIXED | 8badf489 | auditRegression2 PO-001 | purchaseOrderController.ts:396-400 rejects nonnumeric, nonfinite, boolean and nonpositive quantities; regression passes. | Keep existing fix. |
| PRET-001 | ALREADY-FIXED | 8badf489 | auditRegression2 PRET-001 | PurchaseReturn.ts:314,350,364 rounds lines and total as money; regression passes. | Keep existing fix. |
| PRET-002 | PARTIAL | f31c511e / 3cab5c7d | Source reasoning; later new | PurchaseReturn.ts:643-657 creates an immediate cash SupplierRefund for refund_expected; supplierless purchases are now blocked and refund void handling at :792 is improved. Source reasoning only. | Preserve existing improvements; clarify expected refund versus confirmed receipt, then test. |
| PROD-001 | GREEN | 6eba103c | auditRegression4 PROD-001, PROD-001O, PROD-001G, PROD-001b | Material consumption now posts Dr production_clearing / Cr inventory_asset (`production_consume`), and overhead posts Dr production_clearing / Cr 2200 (`production_overhead`). All four regression4 cases pass. | Verified by targeted and full-suite runs. Joint-cost allocation for oil/cake remains unbuilt (see Phase 1 round5 notes). |
| PROD-002 | GREEN | 78e5c8e8 | auditRegression4 PROD-002 | Production.ts:341 posts roundCurrency(output_quantity * costPerUnit), matching batch value; its regression passes. | Verified by targeted and full-suite runs; preserve in subsequent patches. |
| PROD-004 | GREEN | 78e5c8e8 | auditRegression4 PROD-004 | Production.ts:144-147 rejects nonnumeric, nonfinite or negative overhead; its regression passes. | Verified by targeted and full-suite runs; preserve in subsequent patches. |
| PROD-005 | GREEN | 6eba103c | auditRegression4 PROD-005, PROD-005a, PROD-005b | Delete guards the period, refuses once output is partly moved, voids both `production_consume` and `production_overhead`, and restores batches with `skipAdjustmentFinancialPosting`. | Verified by targeted and full-suite runs. |
| PROD-006 | GREEN | 78e5c8e8 | auditRegression4 PROD-006, auditRegression5 WO-003 | Production rejects closed-period production before writes; round5 also added the shared `postLegacyStockEntry` period guard used by the new production postings. | Verified by targeted and full-suite runs; preserve in subsequent patches. |
| PROD-007 | GREEN | 78e5c8e8 | auditRegression4 PROD-007 | Production.ts:148-150 rejects identical input/output items; its regression passes. | Verified by targeted and full-suite runs; preserve in subsequent patches. |
| PAY-001 | DIVERGED-ACCEPTED | f9a72d63 | auditRegression3 PAY-001 + auditRegression3Recovered (PASS) | employeeController.ts:286-360 splits and links rows; accountingService.ts:1557-1597 posts salary/1310 advance once. Corrected regression3 and recovered regression pass. | Keep D3 implementation and add-salary-advance-link.sql migration. e46fc432 corrected only the approved test. |
| PAY-002 | PARTIAL | f9a72d63 | auditRegression3 PAY-002 | employeeController.ts:458-468 cascades parent void and regression3 passes; :443-445 rejects child void with 409. Playbook Phase 2c says voiding either should void both. | Preserve parent cascade; confirm whether parent-only correction is intended before changing child behavior. |
| PAY-003 | ALREADY-FIXED | f9a72d63 | auditRegression3 PAY-003 | accountingService.ts:1581-1583 and postLoanDisbursementEntry enforce funds; both regression3 cases pass. | Keep existing guards and funded fixtures. |
| PAY-004 | ALREADY-FIXED | f9a72d63 | auditRegression3 PAY-004 | employeeController.ts:777-827 validates salary deduction and posts repayment; account 1300 is loan receivable; regression3 passes. | Keep existing implementation. |
| WO-001 | GREEN | a8266f37 | auditRegression5 WO-001 (2 cases) | StockMovement.ts uses the batch's exact unit cost and rounds the write-off VALUE to currency precision; `postLegacyStockEntry` normalises every amount with `roundCurrency` and rejects a value that rounds to zero. All 4 regression5 tests pass. | Verified by targeted and full-suite runs. |
| WO-002 | NOT-FIXED | — | Source reasoning; later new | StockMovement.ts:1470-1471 insists on expired batches; inventoryController.ts:1004 handles expired flow only. Source reasoning only. | Regression9 first; add D7 damage reason and verify expense account mapping. |
| WO-003 | GREEN | 6eba103c | auditRegression5 WO-003 | Round5 added the shared `postLegacyStockEntry` closed-period guard, which covers write-offs and the new production postings; regression5 passes. | Verified by targeted and full-suite runs. |
| AUTHZ-001 | GREEN | pending | auditRegression9 AUTHZ-001 (3 cases) | A drift test walks `routes/`, `controllers/` and `middleware/` for every `requirePermission('m','a')` call and asserts each code exists in `permissions`. Migration `add-missing-guarded-permissions.sql` seeds the 17 genuinely absent codes; `stockBatches.ts` uses `inventory:update` per D5. | Verified by targeted and full-suite runs. |
| AUTHZ-002 | GREEN | 235b01ab | auditRegression7 AUTHZ-002 | Password and status mutations now protect admin targets; all 10 regression7 tests pass. | Verified by targeted and full-suite runs. |
| AUTHZ-003 | GREEN | 235b01ab | auditRegression7 AUTHZ-003 | Privileged role assignment requires the actor check that was previously missing. | Verified by targeted and full-suite runs. |
| AUTHZ-004 | GREEN | 235b01ab | auditRegression7 AUTHZ-004 | Permission grants now require the actor to possess the permission being granted. | Verified by targeted and full-suite runs. |
| REP-001 | GREEN | 32c13c05 | auditRegression6 REP-001 (3 cases) | Custom reports now require the entity's read permission to execute or list it; all regression6 cases pass. | Verified by targeted and full-suite runs. |
| REP-002 | GREEN | 32c13c05 | auditRegression6 REP-002 | HAVING fields are whitelist-enforced and computed aliases are protected in `reportQueryEngine`. | Verified by targeted and full-suite runs. |
| REP-003 | GREEN | 32c13c05 | auditRegression6 REP-003 | `entityRegistry` no longer advertises the nonexistent `stock_balances.id` and BOM quantity fields. | Verified by targeted and full-suite runs. |
| REP-004 | GREEN | 32c13c05 | auditRegression6 REP-004 | COUNT construction now carries the grouped/HAVING query structure while sharing the existing bindings. | Verified by targeted and full-suite runs. |
| REP-005 | NOT-FIXED | — | Source reasoning; later new | reportQueryEngine.ts:294-324 ignores requested group aggregates; :249 permits unbounded limit; :497-503 passes LIKE wildcards. Source reasoning only. | Regression9 first for aggregates, cap, literal wildcard matching. |
| FILE-001 | GREEN | 73b6ccfc | auditRegression8 FILE-001 (3 cases) | Employee document upload no longer trusts a supplied `file_path`, and deletion requires employee ownership; all 9 regression8 tests pass. | Verified by targeted and full-suite runs. |
| FILE-002 | GREEN | 73b6ccfc | auditRegression8 FILE-002 | Uploads validate extension and MIME, and employee documents are served as attachments rather than inline. | Verified by targeted and full-suite runs. |
| BK-001 | GREEN | 73b6ccfc | auditRegression8 BK-001 | The `VACUUM INTO` path is quoted, so a data path containing an apostrophe no longer breaks backup. | Verified by targeted and full-suite runs. |
| BK-002 | GREEN | 73b6ccfc | auditRegression8 'downloading a backup writes an audit row' | A backup download now writes a `BACKUP_DOWNLOAD` activity row like create/delete do, alongside the pre-existing dot-segment-safe `res.download`. | Verified by targeted and full-suite runs. |
| BK-003 | GREEN | 73b6ccfc | auditRegression8 'every backup the list shows can be downloaded and deleted' | The download path and the `backupService` name validator were reconciled, so any name the list returns is downloadable and deletable. | Verified by targeted and full-suite runs. |
| BK-004 | GREEN | 73b6ccfc | auditRegression8 'two backups requested back to back both succeed' | Backup filename timestamps are second-granular, so two backups in the same second no longer collide. | Verified by targeted and full-suite runs. |
| BK-005 | GREEN | 73b6ccfc | auditRegression8 BK-005 | `BACKUP_DIR` now overrides the backup location instead of always using `DB_DIR/backups`. | Verified by targeted and full-suite runs. |
| BK-006 | GREEN | 73b6ccfc | (docs; reviewer checks) | The restore runbook no longer copies from the wrong `../backups/` path. It copies from `backups/`, verifies integrity on the copy first, moves the live DB aside into `pre-restore/`, and swaps in only after the check passes, so a bad backup cannot destroy the live database. `BACKUP_DIR` is documented. | Documentation only; reviewed by reading the runbook, the destructive procedure was not executed. |
| BK-extra | NOT-FIXED | — | Source reasoning; later new | backupService.ts:91-137 backs up DB only; :58-82 lacks retention floor. Startup physical integrity/perms/encryption work has no acceptance proof. | D7 uploads and remaining backup hardening need independent regression9 coverage before fixes. |
| CODE-001 | PARTIAL | — | Source reasoning; later new | invoiceController.ts:253-272 maps some errors; businessRuleError.ts:34-52 misses plain Invalid quantity/unit price from InvoiceCreationService.ts:102-103, yielding 500. Source reasoning only. | Keep existing mappings; test remaining validation errors and return 4xx. |
| CODE-002 | NOT-FIXED | — | Source reasoning; later new | authController.ts:62-85 refreshes verified token claims without reloading current user/role state; auth.ts:103-110 also trusts JWT claims. Source reasoning only. | Regression9 for disabled users and changed roles; refresh current authority. |
| CODE-003 | NOT-FIXED | — | Source reasoning; later new | database.ts:365-375 retains nonproduction default admin123; userController.ts:56,156 accepts six-character passwords. Source reasoning only. | Preserve production default-password guard; define remaining password policy and regression9. |
| CODE-004 | NOT-FIXED | — | Source reasoning; later new (+ Flutter test) | invoice_repository.dart:292-317, owner_equity_repository.dart:77-102, employee_repository.dart:164-171 omit request keys; repository_client.dart:86-103 only forwards supplied headers. Source reasoning only. | Add stable per-submission keys and retry tests in Phase 3e. |
| CODE-005 | UNCLEAR | — | flutter analyze/test | Report groups CODE-005/006/007 rather than defining independent acceptance criteria. Large Flutter files remain; flutter analyze --no-pub passes. | Agree individual scope before Phase 5; no broad refactor during audit patches. |
| CODE-006 | UNCLEAR | — | flutter analyze/test | Grouped report observations include swallowed errors; catch sites differ in intent, including anonymous auth fallback. Analyzer success does not prove runtime feedback. | Select concrete error scenarios and acceptance tests before editing. |
| CODE-007 | UNCLEAR | — | flutter analyze/test | Grouped report observations include dynamic/late usage and lint strictness; current Flutter analysis has zero issues under current configuration. | Agree lint/type migration scope; do not equate counts with bugs. |
| DEPLOY-1 | UNCLEAR | — | seeded-fixture tests + dry-run review | Production material-relief defect persists in source; no production snapshot or historical repair dry run was provided. | Phase 4 needs agreed snapshot, fixture tests and reviewable dry run before historical writes. |

### Current verification

Each regression file was run independently with `npx jest --silent --runTestsByPath src/__tests__/<file>.test.ts`, followed by the full `cd server && npx jest --silent` run. Evidence logs: `/tmp/phase0b-<file>.log` and `/tmp/phase0b-full.log`.

| File | Jest suite summary | Jest test summary |
|---|---|---|
| auditRegression | Test Suites: 1 passed, 1 total | Tests: 18 passed, 18 total |
| auditRegression2 | Test Suites: 1 passed, 1 total | Tests: 9 passed, 9 total |
| auditRegression3 | Test Suites: 1 passed, 1 total | Tests: 8 passed, 8 total |
| auditRegression3Recovered | Test Suites: 1 passed, 1 total | Tests: 8 passed, 8 total |
| auditRegression4 | Test Suites: 1 failed, 1 total | Tests: 11 failed, 11 total |
| auditRegression5 | Test Suites: 1 failed, 1 total | Tests: 3 failed, 1 passed, 4 total |
| auditRegression6 | Test Suites: 1 failed, 1 total | Tests: 8 failed, 5 passed, 13 total |
| auditRegression7 | Test Suites: 1 failed, 1 total | Tests: 7 failed, 3 passed, 10 total |
| auditRegression8 | Test Suites: 1 failed, 1 total | Tests: 8 failed, 1 passed, 9 total |

Full suite:
```text
Test Suites: 5 failed, 130 passed, 135 total
Tests:       37 failed, 1168 passed, 1205 total
Snapshots:   0 total
Time:        699.869 s
```

All failures remain in regression4–8 and belong to subsequent fixes. Existing suites remain green. `npm run typecheck` passed (`/tmp/phase0b-typecheck.log`). `flutter analyze --no-pub`: `No issues found! (ran in 41.1s)`. `npm run lint` could not run: `Missing script: "lint"`; this is an unresolved repository check, not a lint pass. No runtime mobile/desktop QA is claimed for this source triage.

### Patch applicability and revised Phase 1 plan

Read-only `git apply --check` and `git apply --reverse --check` were run for all nine patch files. Failed checks were inspected by file/hunk, including in-memory prerequisite simulation. No patch was applied. “Forward/reverse” below reports current HEAD, before prerequisite patches.

| Order / patch | Forward / reverse | Revised action and exact conflict scope |
|---|---|---|
| 1. candidate-fixes-ACCT-001-004.patch | FAIL / PASS | **SKIP all hunks.** Invoice ratio hunk, Reports P&L/contra-balance hunks, and modern accounting closed-period hunk are already present. ACCT-002 remains PARTIAL solely because production is unresolved. |
| 2. candidate-fixes-round2-ACCT-012-PO-001-PRET-001.patch | FAIL / PASS | **SKIP all hunks.** Existing supplier-balance rebuild, PO numeric validation and purchase-return rounding match. |
| 3. candidate-fixes-round4-production-safe-subset.patch | PASS / FAIL | **Apply all 3 Production.ts hunks:** validation/self-production, unit-cost precision and associated amount precision. Run regression4 and full suite; remaining round5-dependent failures are expected until the next step. |
| 4. candidate-fixes-round5-PROD-001-PROD-005.patch | PASS / FAIL | **Apply 5 Production.ts hunks and 1 accountingService.ts hunk for material relief, deletion integrity and legacy closed-period validation**, subject to D6 clarification below before accepting overhead accounting. Preserve existing transactions and GL voids. Run regression4 (including PROD-001G), regression5 for the shared legacy guard, and full suite. Do not declare all of D6 satisfied by these tests. |
| 5. candidate-fixes-round6-WO-001.patch | FAIL / FAIL | **StockMovement.ts: apply both hunks. accountingService.ts: adapt the 3 rounding hunks.** The first becomes applicable after round5. The last 2 conflict with the existing transaction wrapper introduced in 46ea0c93; put monetary rounding inside the retained wrapper. Never replace it with the patch's old nontransactional structure. Run regression5 and full suite. |
| 6. candidate-fixes-round7-REP-001-004.patch | PASS / FAIL | **Apply all 12 hunks:** customReportsController.ts (4), auth.ts (1), entityRegistry.ts (3), reportQueryEngine.ts (4). Run regression6 and full suite. |
| 7. candidate-fixes-round8-AUTHZ-002-004.patch | FAIL / FAIL | **Apply all 11 hunks after round7:** rolesController.ts (3), userController.ts (7), auth.ts (1). Only middleware prerequisite context prevents current application; all hunks match in-memory after round7. Run regression7 and full suite. |
| 8. candidate-fixes-round9-FILE-001-002-BK-001-005.patch | FAIL / FAIL | **Apply 13 clean hunks; adapt the 1 adminBackup.ts hunk.** Clean files: server/README.md (2), employeeController.ts (2), upload.ts (2), employees.ts (1), activityLogger.ts (1), backupService.ts (5). Add download audit logging while retaining `res.download(target, path.basename(target), { dotfiles: 'allow' }, callback)` from 8ed73cf2. Run regression8 and full suite; review BK-006 restore path separately. |
| policy-patch-ACCT-005-cash-purchase-funds-guard.patch (Phase 2a) | PASS / FAIL | **SKIP entirely.** User's mandatory-active-supplier policy removes this supplierless path; valid supplier payments already enforce funds. |

For any actual application failure in Phase 1, first attempt `git apply --3way`; if a hunk still fails, implement its missing intent and record the exact deviation. Commit once per applied finding group with IDs, run the relevant file and full suite after every step, and update this tracker. Do not create commits for skipped groups. These are proposed future actions, not completed patches.

### Existing changes to preserve and unresolved decisions

- **ACCT-002 / PROD-001:** preserve dynamic P&L account selection. Current production consumes physical material without relieving raw inventory in GL, so the passing original P&L regression is insufficient.
- **ACCT-005:** preserve mandatory supplier validation rather than reintroducing supplierless purchases.
- **ACCT-010 / ACCT-011:** preserve null-due-date AR handling and the ledger-based AP as-of implementation.
- **ACCT-013:** preserve the chronological cash guard; extend missing reversal paths only after new red tests. The supplier-refund controller directly invokes the unguarded model void.
- **PAY-001/002:** preserve the 1310 advance split and parent cascade. The playbook's “voiding either voids both” conflicts with the current deliberate child-void rejection, while D3 merely says void together. **Decision needed before Phase 2c:** keep parent-only voiding, or let voiding the child cascade to the parent too?
- **D6 / round5:** D6 requires manufacturing overhead capitalization and no duplicate expense, but does not state whether these costs are already expensed before production. The candidate patch credits production variance/7000 and does not establish the origin of overhead or a mustard oil/cake joint-cost method. **Decision needed before the production accounting step:** are entered overhead costs already posted as expenses, and which joint-cost allocation basis should be used for oil/cake? Do not silently substitute a cash/payable offset or claim the audit patch implements the complete D6 policy.
- **Legacy posting:** retain the atomic journal header/lines transaction from 46ea0c93 while adapting rounding.
- **Backup download:** retain 8ed73cf2 dot-directory support while adding activity logging.
- **Later product scope:** date/bound limits (ACCT-006/007), expected versus received supplier refunds (PRET-002), scope of accrual/bill/tax/advance support (ACCT-009), password policy (CODE-003), and individual Flutter acceptance criteria (CODE-005/006/007) need decisions before their respective phases. Source reasoning identifies risks, not invented business rules.
- **Historical data (DEPLOY-1):** no live database was repaired or assessed. Phase 4 needs a selected snapshot and reviewable dry run; do not infer historical correctness from current test fixtures.

Phase 0b completed. The user authorized Phase 1 and then clarified D6: overhead is not separately expensed, accrues as an unpaid payable, and joint costs use relative sales value. The user explicitly approved correcting PROD-001O's separate-expense fixture while retaining profit 950 and adding exactly-once overhead assertions. These current decisions supersede the open D6 questions in the historical triage above.

## Phase 1, round4 production safe subset

- Commit: `78e5c8e8` (`fix(audit): address PROD-002 PROD-004 PROD-006 PROD-007`).
- Skipped the already-applied first two patch bundles. Applied all three round4 hunks cleanly, without changes to the candidate patch or regression tests.
- This patch aligns output GL value with quantity times the stored rounded unit cost; it does not increase unit-cost precision. It also adds the production-level period guard, earlier than the shared legacy guard in round5.
- Targeted `auditRegression4.test.ts`: `Test Suites: 1 failed, 1 total`; `Tests: 7 failed, 4 passed, 11 total`; `Time: 14.552 s`.
- Full `npx jest --silent`: `Test Suites: 5 failed, 130 passed, 135 total`; `Tests: 33 failed, 1172 passed, 1205 total`; `Snapshots: 0 total`; `Time: 567.402 s, estimated 697 s`.
- Remaining failures are round5 material relief/deletion plus round6–9 targets; all four round4 targets pass. Logs: `/tmp/phase1-round4-targeted.log`, `/tmp/phase1-round4-full.log`.
- Typecheck and `git diff --check` passed. Lint command remains unavailable (missing script). No UI or schema change in this step.
- Source commit contains only Production.ts. This tracker records its actual SHA after the commit; audit-folder moves remain untouched.
- D6 joint-cost allocation cannot be implemented by the supplied patch alone: CreateProductionDTO currently supports one output item. Relative-sales-value allocation is recorded for follow-up; do not declare the entire D6 finding fixed merely because single-output regressions pass.

## Phase 1, round5 material relief, deletion integrity, unpaid overhead

- Targeted `auditRegression4.test.ts` + `auditRegression9.test.ts`: `Test Suites: 2 passed, 2 total`; `Tests: 12 passed, 12 total`; `Time: 61.356 s`.
- Full `npx jest --silent`: `Test Suites: 4 failed, 132 passed, 136 total`; `Tests: 25 failed, 1181 passed, 1206 total`; `Snapshots: 0 total`; `Time: 865.126 s`.
- Remaining failures are only round5 auditRegression5 (expired-stock write-off) and round6-8 targets. Full-suite failures fell from 37 to 25. Logs: `/tmp/phase1-round5-full.log`.
- Typecheck passed. Lint command remains unavailable (missing script). No UI change in this step.

### Deviations from the candidate round5 patch

1. **Overhead source, per D6 as clarified by the user.** Overhead is NOT a separately recorded expense, so the patch's silent treatment of it (7000 keeping a net credit equal to the absorbed overhead, which inflated profit) is not acceptable. Production now accrues it itself: `Dr production_clearing / Cr 2200`, keyed `production_overhead` so delete voids it. Cash and bank are untouched, matching the "unpaid until settlement" decision.
2. **New liability account 2200 `Accrued Production Overhead`** (`text_code = production_overhead_payable`), added by migration `add-production-overhead-payable.sql` and registered in `config/database.ts` with a boot assertion. A dedicated liability was required rather than reusing 2000 (Accounts Payable): `Reports.ts` reconciles GL 2000 against the supplier ledger, so accruing overhead there would report a phantom AP delta. The migration and boot assertion are additions, not part of the supplied patch. **Confirm the account code/name is acceptable.**
3. **Approved test correction applied.** `auditRegression4.test.ts` PROD-001O no longer posts a separate 6000 expense (it previously counted the same cost twice once production absorbed it); it now asserts the 2200 accrual, unchanged cash/bank, a neutral 7000 and profit 950. No other supplied assertion was changed.
4. **New regression file `auditRegression9.test.ts`** covers the reversal the supplied tests did not: deleting an intact production restores the 2200 payable and leaves cash and bank unchanged. It was shown red before the overhead posting existed.

### Still outstanding for D6

- Joint-cost allocation between mustard oil and mustard cake by relative sales value is **not implemented**: `CreateProductionDTO` accepts a single output item, so there are no co-products to allocate between. Single-output production, material relief, overhead accrual and deletion integrity are fixed; do not treat D6 as fully closed.
- No settlement path (paying the 2200 payable) was requested or built.

## Phase 2, round6 expired-stock write-off precision

- Targeted `auditRegression5.test.ts`: `Test Suites: 1 passed, 1 total`; `Tests: 4 passed, 4 total`; `Time: 26.987 s`.
- Full `npx jest --silent`: `Test Suites: 3 failed, 133 passed, 136 total`; `Tests: 23 failed, 1183 passed, 1206 total`; `Snapshots: 0 total`; `Time: 751.608 s`. Failures fell from 25 to 23; only regressions 6-8 remain. Log: `/tmp/phase2-round6-full.log`.
- Typecheck passed. Lint command remains unavailable (missing script).

### Deviation from the candidate round6 patch

`git apply --3way` reported the `StockMovement.ts` hunk as clean but then aborted the whole patch because `accountingService.ts:481` no longer matched, so nothing was written. Both hunks were therefore applied by hand to identical content:

1. `StockMovement.ts` imports `roundCurrency` and computes `value = roundCurrency(qty * unitCost)` from the batch's unrounded `unit_cost`.
2. `accountingService.postLegacyStockEntry` rounds the amount once via `roundCurrency` and throws when it rounds to zero, then uses that value for the header and both lines.

The hunk context had shifted because round5 inserted the closed-period guard into `postLegacyStockEntry`; the patch's own content was otherwise unchanged.

## Phase 2, round7 custom report engine

- Targeted `auditRegression6.test.ts`: `Test Suites: 1 passed, 1 total`; `Tests: 13 passed, 13 total`; `Time: 42.708 s`.
- Full `npx jest --silent`: `Test Suites: 2 failed, 134 passed, 136 total`; `Tests: 15 failed, 1191 passed, 1206 total`; `Snapshots: 0 total`; `Time: 662.787 s`. Failures fell from 23 to 15; only regressions 7-8 remain. Log: `/tmp/phase2-round7-full.log`.
- Typecheck passed. All four files applied cleanly with `git apply --3way`; no deviation from the supplied patch.
- **REP-005 is still open** and was deliberately not touched: the supplied patch does not address group aggregates, the unbounded limit, or the remaining items recorded against it. It has no regression test yet, so it needs one written before any fix (see below).

## Phase 2, round8 privilege escalation

- Targeted `auditRegression7.test.ts`: `Test Suites: 1 passed, 1 total`; `Tests: 10 passed, 10 total`; `Time: 26.956 s`.
- Full `npx jest --silent`: `Test Suites: 1 failed, 135 passed, 136 total`; `Tests: 7 failed, 1199 passed, 1206 total`; `Snapshots: 0 total`; `Time: 568.617 s`. Failures fell from 15 to 7; only regression8 remains. Log: `/tmp/phase2-round8-full.log`.
- Typecheck passed. All three files applied cleanly with `git apply --3way`; no deviation from the supplied patch.
- **AUTHZ-001 is still open** and was not touched: `seedDefaultPermissions` lacks the audit's requested permission codes, and it has no regression test yet.

## Phase 2, round9 employee documents and backups

- Targeted `auditRegression8.test.ts`: `Test Suites: 1 passed, 1 total`; `Tests: 9 passed, 9 total`; `Time: 27.751 s`.
- **Full `npx jest --silent`: `Test Suites: 136 passed, 136 total`; `Tests: 1206 passed, 1206 total`; `Snapshots: 0 total`; `Time: 644.458 s`.** The suite is fully green. Log: `/tmp/phase2-round9-full.log`.
- Typecheck passed. All seven files applied cleanly with `git apply --3way`.
- **Rule 10 check on `adminBackup.ts`:** Phase 0b recorded this file as the one mismatching hunk, so it was inspected before staging. The patch's change is purely additive (a `BACKUP_DOWNLOAD` activity-log entry) and sits above your `dotfiles: 'allow'` download fix; your comment block and `res.download` call are unchanged. Your fix is preserved.
- `server/README.md` was amended by the patch to document `BACKUP_DIR` and the new document-download rules.

## Remaining open findings (no regression test yet)

These have no failing test because none was supplied. Per the rules each needs a test written
and shown red before any fix, so they are NOT part of the green suite above:

| Finding | Why still open |
|---|---|
| AUTHZ-001 | `seedDefaultPermissions` lacks the audit's requested permission codes. Needs the exact code list confirmed before implementation. |
| REP-005 | Group aggregates ignored, unbounded limit, and further items in `reportQueryEngine`. Needs a test per sub-item. |
| WO-002 | `StockMovement` insists on expired batches and `inventoryController` handles the case; no test encodes the intended behaviour yet. |
| CODE-005..007 | Flutter client quality observations (large files, error handling). `flutter analyze` passes; the audit itself did not run it. |
| D6 joint-cost allocation | Mustard oil/cake allocation by relative sales value is unimplemented: `CreateProductionDTO` accepts a single output item. Needs a schema decision first. |
| Phase 1 deviation | The 2200 `Accrued Production Overhead` account code/name still needs the user's confirmation. |

## Tracker correction, BK-002 / BK-003 / BK-004

The Phase 0b rows for BK-002, BK-003, BK-004 and BK-006 still read NOT-FIXED, but each names an
`auditRegression8` case or a README check that the round9 patch addressed. All four are marked GREEN
with commit `73b6ccfc`. No code changed; this only corrects the tracker. BK-002..004 are covered by
passing regression8 tests; BK-006 is documentation and was verified by reading the runbook.

## Phase 3, AUTHZ-001 guarded permissions that could not be granted

- Red first: the new drift test reported 19 codes guarded by a route but absent from `permissions`,
  and `stockBatches.ts` still used `inventory:write`. Then green after the fix.
- Targeted `auditRegression9.test.ts`: `Test Suites: 1 passed, 1 total`; `Tests: 4 passed, 4 total`.
- Full `npx jest --silent`: `Test Suites: 136 passed, 136 total`; `Tests: 1209 passed, 1209 total`;
  `Snapshots: 0 total`; `Time: 714.323 s`. Log: `/tmp/phase3-authz001-full.log`.
- Typecheck passed.

### The audit's list was stale; the drift test found the real set

The audit reported 14 unassignable codes. Measuring the current tree gives **17 codes that were
genuinely absent**, because the audit predates later work:

| Code | Why the audit's list did not match |
|---|---|
| `admin:read/create/delete` | Audit wrote `admin:*` generically; only 3 codes exist |
| `owner_equity:read/create/edit/delete` | Audit wrote `owner_equity:*`; 4 codes exist, and `edit` is an action the audit never named |
| `dashboard:create/update/delete` | **Not in the audit's list at all** - these guards were added later |
| `accounting:update`, `expenses:delete`, `forecasts:delete`, `invoices:void`, `reports:create/update/delete` | Present in the audit's list |
| `inventory:write` | Audit listed it; D5 retires it, so it is renamed away rather than seeded |
| `activity_log:purge` | Audit did not list it; a migration already seeds it, so it was correctly excluded |

Seeding `reports:create` also activates a previously dormant block in
`seedDefaultPermissions` that grants `reports:create` to the **Manager** role. It is a no-op in
tests because no migration creates a Manager role, but on any real installation that has one it
would hand out a permission D5 says to grant to nobody. **Left unchanged - needs a user decision.**

### Decisions still needed from the user

1. **`reports:create` to Manager.** Keep the dormant grant (the role needs to author reports) or
   remove it to honour D5's "grant none by default"?
2. **D5's "seed admin:* and owner_equity:* as sensitive permissions" is unimplemented.** The
   `permissions` table has no sensitivity column and `requirePermission` has no notion of sensitive
   modules, so "sensitive" has no defined enforcement. Options: add an `is_sensitive` column and
   enforce it, treat it as description text only, or drop the bullet. **Not guessed.**
3. **AUTHZ-001 grant exception.** The migration grants the new codes to the **Admin** role only.
   `seedDefaultPermissions` grants Admin every permission but only when the role has none, so an
   existing installation would otherwise lose access to `owner_equity:*`, `admin:*`, `dashboard:*`
   and `invoices:void`. D5's "grant none by default" is read as protecting non-Admin roles; the
   test asserts exactly that. Confirm this reading.
