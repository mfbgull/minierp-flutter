# Accounting remediation — independent code review

## Latest pass: remediation working tree, 2026-10-26

**codeQualityStatus: BLOCK; recommendation: REQUEST_CHANGES.** Reviewed the production/test diff and untracked migrations 117–120, `storeCreditOwnership.ts`, `physicalCountLayers.ts`, `salaryAdvanceRecognition.ts`, four audit test suites, and Flutter report regression tests. The earlier preliminary findings below are historical and superseded by this pass where stated.

### CRITICAL

No unresolved critical defect established in the newly implemented F-002/F-073 paths. The source now preserves explicit zero tender and adds durable credit-source ownership plus a conservative historical-consumption guard. `accounting-audit/remediation/critical-green.log` records 2 suites / 25 tests passed. This reviewer inspected that artifact and the tests; it is executor-run evidence, not an independently rerun test suite.

### HIGH

1. **Positive physical-count adjustments still omit location stock.** `server/src/models/PhysicalCount.ts:360` creates the surplus batch without calling `syncBatchStockByLocationForNewBatch`. With `feature_batch_locations`, the new extension sync at `:401` aggregates bins that omit the surplus. The resulting batch master/stock quantity and location quantity disagree. Add a mounted +surplus count case with location tracking and assert all representations.
2. **Surplus correction leaves the batch master unchanged with locations enabled.** `server/src/models/PhysicalCount.ts:546` selects the adjustment batch, but the locations branch at `:556` subtracts only from the DEFAULT bin; `stock_batches.quantity_remaining` is reduced only in the non-location branch. The batch-location triggers maintain `quantity_available`, not the batch master. A +3 surplus corrected to zero leaves three extra units in the master (and moved-bin scenarios need a safe guard or exact restoration). The new shortage-only location test cannot detect this.
3. **F-020 larger carryover has no complete disposition.** `server/src/models/salaryAdvanceRecognition.ts:6` selects only advances whose `pay_period` equals the new payment month and caps recognition at one salary. For salary 1000 and August tender 2500, a September advance of 1500 is created. A zero-cash September application is rejected by `employeeController.ts:427`; even a positive payment recognizes at most 1000 and leaves 500 tied to September, excluded from October recognition. The original finding expressly calls for larger advances spanning months. This is a source-derived missed path, not an executed reproduction; prove/fix it or record an explicit unsupported/unverified disposition and do not claim complete salary correctness.

### MEDIUM

1. **Count detail valuation still uses standard cost rather than posted cost.** `PhysicalCount.ts:142` snapshots `items.standard_cost`; `recordCount` and correction at approximately `:691` set `variance_value = variance * unit_cost`, while shortage journals/movements use weighted consumed layers. A shortage crossing 5@10 and 3@20 posts 110 but can display a different count variance value. The reverse correction movement also writes the snapshot cost. Tests need document/report and movement valuation assertions in addition to batch quantity and net GL checks.
2. **Generated Flutter evidence reports obsolete calculations as actual results.** `test/features/accounting_report_regressions_test.dart` writes `actual_remaining_from_client_expression: 1000 - 200 - 200` after the production fix, and its displayed-component sums omit newly displayed other-assets/tax/other-liability values. These fields must be removed, relabeled as historical, or derived from current output. The extra hand-written CSV parser and its tests are unnecessary when the same test uses the existing CSV decoder.
3. **Completion evidence is pending.** At review time STATUS.md still marked every finding UNVERIFIED, and available logs included payroll/stock and controls failures; no final full-suite/static-check report was present. The header test's name promises protection of active child lines but only voids a whole two-line entry. The new widget tests pump displays but do not drive taps. Do not present these as complete interaction or mixed-header verification.

### LOW

None recorded.

### Skill perspectives and scope

The `remove-ai-slops` and `programming` perspectives were applied. The core new regressions assert actual monetary/stock behavior rather than deletion-only or mirrored implementation assertions. The redundant CSV parser and misleading evidence calculations violate the simplicity/evidence perspective. No type escape was introduced in the reviewed new production helpers. Migrations are registered and append new provenance structures without historical financial backfill. No live or disposable database was opened or mutated by this reviewer; findings above distinguish source deductions from executor-run evidence.

The graph coverage check reported metadata changed or untracked for the modified/new files, so this pass used direct source as required. Review remains blocked pending the high findings and final evidence. No existing prompt file was altered.

---

## Historical preliminary pass (before remediation)

Date: 2026-10-26. Reviewer scope: current F-002 and F-073 implementation and existing regression coverage. This is a preliminary source review, not approval of an implementation diff. No application, migrations, or database-writing scenarios were run by this reviewer.

## Verdict

- codeQualityStatus: BLOCK
- recommendation: REQUEST_CHANGES
- Remediation diff: not supplied yet. Final review remains pending.

## CRITICAL

1. **F-002 remains present in source.** `server/src/services/invoiceReturnService.ts:1327` reverses a credit settlement by subtracting its full amount from the aggregate pool with `MAX(0, ...)`, then reversing the credit ledger entry. There is no source-consumption guard. Both settlement void (`:721`) and whole-return void (`:624`) call this primitive. `server/src/services/InvoiceCreationService.ts:374` consumes pool credit without recording which credit settlement funded it. The historical reproduction is therefore consistent with current code: consumed entitlement can be released and reissued while downstream invoices remain settled. A check of aggregate pool sufficiency alone would still miss consumption followed by replenishment from another return. Fix and prove source-level conservation at the common boundary.

2. **F-073 remains present in source.** `server/src/controllers/posController.ts:162` uses `parseFloat(String(body.cash_received)) || total`. Explicit zero becomes full tender before the insufficient-cash guard. The replay response duplicates the fallback at `:91`. Correctness tests must cover actual tender and committed/rolled-back effects, not only agreement between a fabricated payment and its balanced journal.

## HIGH

None additional established by this bounded source review.

## MEDIUM

1. **Relevant existing regressions do not cover the critical sequences.** `server/src/__tests__/customerStoreCredit.test.ts` exercises pool creation, consumption, and overapplication but does not void a consumed source. `server/src/__tests__/posPayments.test.ts:131` covers insufficient positive tender (40 against 100), which does not exercise the falsy-zero branch. Preserve these valid tests and add the missing behavioral cases. Include partial/full consumption, multiple target invoices, source replenishment, both void paths and repeats; include zero/negative/insufficient/exact/excess tender and replay.

## LOW

None.

## Review method and limits

Graph discovery and exact snippet reads were used first. Coverage checks for `server/src/controllers/posController.ts` and `server/src/services/invoiceReturnService.ts` returned `no_recorded_issue` with matching metadata. Direct source inspection confirmed the cited branches. Graph coverage is best-effort and is not proof of complete path enumeration.

The `remove-ai-slops` and `programming` skill perspectives were consulted. Existing tests examined here assert meaningful externally observable behavior; the identified issue is missing adversarial lifecycle coverage, not deletion-only or tautological assertions. No new production/test diff was available to judge for unnecessary complexity, untyped escapes, or overfitting.

`omo-agent-toolkit ulw-loop status --json` exited 1 with `ULW_LOOP_PLAN_MISSING`, so this report uses the prescribed fallback evidence path. No code or financial data was changed; this report is the only reviewer-created artifact.

Final acceptance requires inspecting the completed diff and executed evidence, including per-entry balancing and signed economic balances. Historical audit outputs alone do not establish current execution results.
