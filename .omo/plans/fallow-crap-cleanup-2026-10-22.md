# Fallow CRAP cleanup — new symbols and anonymous findings

> Plan date: 2026-10-22
> Parent remediation: `.omo/plans/fallow-remediation-2026-10-21.md`
> Ledger: `audit/fallow-remediation-2026-10-21.md` (section D.1b)
> Scan of record: `.omo/evidence/task-6-fallow.json`
> Delivery: local changes; commit only when requested
> Status: proposed

## Objective

Bring the six new named symbols and two anonymous findings recorded in D.1b to
**CRAP < 30 with measured coverage**, or record a genuine coverage boundary with
evidence. This is a test-and-extraction cleanup, not a behavior change.

Out of scope: the 72 pre-existing functions newly reported by the remapped coverage
(D.2). They remain recorded and are not introduced by the extraction.

## Guardrails

- No suppression comments, threshold changes, replacement baselines, or gate changes.
- No changes to SQL predicates, validation order, transaction boundaries, response
  shapes, account selection, descriptions, or journal amounts.
- Fresh fixture/temp databases only; never run against the live database.
- Characterization tests first. For every extraction, tests must pass before and after.
- Accounting-touching changes must pass invariants A–J and `npm run verify:reversal-rules`.
- Prepared statements only; keep dynamic update-field lists parameterized.
- Server-only changes; no Flutter edits.
- Do not change test timeouts to mask load flakiness.

## Findings

| # | Finding | Location | Current | Root cause | Target action |
|---|---|---|---|---|---|
| 1 | `updateBorrowerFields` | `server/src/controllers/ownerPersonalLoansController.ts:695` | CRAP 90, cyc 9, 0% | Four optional-field branches uncovered | Test-only through mounted update route; full coverage → CRAP 9 |
| 2 | `validateReportSort` | `server/src/controllers/customReportsController.ts:97` | CRAP 35, cyc 8, 25% | Sort branches not exercised | Test-only through custom-report validation; full coverage → CRAP 8 |
| 3 | `parseGuardOption` | `scripts/openspec-archive-guard.js:58` | CRAP 30, cyc 5, est. 0% | Root-level CLI parser outside Jest roots | Test the exported `parseArgv`; cover all flag/error branches |
| 4 | `verifySnapshot` | `server/scripts/backup-db.js:82` | CRAP 30, cyc 5, est. 0% | Top-level script has no testable helper | Extract `verifySnapshotAt(snapshotPath)`; keep CLI wrapper |
| 5 | `postReconciledStock` | `server/scripts/repair-stock.ts:90` | CRAP 30, cyc 5, est. 0% | Journal-posting helper untested; script imports the live DB | Extract shared reconciliation-journal helper; call it directly |
| 6 | `postCoverageAdjustment` | `server/src/config/database.ts:1262` | CRAP 30, cyc 5, 0% | Nested helper inside startup reconciliation | Use the shared reconciliation-journal helper; add fresh-DB integration test |
| 7 | `<arrow>` | `server/src/models/Employee.ts:405` | CRAP 72, cyc 8, 0% | `rows.map` callback in `getSalaryHistory` untested | Extract `toSalaryHistoryRow(r, salary)`; cover all status branches |
| 8 | `<arrow>` | `server/src/models/Reports.ts:1241` | CRAP 56, cyc 7, 0% | Transaction callback in `saveCashReconciliation` untested | Extract `upsertCashReconciliationEntries(...)`; cover upsert/rollback |

## Per-finding actions

### 1. `updateBorrowerFields`

Test-only; do not change the dynamic SQL builder. Extend
`server/src/__tests__/ownerPersonalLoans.test.ts` using the mounted route
`PUT /api/owner-equity/borrowers/:id` (`server/src/routes/ownerEquity.ts:47`).

Cases:
- Each of `name`, `phone`, `linked_type`, `linked_id` alone.
- All fields together; no fields (no-op, row unchanged).
- `name` whitespace trimming.
- `phone` empty string → null; `linked_type` empty → null; `linked_id` 0 → null
  (current `|| null` behavior).
