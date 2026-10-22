# Resolve the complete Fallow report without changing ERP behavior

## TL;DR
> Summary: Inspect and account for all 63 dead-code findings, 39 duplicate groups, and 238 health findings in the captured Fallow 3.34.1 report. Remove confirmed dead code, extract coherent shared operations, reduce structural complexity, and repair coverage mapping before deciding which remaining health findings need tests.
> For whom: MiniERP maintainers receive a complete, evidence-backed disposition; desktop and API users retain accounting, inventory, validation, authorization, and reporting behavior.
> Deliverables: source refactors; corrected test coverage mapping; complete finding ledger; targeted and full server verification.
> Effort: XL
> Risk: High - transaction ordering and financial invariants span controllers, models, services, and historical migration utilities.

## Scope
### Affected user and ideal state
**Affected user:** Maintainers currently see a mixture of actionable complexity and duplication, live-symbol false positives, persisted vocabulary, and unreliable coverage estimates. After this work every original finding has a supported disposition, useful duplication and complexity are resolved, and fresh coverage describes TypeScript source. ERP users continue the same workflows and receive the same financial results and API responses.

| Row | Statement | Reason |
|-----|-----------|--------|
| IS-1 | All 340 original report entries are individually accounted for. | A smaller headline count cannot establish that every issue was checked. |
| GAP-1 | The captured report contains 63 dead-code, 39 duplicate, and 238 health entries without a final remediation ledger. | Work can otherwise silently omit findings or count overlapping clones twice. |
| IS-2 | Reachable APIs and persisted action vocabulary remain available; genuinely unused code is removed. | Static member detection does not establish runtime reachability or historical data meaning. |
| GAP-2 | Two dead-code entries identify the same unused `AccountingService.openPeriod`; 33 class entries are live and 28 enum entries describe persisted vocabulary. | Bulk deletion would break useful code or erase documented meanings. |
| IS-3 | Every structural finding is resolved through a coherent operation with bounded complexity. | Maintainability improves only when extraction produces understandable responsibilities. |
| GAP-3 | 75 original functions exceed cyclomatic 20 or cognitive 15. | The complexity is concentrated in transactional and validation code. |
| IS-4 | Shared behavior has one implementation while distinct SQL and business policies remain explicit. | Clone similarity alone cannot justify merging different operations. |
| GAP-4 | 39 overlapping clone groups mix reusable operations with different SQL and policies. | Unselective abstraction risks policy changes and hides domain logic. |
| IS-5 | Coverage and CRAP decisions use current, correctly mapped TypeScript locations. | Incorrect line mapping can label exercised code as uncovered. |
| GAP-5 | 163 original health entries are CRAP-only; the production compiler disables source maps. | Their status must be recomputed after configuring test-only source maps. |
| IS-6 | Accounting, stock, reversals, security, response shapes, and write ordering retain observed behavior. | This cleanup must not become a product or data migration. |
| GAP-6 | Refactoring touches critical paths whose current test baseline is not yet established. | Verification must distinguish regressions from existing failures. |

### Must have
- Input of record: `audit/fallow-tools/fallow-before-20261021.json`; temporary copy: `/tmp/minierp-fallow-before-20261021.json`.
- Stable IDs use original section, path, symbol and line; duplicate groups use their fingerprint. Preserve the original report and group ordering.
- Complete ledger under a new dated path, such as `audit/fallow-remediation-2026-10-21.md`, maintained by the root executor. Every row records owner, evidence, action, final status, and a concrete reason if retained.
- Resolve all 75 structural findings, including findings in test fixtures, scripts, routes, migrations, and database bootstrap.
- Reassess every original CRAP-only finding after fresh source-mapped coverage; add meaningful tests for genuine reachable gaps. Track any new findings introduced by extraction as part of completion.
- Read `CODING_STANDARDS.md:20`, `docs/REVERSAL-RULES.md:14`, `audit/DECISIONS.md:243`, and `audit/DECISIONS.md:321` before editing.

