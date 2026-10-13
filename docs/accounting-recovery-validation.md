# Accounting recovery from OpenCode

Session: `ses_eeb8d64a7ffeWr61c3Aqcla387`, inspected through Herdr pane `w4:p3`.
Starting commit: `6c6273dd`.

## Scope and constraints

Restore lost ACCT-013 and PAY-001 through PAY-004 coverage, fix the demonstrated defects, validate, then resume DB-002 write-time journal protection separately. Do not open the live database for writing or include unrelated workspace changes.

The implementation follows the finalized D1 through D4 decisions in `audit/DECISIONS.md`: sufficient funds for payouts; chronological cash-inflow reversal checks; a linked salary/advance split with no double posting; and Dr Cash / Cr Employee Loan Receivable for salary deductions.

## Recovery findings

- OpenCode's last report incorrectly described all three audit test rounds as absent from the active suite. Round 1 already exists unchanged in `server/src/__tests__/auditRegression.test.ts`. Round 2 exists in `auditRegression2.test.ts`, with stronger supplier-required validation and a supplier-specific AP delta assertion. Duplicate recovery copies were removed.
- Round 3 was missing from the active suite. Restoring its eight cases reproduced eight failures: three cash-inflow reversal cases, two insufficient-funds payout cases, duplicate salary-overpayment posting, orphaned advance on salary void, and missing loan-receivable GL movement for salary deductions.
- The original PAY-001 expectation that all 1,500 is wage expense predates decision D3. The recovered case retains the 1,500 cash assertion and additionally requires 1,000 wage expense, 500 advance receivable, and linked rows totaling exactly 1,500.
- Four additional chronological reversal cases fail against the starting implementation. They cover deleting an inflow despite later replenishment and edits to its amount, date, or account. Two positive controls pass: reducing to exactly the spent amount and voiding when earlier funding covers the spending.
- The supplier-less cash-purchase assertions removed in `3cab5c7d` concern a superseded workflow: current policy rejects purchases without an identified supplier. Restoring those obsolete cash-posting expectations would contradict the current purchase contract.

## Work sequence

1. Validate the starting commit with the full existing suite and TypeScript.
2. Restore round 3 and strengthen chronology, split, rollback, and reversal coverage.
3. Implement cash-reversal and payroll/loan fixes with required migrations.
4. Run targeted API scenarios, the full suite, type checks, and lint; update the audit ledger and commit accounting recovery separately.
5. Implement and validate DB-002 journal sealing in a separate commit.

## Accounting recovery validation

- Starting-commit `npm run typecheck`: passed.
- Recovered historical tests before changes: 23 passed, eight failed across three files; the first two recovery files duplicated existing coverage and were removed.
- Chronological reversal cases before changes: four failed, two passed.
- Full starting suite: 125 suites and 1,107 tests passed. Used `TMPDIR=/dev/shm` and two workers after disk-backed fixture creation proved slow; only newly added recovery tests were excluded from this baseline run.
- `npm run lint`: unavailable because `server/package.json` has no lint script. The existing ESLint configuration is available for direct invocation.
- Accounting recovery: `env TMPDIR=/dev/shm npm test -- --maxWorkers=2 --silent` passed all 128 suites and 1,129 tests, including 22 added cases. The existing worker-exit warning remains; unrelated teardown changes were explicitly excluded.
- `npm run typecheck` passed after implementation.
- Direct ESLint on all changed TypeScript files with `--max-warnings=0` passed, and `git diff --check` passed.
- API tests exercise authenticated capital corrections, salary/loan payouts, linked advance voids, salary deductions and their reversals, insufficient-funds rollback, and overpayment idempotency. The HTTP response shape remains compatible; Flutter UI code is unchanged and has not been manually retested.

The new migration adds the salary parent link and account 1310 (Employee Salary Advances). It does not infer links or rewrite old payroll transactions. Existing historical unlinked advances and old deductions require separately reviewed data reconciliation. The live database was never opened for writing.

## Completed continuation

Accounting recovery was committed separately as `f9a72d63` (`fix(server): restore cash and payroll audit coverage`).

DB-002 now enforces each journal's balance at transaction commit through a
trigger-maintained integer balance and a deferred foreign key to zero. The
legacy stock writer owns its transaction, and ordinary fixtures create complete
postings atomically. Boot-detection tests retain their deliberate corruption
scenarios with enforcement restored before each assertion. See
[DB-002 design and validation](database-journal-seal.md).

Final combined validation passed **129 suites and 1,150 tests**, TypeScript,
strict lint on changed files, and the whitespace check. The existing Jest
worker-exit warning remains. No live database migration or manual Flutter UI
retest was performed. Unrelated audit-directory changes were left untouched.