- Duplicate name/link → 400; unknown borrower → 404.
- Read back every update from the database; assert no values are interpolated into SQL.

### 2. `validateReportSort`

Test-only through the custom-report create/update path; prefer not to export internals.
Add `server/src/__tests__/customReportValidation.test.ts` or extend
`server/src/__tests__/reportExpressionSecurity.test.ts`.

Cases:
- `sort` absent or non-array → no errors.
- Missing, empty, or non-string field → `sort[i].field` error.
- Unknown field → entity-qualified error; accepted computed-column field.
- Direction `asc`, `ASC`, `desc` accepted; invalid direction rejected.
- Multiple entries; errors accumulate in input order.
- Injection-shaped field fails the allowlist with no query execution.

### 3. `parseGuardOption`

The script already exports `parseArgv`; test through it so `parseGuardOption` is
executed. Add `server/src/__tests__/openspecArchiveGuard.test.ts` requiring
`../../../scripts/openspec-archive-guard.js`.

Cases:
- `--force-incomplete`.
- `--reason value` and `--reason=value`.
- `--reason` with no value → `UsageError`.
- Unknown flag → `UsageError`.
- `--` passthrough; missing change or flag-first invocation → `UsageError`.

Verify `server/coverage/coverage-final.json` includes the root script. If Jest does not
instrument it, export `parseGuardOption` and add a test-only `collectCoverageFrom` entry,
or move the pure parser to a shared JS module and require it from both the CLI and test.

### 4. `verifySnapshot`

Extract a testable helper, for example `server/scripts/lib/backup-verify.js`:

- `verifySnapshotAt(snapshotPath)` opens the file read-only, runs
  `PRAGMA integrity_check`, and returns/throws a typed result.
- Keep the existing CLI wrapper: on failure delete the snapshot, print the same message,
  and exit 1.
- Guard script execution with `if (require.main === module) run();`.

Add `server/src/__tests__/backupVerifySnapshot.test.ts` using temp directories:
- Valid database → ok.
- Corrupt/garbage file → failure and snapshot removed.
- Missing file → failure with a clear message.
- One child-process smoke test if the CLI wrapper is modified.

If coverage remains estimated, move the helper to a plain JS module under `server/src`
so Jest instruments it; do not suppress the finding.

### 5 and 6. Shared reconciliation journal

Create `server/src/utils/inventoryReconciliation.ts` with a single helper, for example:

```ts
postInventoryReconciliationEntry(db, {
  description: string,
  amount: number,
  inventoryAccountCode?: string,
  adjustmentAccountCodes?: readonly string[],
}): void
```

Preserve exactly:
- No-op when `amount <= 0.005`.
- No-op when the `journal_entries` table is absent.
- Header insert: `reference_type='RECON'`, `reference_id=0`, today’s date, voided 0.
- Debit account `1200`; credit account `4999` or `4000` with
  `ORDER BY code DESC LIMIT 1`.
- Two journal lines only when both accounts exist; header-only behavior otherwise.
- Caller owns the transaction; the helper must not start one.

Replace the local `postReconciledStock` and `postCoverageAdjustment` wrappers with direct
calls to this helper, so no new wrapper symbol is introduced. Add:
- `server/src/__tests__/inventoryReconciliation.test.ts` using
  `createFixtureDb({ reference: true })`: no-op below threshold, missing table, missing
  accounts, successful balanced entry, and line-insert failure rollback.
- `server/src/__tests__/stockCoverageReconciliation.test.ts`: seed a fresh-DB mismatch,
  run `runStockCoverageReconciliation` (export it narrowly for the test or invoke it via
  initialization), assert batch + journal rows and repeat-run idempotence.
- One script-level fixture test for `repair-stock` if its wrapper logic changes; do not
  import the script itself, because it opens the live DB at module load.