### Must NOT have (guardrails, anti-slop, scope boundaries)
- No blanket suppressions, disabled categories, threshold increases, or replacement baselines used to claim success. Preserve the existing D14 enforcement policy.
- No wrappers created solely to move a warning, arbitrary boolean-driven universal helpers, weakened tests, altered SQL predicates, changed error precedence, or moved writes outside their transaction.
- No live database repair or re-audit of known dummy historical gaps. Use fresh fixture databases.
- Preserve unrelated user files: `audit/README.md`, `audit/baseline/`, `audit/coverage_checklist.md`, `audit/execution_log.jsonl`, and `audit/reports_exported/`.
- No Flutter changes unless an actual shared-contract regression requires them. No commits are requested; leave reviewed working changes for the user.

## Verification strategy
> Zero human intervention - all verification is agent-executed.
- Test decision: existing Jest regression tests before and after behavior-preserving extraction; TDD for a newly discovered defect; new tests only for meaningful missing behavior or financial/security invariants.
- QA policy: every task executes the named scenarios; controller changes exercise mounted Express routes with real bodies, and database changes use fresh databases and assert rollback as well as success.
- Evidence: `<attemptDir>/task-<N>-<slug>.<ext>`; outside ulw-loop use `.omo/evidence/`. Under ulw-loop, use `currentAttemptDir` from `omo-agent-toolkit ulw-loop status --json`.
- Run commands from `server/` unless stated otherwise. Existing package scripts are defined at `server/package.json:11`; Jest setup and database isolation start at `server/jest.config.js:13`.
- Before source changes establish the directly affected suites' baseline. Record exact failures and investigate rather than weakening assertions. At final integration run the complete server suite with coverage, typecheck, lint, reversal verification, and Fallow. Preserve logs even on failure.
- Fallow raw report may remain nonzero for documented live-symbol and intentional duplication findings. A passing baseline comparison alone is insufficient; final acceptance requires all original rows resolved or specifically justified and no unreviewed new findings.

## Execution strategy
### Parallel execution waves
> Target 5-8 tasks per wave. This repository uses four concurrent slots and three disjoint worker ownership areas; ownership safety takes precedence over artificially splitting files among concurrent workers.

Wave 1 (no dependencies; root preparation):
- Task 1: establish finding inventory, coverage mapping, and dead-code removal; announce the accountingService handoff.

Wave 2 (after Task 1; root plus three high-difficulty workers):
- Task 2: all controller findings and controller helpers.
- Task 3: all model findings, sequence utilities, and shared document-date helper.
- Task 4: all service findings.
- Task 5: root handles scripts, migrations, configuration, routes, middleware, test-fixture complexity, and remaining utilities.

Wave 3 (after Tasks 2-5):
- Task 6: regenerate coverage and finish remaining true coverage/CRAP findings with the same ownership assignments.
- Task 7: complete ledger and integration verification after Task 6.

Critical path: Task 1 -> Tasks 2-5 -> Task 6 -> Task 7.

### Dependency matrix
| Task | Depends on | Blocks | Can parallelize with |
|------|------------|--------|----------------------|
| 1 | none | 2,3,4,5 | none |
| 2 | 1 | 6 | 3,4,5 |
| 3 | 1 | 6 | 2,4,5 |
| 4 | 1 | 6 | 2,3,5 |
| 5 | 1 | 6 | 2,3,4 |
| 6 | 2,3,4,5 | 7 | internal disjoint ownership lanes |
| 7 | 6 | F1-F4 | none |

Shared-file rule: root owns the ledger, Jest configuration, and common test setup. Model worker owns `server/src/utils/sequence.ts`, any document-number helper, and any shared date-prefix helper. Controller worker requests the helper signature before importing it; preserve each caller's UTC/local parsing and fallback semantics. Service worker edits `accountingService.ts` only after root confirms `openPeriod` removal is complete. Existing test files have a single assigned editor; root resolves overlapping requested assertions. Workers must preserve other workers' changes.

## Todos
> Implementation + Test = ONE task. Each lane is implemented in individual coherent extractions; do not batch unverified behavior changes until the end of the lane.

