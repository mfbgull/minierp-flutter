# Audit findings status

## Phase 0 baseline

- Branch: `audit-fixes`, created from `46ea0c93` (current user fixes preserved).
- Audited reference: `87f1265b`; no rollback to the audited commit.
- Report: `audit/MiniERP — Accounting, Code and Architecture Audit.md`.
- Existing regression files are preserved, including the modified `auditRegression2.test.ts` and `auditRegression3Recovered.test.ts`.
- No finding has been triaged yet. TODO means awaiting Phase 0b; a passing baseline test alone does not establish that the root cause is fixed.
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

## Findings

| ID | Title | Phase | Test name / planned proof | Status | Fix commit SHA |
|---|---|---|---|---|---|
| ACCT-001 | Balance sheet after store-credit offset | 1 | auditRegression ACCT-001 | TODO | — |
| ACCT-002 | P&L covers all accounts (after PROD-001) | 1 | auditRegression ACCT-002 | TODO | — |
| ACCT-003 | Partial-return restock rounding | 1 | auditRegression ACCT-003 | TODO | — |
| ACCT-004 | Closed-period bypass on create | 1 | auditRegression ACCT-004 | TODO | — |
| ACCT-005 | Cash purchase funds guard | 2a | auditRegression2 ACCT-005 | TODO | — |
| ACCT-006 | Date validation | 3a | new (auditRegression9) | TODO | — |
| ACCT-007 | Tax / discount / price bounds | 3a | new | TODO | — |
| ACCT-008 | Duplicate submit without key | 3e | new | TODO | — |
| ACCT-009 | Scope gaps (accruals, bills, input tax, advances) | 3i | decision | TODO | — |
| ACCT-010 | AR aging as-of + null due date | 3b | new | TODO | — |
| ACCT-011 | AP aging as-of | 3b | new | TODO | — |
| ACCT-012 | Supplier balance after backdated purchase | 1 | auditRegression2 ACCT-012 | TODO | — |
| ACCT-013 | Cash inflow reversal overdraws cash | 2b | auditRegression3 ACCT-013 | TODO | — |
| PO-001 | Non-numeric goods receipt quantity | 1 | auditRegression2 PO-001 | TODO | — |
| PRET-001 | Purchase-return rounding | 1 | auditRegression2 PRET-001 | TODO | — |
| PRET-002 | Cash purchase return / refund_expected | 3f | new | TODO | — |
| PROD-001 | Raw-material relief in GL | 1 | auditRegression4 PROD-001* | TODO | — |
| PROD-002 | Production unit-cost rounding | 1 | auditRegression4 PROD-002 | TODO | — |
| PROD-004 | Negative overhead | 1 | auditRegression4 PROD-004 | TODO | — |
| PROD-005 | Production delete corruption | 1 | auditRegression4 PROD-005 | TODO | — |
| PROD-006 | Production closed period | 1 | auditRegression4 PROD-006 | TODO | — |
| PROD-007 | Self-production | 1 | auditRegression4 PROD-007 | TODO | — |
| PAY-001 | Salary overpayment double-posted | 2c | auditRegression3 PAY-001 (user-approved D3 correction; awaiting triage) | TODO | — |
| PAY-002 | Void leaves advance | 2c | auditRegression3 PAY-002 | TODO | — |
| PAY-003 | Salary/loan funds guard | 2a | auditRegression3 PAY-003 | TODO | — |
| PAY-004 | Salary-deduction repayment GL | 2d | auditRegression3 PAY-004 | TODO | — |
| WO-001 | Write-off precision | 1 | auditRegression5 WO-001 | TODO | — |
| WO-002 | Damaged stock write-off / reversal | 3f | new | TODO | — |
| WO-003 | Write-off closed period | 1 | auditRegression5 WO-003 | TODO | — |
| AUTHZ-001 | 14 unassignable permissions | 2e | new (drift test) | TODO | — |
| AUTHZ-002 | Admin account takeover | 1 | auditRegression7 AUTHZ-002 | TODO | — |
| AUTHZ-003 | Role assignment escalation | 1 | auditRegression7 AUTHZ-003 | TODO | — |
| AUTHZ-004 | Role self-grant | 1 | auditRegression7 AUTHZ-004 | TODO | — |
| REP-001 | Report entity permissions | 1 | auditRegression6 REP-001 | TODO | — |
| REP-002 | Report whitelist bypass | 1 | auditRegression6 REP-002 | TODO | — |
| REP-003 | Registry fields without columns | 1 | auditRegression6 REP-003 | TODO | — |
| REP-004 | HAVING bound value / grouped count | 1 | auditRegression6 REP-004 | TODO | — |
| REP-005 | Aggregates, row cap, LIKE escape | 3g | new | TODO | — |
| FILE-001 | Arbitrary file deletion | 1 | auditRegression8 FILE-001 | TODO | — |
| FILE-002 | Upload served as active content | 1 | auditRegression8 FILE-002 | TODO | — |
| BK-001 | Apostrophe in DB path | 1 | auditRegression8 BK-001 | TODO | — |
| BK-002 | Download not audited | 1 | auditRegression8 BK-002 | TODO | — |
| BK-003 | List/download/delete mismatch | 1 | auditRegression8 BK-003 | TODO | — |
| BK-004 | Same-second backups | 1 | auditRegression8 BK-004 | TODO | — |
| BK-005 | BACKUP_DIR ignored | 1 | auditRegression8 BK-005 | TODO | — |
| BK-006 | README restore procedure | 1 | (docs; reviewer checks) | TODO | — |
| BK-extra | Uploads in backup, retention floor, startup check, perms/encryption | 3h | new | TODO | — |
| CODE-001 | Validation errors as HTTP 500 | 3c | new | TODO | — |
| CODE-002 | Refresh trusts token claims | 3d | new | TODO | — |
| CODE-003 | Password length / default admin | 3d | new | TODO | — |
| CODE-004 | Client idempotency keys | 3e | new (+ Flutter test) | TODO | — |
| CODE-005 | Flutter quality (large files, swallowed errors, lints) | 5 | flutter analyze/test | TODO | — |
| CODE-006 | Flutter quality (large files, swallowed errors, lints) | 5 | flutter analyze/test | TODO | — |
| CODE-007 | Flutter quality (large files, swallowed errors, lints) | 5 | flutter analyze/test | TODO | — |
| DEPLOY-1 | Production backfill / supplier rebuild / stock repair | 4 | seeded-fixture tests + dry-run review | TODO | — |

PROD-001 also requires the production inventory/profit/overhead tests and PROD-001G guard. New tests listed for later phases do not exist yet. Fix commit SHAs will be populated only after triage or a verified fix.