### 7. Salary history arrow

Extract the map callback in `Employee.getSalaryHistory` to a named module-level function:

```ts
function toSalaryHistoryRow(r: SalaryHistoryDbRow, salary: number): SalaryHistoryRow
```

Test through `GET /api/employees/:id/salary/history` or
`EmployeeModel.getSalaryHistory`; extend `salaryAtomicDeduction.test.ts` or add
`server/src/__tests__/salaryHistory.test.ts`.

Cases: `paid`, `advance` (all auto-advances), `partial`, zero/no payments; valid and
invalid `ADV-YYYY-MM` references; `remaining` clamped at 0; multiple pay periods ordered
descending.

### 8. Cash reconciliation arrow

Extract the transaction callback in `Reports.saveCashReconciliation`:

```ts
function upsertCashReconciliationEntries(
  db, date, entries, expected, userId
): void
```

Preserve the existing prepared upsert, unknown-key rejection, account-name lookup,
rounding to two decimals, notes trimming, and transaction scope. Test through
`POST /api/reports/cash-reconciliation` or `ReportsModel.saveCashReconciliation`; extend
`cashTruth.test.ts` or add `server/src/__tests__/cashReconciliationWrite.test.ts`.

Cases: valid insert; re-save upsert; unknown account key throws and rolls back all
entries; null counted balance → null variance; 2-decimal rounding; empty notes → null;
expected balances and variance asserted directly in the database.

## Execution phases

- [ ] **Phase 1 — pure logic (≈0.5d):** #2 `validateReportSort`, #3 `parseGuardOption`.
- [ ] **Phase 2 — controller/model coverage (≈1d):** #1 borrower update, #7 salary history, #8 cash reconciliation.
- [ ] **Phase 3 — scripts/config and accounting (≈1.5d):** #4 `verifySnapshot`, #5/#6 shared reconciliation journal.
- [ ] **Phase 4 — verification and ledger closure (≈0.5d).**

Dependencies: Phase 2 and Phase 3 are independent after Phase 1; the shared journal
helper in Phase 3 must land before the ledger can mark #5/#6 resolved.

## Verification and acceptance

- [ ] Final scan shows **CRAP < 30** for all eight findings with measured coverage, or a
      documented evidence-backed boundary.
- [ ] `npx --yes fallow@3.34.1 audit --base HEAD` → exit 0; no new findings.
- [ ] `npm run typecheck`, `npm run lint`, `npm run verify:reversal-rules` → exit 0.
- [ ] Targeted suites green; existing accounting/reversal suites green.
- [ ] Full server suite green. Run the final suite with `--runInBand` to avoid the known
      load-induced timeout; do not change test timeouts.
- [ ] `scripts/check.sh --quick` passes; Flutter is untouched.
- [ ] No live database repair; all fixtures are fresh/temp databases.

Ledger closure:
- [ ] Update D.1b statuses from “still reported” to “Resolved — CRAP X (measured)”.
- [ ] Update the post-remediation counts note: 6 named + 2 anonymous resolved; 0 of these
      still reported.
- [ ] Update E with the clean full-suite run and final scan evidence.
- [ ] Copy evidence to `.omo/evidence/task-8-*`.
- [ ] Close `.omo/ulw-execute/fallow-todos.json` and `ledger.jsonl` only after acceptance.

## Risks and rollback

- The shared journal helper touches startup reconciliation. Keep it in a low-level module
  with no `database.ts` import to avoid require cycles; verify exact descriptions, account
  order, and amounts.
- `repair-stock.ts` imports the live DB at module load — never import the script in tests;
  import the extracted helper instead.
- `backup-db.js` and the archive guard are operational CLIs. Preserve stdout and exit codes.
- `scripts/openspec-archive-guard.js` is outside Jest roots; instrumentation is the main
  uncertainty. Spike that first.
- If an extraction changes behavior, revert the extraction and fall back to test-only
  coverage rather than weakening assertions or adding suppressions.