- [ ] 1. Establish an honest baseline and remove the one confirmed dead method

  What to do: root enumerates the captured JSON into the ledger; records 75 structural and 163 CRAP-only entries using `cyclomatic > 20 || cognitive > 15`; configures Jest to use a test-only tsconfig with `sourceMap: true`, preserving production tsconfig; verifies source mapping using actual covered function locations; checks all references before deleting `AccountingService.openPeriod`; records both duplicate dead-code entries as one removal. Keep all 33 live class findings and 28 persisted enum findings with individual evidence and D13 reasons. Root may already have started these edits: reconcile the current working files before acting.
  Must NOT do: change production source-map policy, delete persisted vocabulary, alter audit baseline files, or let the services worker race root in accountingService.
  Closes: GAP-1, GAP-2, GAP-5, GAP-6.

  Parallelization: Can parallel: NO | Wave 1 | Blocks: [2,3,4,5] | Blocked by: []

  References:
  - Pattern: `server/jest.config.js:7` - ts-jest transform owns test compiler options.
  - API/Type: `server/tsconfig.json:20` - production source maps disabled.
  - Evidence: `.fallowrc.json:40` - configured coverage input; `audit/DECISIONS.md:243` - retained vocabulary; `audit/DECISIONS.md:321` - gate policy.
  - Test: `server/src/__tests__/accountingPeriodRoller.test.ts`, `server/src/__tests__/accountingInvariants.test.ts`.

  Acceptance criteria:
  - [ ] Ledger has 63 + 39 + 238 original entries, including duplicate reports of the same symbol.
  - [ ] `npm test -- --runInBand --coverage --runTestsByPath src/__tests__/accountingPeriodRoller.test.ts src/__tests__/accountingInvariants.test.ts` passes or establishes an explicitly investigated existing failure.
  - [ ] Coverage function/statement locations are within the current `.ts` file and known exercised functions have nonzero hits; mapping checks cover a multi-line method, an arrow callback, and a branch.
  - [ ] `npm run typecheck` passes after the dead method removal.

  QA scenarios:
  ```
  Scenario: Correct source mapping and intact accounting period lifecycle
    Tool: bash
    Steps: npm test -- --runInBand --coverage --runTestsByPath src/__tests__/accountingPeriodRoller.test.ts src/__tests__/accountingInvariants.test.ts
    Expected: suites pass; inspect coverage-final.json locations against current TypeScript; record exact matching functions and hit counts.
    Evidence: <attemptDir>/task-1-source-mapping.log
  Scenario: Closed-period and insufficient-funds rejection
    Tool: bash
    Steps: npm test -- --runInBand --runTestsByPath src/__tests__/accountingPeriodRoller.test.ts src/__tests__/accountingInvariants.test.ts
    Expected: existing rejection and rollback assertions remain green; no unexpected ledger writes.
    Evidence: <attemptDir>/task-1-accounting-errors.log
  ```

  Commit: NO | Message: `fix(test): map coverage to TypeScript sources` | Files: [`server/jest.config.js`, `server/tsconfig.test.json`, `server/src/services/accountingService.ts`, `audit/fallow-remediation-2026-10-21.md`]

- [ ] 2. Resolve controller complexity and controller duplication

  What to do: controller worker owns `server/src/controllers/**` and new controller-only helpers. Extract request normalization, reusable entity lookups, pagination/filter parsing, salary/date validation, receipt assembly, and report-config validation only where contracts match. Resolve all 23 structural entries listed below. Resolve duplicate groups 1,2,3,5,8,9,10,11,12,14,16,18,22,23,24,25,26,29,30,34,36,37,38,39; overlapping groups may share one extraction but every original group gets a disposition. Retain group 27 (`dup:c79c25b2`) with the concrete differences in missing-date defaults. Coordinate date helpers with Task 3. Add or extend route tests for extracted request paths, including malformed values, authorization, and errors after transaction entry.
  Must NOT do: broaden accepted request values, change response bodies/status codes, merge differently defaulted report policies, or move validation after writes.
  Closes: GAP-3, GAP-4, GAP-6.

  Parallelization: Can parallel: YES | Wave 2 | Blocks: [6] | Blocked by: [1]

  References:
  - Pattern: `server/src/controllers/employeeController.ts:65`, `server/src/controllers/inventoryController.ts:15` - repeated lookup and request operations.
  - API/Type: `server/src/controllers/mobileInvoiceController.ts:149`, `server/src/controllers/invoiceController.ts:200` - submission contracts.
  - Test: `server/src/__tests__/api.integration.test.ts`, `server/src/__tests__/invoiceIdempotency.test.ts`, `server/src/__tests__/ownerPersonalLoans.test.ts`, `server/src/__tests__/salaryAtomicDeduction.test.ts`.
  - Full structural references: preferencesController.ts:49; productionController.ts:10; mobileInvoiceController.ts:249,149; invoiceController.ts:1081,504,450,200; customReportsController.ts:55; employeeController.ts:890,354; paymentsController.ts:418,561; posController.ts:210; userController.ts:110; ownerPersonalLoansController.ts:662; purchaseController.ts:71; inventoryController.ts:1020; expenseController.ts:283; ownerEquityController.ts:284,448; purchaseOrderController.ts:363,18. All paths are under `server/src/controllers/`; lines refer to the captured report.

  Acceptance criteria:
  - [ ] All 23 original structural entries resolve to functions below both thresholds, with useful names and unchanged transaction/error ordering.
  - [ ] Every assigned clone group is resolved or retained with an instance-specific semantic reason.
  - [ ] `npm run typecheck` and applicable mounted-route suites pass; add concrete missing edge cases where extraction changes a shared path.

  QA scenarios:
  ```
  Scenario: Mounted API and invoice creation contracts
    Tool: bash
    Steps: npm test -- --runInBand --runTestsByPath src/__tests__/api.integration.test.ts src/__tests__/invoiceIdempotency.test.ts src/__tests__/ownerPersonalLoans.test.ts
    Expected: mounted route success bodies, authorization, and idempotency assertions pass.
    Evidence: <attemptDir>/task-2-controllers.log
  Scenario: Salary and owner loan rejection remains atomic
    Tool: bash
    Steps: npm test -- --runInBand --runTestsByPath src/__tests__/salaryAtomicDeduction.test.ts src/__tests__/ownerPersonalLoans.test.ts src/__tests__/accountingInvariants.test.ts
    Expected: invalid requests and insufficient funds produce existing expected errors and leave balances/rows unchanged.
    Evidence: <attemptDir>/task-2-controllers-error.log
  ```

  Commit: NO | Message: `refactor(controllers): extract shared request operations` | Files: [`server/src/controllers/**`, controller-owned targeted test files]

- [ ] 3. Resolve model complexity and atomic document numbering duplication

  What to do: model worker owns `server/src/models/**`, `server/src/utils/sequence.ts`, and new document-number/date helpers. Resolve all 25 structural entries below. Resolve groups 6,7,15,17,21,31 and the genuinely shared month formatting part of group 19 (`dup:a3471acf`). Retain distinct transaction bodies in group 19 and distinct SQL groups 4 (`dup:4d3320a0`), 20 (`dup:e2a1deae`), and 35 (`dup:b49eb11a`) with exact differences. Extract coherent stock allocation, return costing, posting parameter assembly, and transaction stages while retaining the enclosing transaction and write order. Publish shared date helper contract early, preserving caller-specific semantics.
  Must NOT do: replace prepared SQL with concatenated input, make document numbering non-atomic, change valuation/FEFO/FIFO behavior, or combine SQL merely because fragments look similar.
  Closes: GAP-3, GAP-4, GAP-6.

  Parallelization: Can parallel: YES | Wave 2 | Blocks: [6] | Blocked by: [1]

  References:
  - Pattern/API: `server/src/utils/sequence.ts:27`; `server/src/models/Production.ts:174`, `server/src/models/Purchase.ts:126`, `server/src/models/PurchaseOrder.ts:226` - sequence/number generation.
  - Test: `server/src/__tests__/physicalCountBatchSync.test.ts`, `server/src/__tests__/purchaseReturn.test.ts`, `server/src/__tests__/stockTransferVoid.test.ts`, `server/src/__tests__/reversalSymmetry.test.ts`.
  - Full structural references under `server/src/models/`: PhysicalCount.ts:510,305; Expense.ts:179; SalesOrder.ts:115,411; Production.ts:240,736; Quotation.ts:117,400; Dashboard.ts:448; PurchaseReturn.ts:759,301,564; Payment.ts:562,181; StockMovement.ts:472,1724,1592; Invoice.ts:569,206; Item.ts:190; OwnerWithdrawal.ts:431,209; PurchaseOrder.ts:917,687.

  Acceptance criteria:
  - [ ] All 25 original structural entries are resolved; new helpers do not recreate the same threshold violation.
  - [ ] Numbering fixtures cover existing rows, month boundaries, malformed suffix behavior, duplicate avoidance, and rollback without altering established numbering formats.
  - [ ] Targeted model suites and accounting invariants A-J pass.

  QA scenarios:
  ```
  Scenario: Physical count and purchase-return values remain consistent
    Tool: bash
    Steps: npm test -- --runInBand --runTestsByPath src/__tests__/physicalCountBatchSync.test.ts src/__tests__/purchaseReturn.test.ts src/__tests__/accountingInvariants.test.ts
    Expected: stock batches, subledgers, and balanced GL assertions pass on fresh fixtures.
    Evidence: <attemptDir>/task-3-models.log
  Scenario: Reversal failures and duplicate operations preserve stock
    Tool: bash
    Steps: npm test -- --runInBand --runTestsByPath src/__tests__/stockTransferVoid.test.ts src/__tests__/reversalSymmetry.test.ts src/__tests__/purchaseVoid.test.ts
    Expected: failed operations roll back, repeated voids retain existing behavior, and no posting is duplicated.
    Evidence: <attemptDir>/task-3-models-error.log
  ```

  Commit: NO | Message: `refactor(models): extract transactional model operations` | Files: [`server/src/models/**`, `server/src/utils/sequence.ts`, document-number/date helper files, model-owned targeted test files]

- [ ] 4. Resolve service complexity and shared cash-account lookup

  What to do: service worker owns `server/src/services/**` after root's accountingService handoff. Resolve all 13 structural entries below and duplicate group 33 (`dup:827d201f`). Reuse a typed cash/bank lookup where account policy matches; retain validation and posting ownership in the callers. Extract report query validation/selection/join operations, forecast cache parsing, payment checks, cash flow construction, invoice creation/return stages, and journal entry validation with unchanged ordering. Examine `unappliedCashService.ts` as a high CRAP candidate after coverage repair rather than guessing it is a structural violation.
  Must NOT do: change report expression security, duplicate accounting writes, alter invoice-return sequencing, or bypass supplier/payment validations.
  Closes: GAP-3, GAP-4, GAP-6.

  Parallelization: Can parallel: YES | Wave 2 | Blocks: [6] | Blocked by: [1]

  References:
  - Pattern/API: `server/src/services/accountingService.ts:775,919,956` - cash/bank lookup clone instances.
  - Test: `server/src/__tests__/invoiceCreationService.test.ts`, `server/src/__tests__/invoiceReturnAcceptance.test.ts`, `server/src/__tests__/supplierPaymentAllocation.test.ts`, `server/src/__tests__/reportExpressionSecurity.test.ts`, `server/src/__tests__/forecastConfigInjection.test.ts`.
  - Full structural references under `server/src/services/`: invoiceReturnService.ts:301; cashService.ts:529,102; InvoiceCreationService.ts:155,111; accountingService.ts:243; paymentValidation.ts:110; reportQueryEngine.ts:204,347,166,464; forecastService.ts:655; SupplierPaymentService.ts:24.

  Acceptance criteria:
  - [ ] All 13 structural entries resolved with intact public service contracts.
  - [ ] Shared account lookup tests cover cash, bank, missing account, and existing validation messages.
  - [ ] Financial service, expression-security, and forecast-security tests pass.

  QA scenarios:
  ```
  Scenario: Invoice and supplier-payment lifecycle
    Tool: bash
    Steps: npm test -- --runInBand --runTestsByPath src/__tests__/invoiceCreationService.test.ts src/__tests__/invoiceReturnAcceptance.test.ts src/__tests__/supplierPaymentAllocation.test.ts src/__tests__/accountingInvariants.test.ts
    Expected: successful creation, allocation, return and ledger assertions pass.
    Evidence: <attemptDir>/task-4-services.log
  Scenario: Unsafe reports, forecast configuration, and return edges
    Tool: bash
    Steps: npm test -- --runInBand --runTestsByPath src/__tests__/reportExpressionSecurity.test.ts src/__tests__/forecastConfigInjection.test.ts src/__tests__/invoiceReturnEdgeCases.test.ts
    Expected: malicious/invalid inputs retain expected rejection; no SQL or filesystem injection is enabled.
    Evidence: <attemptDir>/task-4-services-error.log
  ```

  Commit: NO | Message: `refactor(services): extract financial and report operations` | Files: [`server/src/services/**`, service-owned targeted test files]

- [ ] 5. Resolve remaining scripts, bootstrap, route, and fixture findings

  What to do: root owns all remaining source locations, including scripts, migrations, config, routes, middleware and utils other than Task 3's files. Resolve the 14 structural findings below. Extract repeated script startup/environment/database setup in group 13 (`dup:66fc37bd`); inspect group 28 (`dup:2383cf9f`) and retain distinct execution/output or data-repair policy portions with reasons. Extract shared rate-limiter configuration in group 32 (`dup:58949ae7`) while preserving route-specific keys, limits, windows, and messages. Refactor test fixture complexity without weakening assertions; keep historical migration SQL behavior unchanged.
  Must NOT do: execute repair scripts against a live database, alter migration order, rewrite old records, or change rate limits while consolidating configuration.
  Closes: GAP-3, GAP-4, GAP-6.

  Parallelization: Can parallel: YES | Wave 2 | Blocks: [6] | Blocked by: [1]

  References:
  - Pattern/API: `server/src/middleware/rateLimiter.ts:13,35,102`; `server/scripts/backfill-ledger-dates.js:23,33`; `server/scripts/dedupe-po.js:26,36`; `server/scripts/recompute-item-amounts.js:51,61`.
  - Test: `server/src/__tests__/accountingExtensionMigrations.test.ts`, `server/src/__tests__/purchaseVoid.test.ts`, `server/src/__tests__/accountingInvariants.test.ts`.
  - Full structural references: `server/src/__tests__/accountingInvariants.test.ts:153`; `server/scripts/verify-reversal-rules.ts:68`; `server/src/config/database.ts:1118,1238`; `server/src/__tests__/purchaseVoid.test.ts:33`; `server/src/utils/purchaseReturnBackfill.ts:96`; `server/src/migrations/backfillGlUnification.ts:27`; `scripts/openspec-archive-guard.js:109,58`; `server/src/migrations/backfillGlPreposting.ts:158`; `server/scripts/backup-db.js:43`; `server/scripts/repair-stock.ts:73`; `server/src/scripts/reconcile-stock-cash.ts:134`; `server/src/routes/stockBatches.ts:50`.

  Acceptance criteria:
  - [ ] All 14 original structural findings resolved and each assigned duplicate group has a supported disposition.
  - [ ] `npm run verify:reversal-rules` passes; fresh-database migration and fixture tests pass.
  - [ ] Add necessary temporary-database/script and mounted-route tests for changed paths where existing tests do not observe behavior, including invalid arguments and rate-limit response equivalence.

  QA scenarios:
  ```
  Scenario: Migrations and reversal fixture behavior
    Tool: bash
    Steps: npm test -- --runInBand --runTestsByPath src/__tests__/accountingExtensionMigrations.test.ts src/__tests__/purchaseVoid.test.ts src/__tests__/accountingInvariants.test.ts
    Expected: fresh bootstrap, accounting invariants, and purchase void assertions pass.
    Evidence: <attemptDir>/task-5-infrastructure.log
  Scenario: Reversal rules and error invariants
    Tool: bash
    Steps: npm run verify:reversal-rules
    Expected: zero rule violations and zero exit code; script-specific invalid-input tests preserve their current error contract.
    Evidence: <attemptDir>/task-5-infrastructure-error.log
  ```

  Commit: NO | Message: `refactor(server): simplify maintenance and bootstrap operations` | Files: [remaining scripts/config/routes/middleware/migrations/utils, root-owned targeted test files]

- [ ] 6. Recompute mapped coverage and close genuine remaining health gaps

  What to do: root runs full mapped coverage after all source lanes settle, then regenerates Fallow. Reconcile each of the 163 original CRAP-only entries to its current symbol and measured coverage. Confirm disappeared findings reflect corrected mapping or actual coverage, not missing input files. Assign remaining reachable coverage gaps to the original owner; use targeted scenario tests, and refactor any still excessive complexity through coherent operations. Register all new findings caused by extraction and resolve them before final reporting.
  Must NOT do: assign 100% to missing files, use stale coverage from a targeted run as the final input, or claim estimated coverage is measured coverage.
  Closes: GAP-1, GAP-3, GAP-5, GAP-6.

  Parallelization: Can parallel: NO | Wave 3 | Blocks: [7] | Blocked by: [2,3,4,5]

  References:
  - Pattern: `.fallowrc.json:40`; `server/jest.config.js:7`; `audit/fallow-tools/fallow-before-20261021.json` at `health.findings`.
  - API/Type: original findings identify exact symbols, paths and source lines; use source mapping when functions have moved.
  - Test: `server/src/__tests__/accountingInvariants.test.ts`; targeted suites chosen by actual uncovered behavior and existing test ownership.

  Acceptance criteria:
  - [ ] `npm test -- --runInBand --coverage` passes and refreshes `server/coverage/coverage-final.json` after the final relevant edit.
  - [ ] From repo root, `npx --yes fallow@3.34.1 --format json` produces a complete captured report; confirm the flag from `npx --yes fallow@3.34.1 --help` if the installed CLI differs.
  - [ ] Every original health entry has current measured/source-supported status; every newly introduced actionable finding is fixed.

  QA scenarios:
  ```
  Scenario: Fresh full server coverage
    Tool: bash
    Steps: npm test -- --runInBand --coverage
    Expected: all server tests pass; mapped coverage reflects the final source and contains exercised critical paths.
    Evidence: <attemptDir>/task-6-full-coverage.log
  Scenario: Detect remaining health findings without baseline masking
    Tool: bash
    Steps: From repo root run npx --yes fallow@3.34.1 --format json; compare every original health row and all new rows by current path/symbol.
    Expected: no unresolved structural finding; each original CRAP-only entry has a measured result or a concrete legitimate coverage-boundary reason.
    Evidence: <attemptDir>/task-6-fallow.json
  ```

  Commit: NO | Message: `test(server): cover remaining financial and validation paths` | Files: [targeted tests and any necessary source refactors, remediation ledger]

- [ ] 7. Finish the complete disposition ledger and integrated checks

  What to do: root merges worker evidence into the dated ledger, checks all original IDs plus newly introduced findings, and runs static/final integration checks. Explain retained duplicate differences and live-symbol evidence; report exact before/after counts with mapping changes distinguished from code changes. Run full server tests with coverage again only if Task 6's successful full run precedes subsequent source/test edits. Record that Flutter was intentionally not rerun when its code and shared contracts are unchanged.
  Must NOT do: present a new-only gate as proof of old-finding resolution, delete preserved audit files, or claim a full suite ran when only selected suites ran.
  Closes: GAP-1, GAP-6.

  Parallelization: Can parallel: NO | Wave 3 | Blocks: [F1,F2,F3,F4] | Blocked by: [6]

  References:
  - Pattern: `scripts/check.sh:45` - typecheck/lint and pinned Fallow gate; `scripts/check.sh:53` - server suite.
  - API/Type: `audit/DECISIONS.md:321` - existing baseline/gate policy; `CODING_STANDARDS.md:48` - accounting integrity.
  - Test: Task 6's full-suite coverage evidence and all lane-specific scenario evidence.

  Acceptance criteria:
  - [ ] `npm run typecheck`, `npm run lint`, and `npm run verify:reversal-rules` pass.
  - [ ] From repo root, `npx --yes fallow@3.34.1 audit --base HEAD` is checked alongside the raw final report; any remaining gate failure is resolved or specifically explained without changing thresholds/baselines.
  - [ ] Ledger accounts for exactly 340 original entries and every new finding, with no vague retained/deferred category.
  - [ ] Final full server suite and mapped coverage are current; user files are preserved; no unrequested commits are created.

  QA scenarios:
  ```
  Scenario: Integrated static and reversal gates
    Tool: bash
    Steps: Execute npm run typecheck; npm run lint; npm run verify:reversal-rules separately from server/ and capture each exit status.
    Expected: all exit zero.
    Evidence: <attemptDir>/task-7-static.log
  Scenario: Full finding reconciliation detects omissions
    Tool: bash
    Steps: Compare original check findings, dupes.clone_groups, and health.findings against ledger IDs; require cardinalities 63,39,238 and inspect every retained reason. Run npx --yes fallow@3.34.1 audit --base HEAD from repo root.
    Expected: zero missing original IDs, zero unreviewed new findings, and no suppression/baseline changes used to mask issues.
    Evidence: <attemptDir>/task-7-reconciliation.json
  ```

  Commit: NO | Message: `docs(audit): record complete Fallow remediation evidence` | Files: [`audit/fallow-remediation-2026-10-21.md`]

## Final verification wave (MANDATORY - after all implementation tasks)
> Runs in parallel when reviewer capacity permits; all four checks must approve. Surface the actual results to the caller. Existing user authorization covers these checks; do not add a permission round trip.
- [ ] F1. Plan compliance audit - every original finding has a disposition; every task and acceptance criterion is met.
- [ ] F2. Code quality review - diagnostics clean, useful operations extracted, no new dead code, no SQL/policy changes hidden by generic helpers.
- [ ] F3. Real manual QA - mounted API and fresh-database scenarios executed with evidence; script behavior observed on isolated fixtures where changed.
- [ ] F4. Ideal-state fidelity - verify IS-1 through IS-6 individually; a shortfall becomes a correction task, not an unexplained caveat.

## Commit strategy
- No commits requested; keep changes unstaged for review. Commit suggestions above describe logical boundaries only.
- If the user later requests commits, make one logical change per commit, each independently buildable and tested. Use Conventional Commits and include `Plan: .omo/plans/fallow-remediation-2026-10-21.md` in the final commit footer.

## Success criteria
| IS | Delivering task(s) | Proving QA scenario | Evidence |
|----|--------------------|---------------------|----------|
| IS-1 | 1,6,7 | Full finding reconciliation detects omissions | `<attemptDir>/task-7-reconciliation.json` |
| IS-2 | 1 | Correct source mapping and intact accounting period lifecycle | `<attemptDir>/task-1-source-mapping.log` plus ledger reachability/vocabulary rows |
| IS-3 | 2,3,4,5,6 | Detect remaining health findings without baseline masking | `<attemptDir>/task-6-fallow.json` |
| IS-4 | 2,3,4,5,7 | Full finding reconciliation detects omissions | `<attemptDir>/task-7-reconciliation.json` plus per-group ledger evidence |
| IS-5 | 1,6 | Fresh full server coverage | `<attemptDir>/task-6-full-coverage.log` and final coverage JSON |
| IS-6 | 2,3,4,5,6,7 | Fresh full server coverage; Integrated static and reversal gates | `<attemptDir>/task-6-full-coverage.log`, `<attemptDir>/task-7-static.log` |
- Every IS row has a delivering task and proving scenario; all required scenarios pass with captured evidence, F1-F4 approve, and no requested finding is silently omitted.
