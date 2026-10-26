# MiniERP — AI-agent fix playbook

How to get an AI coding agent (Claude Code, Cursor, Copilot agent, etc.) to fix **every** finding in the audit, step by step, with proof at each step.

**The idea in one paragraph:** the regression tests are the spec. The agent never decides "is it fixed?" — the tests decide. You give the agent one phase at a time, it must show a green gate before moving on, and a status file (`FINDINGS-STATUS.md`) tracks all 53 finding IDs so nothing silently disappears. Findings that have no test yet are handled test-first.

---

## 0. Prepare (you, 15 minutes)

**Folder layout** (outside the repo so the agent can't accidentally commit it):

```
audit/
├── MiniERP-Audit-Report.md                 ← the report (the agent reads the finding it is fixing)
├── AI-AGENT-FIX-PLAYBOOK.md                ← this file
├── tests/auditRegression{,2..8}.test.ts    ← 8 files, 78 tests
└── patches/
    ├── candidate-fixes-ACCT-001-004.patch
    ├── candidate-fixes-round2-ACCT-012-PO-001-PRET-001.patch
    ├── candidate-fixes-round4-production-safe-subset.patch
    ├── candidate-fixes-round5-PROD-001-PROD-005.patch
    ├── candidate-fixes-round6-WO-001.patch
    ├── candidate-fixes-round7-REP-001-004.patch
    ├── candidate-fixes-round8-AUTHZ-002-004.patch
    ├── candidate-fixes-round9-FILE-001-002-BK-001-005.patch
    └── policy-patch-ACCT-005-cash-purchase-funds-guard.patch   ← only after decision D1
```

**In the repo:**
```bash
git checkout 87f1265b            # the commit the patches were built against
git checkout -b audit-fixes
cd server && npm ci
cp ../../audit/tests/*.test.ts src/__tests__/       # adjust path to where you keep audit/
npx jest --silent 2>&1 | tail -20                    # BASELINE: expect the 78 new tests to be the only failures
```
Write down the baseline. Existing suite should be 113 suites / 991 tests green; the regression files should be mostly red.

**If you have already fixed some things yourself (you have):** commit your work first (`git add -A && git commit -m "my fixes so far"`) on the branch you want the agent to use, and use *that* HEAD as the baseline instead of `87f1265b`. The agent must not start applying patches until it has done **Phase 0b (triage)** below.

**If your repo is no longer at `87f1265b`:** tell the agent (below) to use `git apply --3way` and, when a hunk fails, re-implement the *intent* described in the report until the test passes.

---

## 1. Make the 7 decisions first (you, 20 minutes)

The agent cannot make these for you. My recommended defaults are in **bold** — reply "accept all defaults" or change any.

| # | Decision | Recommended default |
|---|---|---|
| **D1** | Require funds for cash purchases, salary and loans (ACCT-005, PAY-003)? | **Yes.** Same rule as owner withdrawals and supplier payments: "record opening cash / owner capital first". Fix the 12 fixture suites by adding one helper that seeds opening cash. |
| **D2** | Block reversals of cash inflows that would overdraw cash (ACCT-013)? | **Yes.** Reject capital edit/void and receipt delete if any cash/bank account would be below 0 on any later date; message: "reverse the later spending first". |
| **D3** | Salary overpayment model (PAY-001/002) | **Post once.** Split one payment into a current-month row (up to the remaining salary) and an advance row for the excess; the two rows total exactly what was paid, link the advance to its parent, and void both together. |
| **D4** | Salary-deduction loan repayments (PAY-004) | **Post Dr cash / Cr 1300** exactly like a direct repayment (the salary row was already posted at gross cash). |
| **D5** | The 14 permissions that guard routes but don't exist (AUTHZ-001) | **Seed all of them into `permissions`** so the roles screen can grant them (grant none by default). Rename `inventory:write` → `inventory:update`. Keep `admin:*` and `owner_equity:*` as seeded-but-sensitive. The AUTHZ-004 rule already stops non-admins granting what they don't hold. |
| **D6** | Is production overhead also recorded as an expense when incurred? (PROD-001) | **Ask your accountant.** If yes (usual): keep the current fix. If no: credit cash/payables for overhead instead of 7000. |
| **D7** | Back up `server/uploads/`? Allow damaged-stock write-off? | **Yes to both.** Zip uploads next to each DB backup; damaged write-off reuses the write-off flow with a reason code and account 7201 (or a new 7202). |

Save your answers in `audit/DECISIONS.md`; the agent reads it.

---

## 2. Rules for the agent (paste once at the start, or save as `CLAUDE.md` / `AGENTS.md` in the repo root)

```
You are fixing findings from an accounting/security audit of MiniERP.
Read audit/MiniERP-Audit-Report.md (finding details) and audit/DECISIONS.md (my decisions).

RULES
1. Work only on branch `audit-fixes`. One phase at a time. Commit once per patch/finding group
   with the finding IDs in the message. Never squash phases together.
2. The regression tests in server/src/__tests__/auditRegression*.test.ts are the specification.
   NEVER edit, skip, delete or weaken them to make them pass. If you believe a test is wrong, STOP
   and explain with evidence; I will decide. (Setup/fixture helpers you add elsewhere are fine.)
3. After EVERY step run: (a) the specific regression file, (b) the full suite
   `cd server && npx jest --silent`. A step is done only when both are green except for tests that
   belong to later phases. Paste the summary lines of both runs in your reply.
4. If a patch does not apply cleanly, use `git apply --3way`; if a hunk still fails, implement the
   intent from the report until the target tests pass. Say explicitly what you did differently.
5. Findings with no test yet: write the failing test FIRST (in a new file auditRegression9.test.ts),
   show it red on the current code, then fix, then show it green. Tests must encode correct
   behaviour, be independent of each other, and not depend on leftover state.
6. No unrelated refactors, renames or formatting changes. Keep diffs minimal and reviewable.
7. Maintain audit/FINDINGS-STATUS.md (table of all finding IDs: status, commit SHA, test name).
   Update it at the end of every step. Statuses: TODO -> RED(test written) -> GREEN(commit) -> VERIFIED, or from triage: ALREADY-FIXED / DIVERGED-ACCEPTED / PARTIAL / NOT-FIXED / UNCLEAR.
8. Do not start the next phase until I reply "go". At the end of each phase, stop and report:
   what changed, test results, anything surprising, and any finding you think is not really fixed.
9. If something is ambiguous or needs a product decision not in DECISIONS.md, ask me. Do not guess.
10. I have already fixed some findings myself. NEVER overwrite or revert my existing changes. Before
    touching any finding, check whether it is already fixed (Phase 0b). If my implementation differs
    from the audit patch but the tests pass and the root cause is addressed, KEEP MINE and mark it
    DIVERGED-ACCEPTED. Only add what is missing.
```

Then create `audit/FINDINGS-STATUS.md` from the table in Section 5 (or tell the agent: "create it from the table in the playbook").

---

## 3. Phases — paste one prompt at a time

### Phase 0 — Baseline (no code changes)
```
Phase 0. Check out 87f1265b into branch audit-fixes (or tell me which commit the repo is on if
different). Run `npm ci` and the full server test suite BEFORE copying the regression tests, then copy
audit/tests/*.test.ts into server/src/__tests__/ and run again. Report: existing suite totals, and
per regression file how many tests pass/fail. Create audit/FINDINGS-STATUS.md. Change no source code.
```
**Gate:** existing suite green; regression files mostly red (78 tests total, a few controls green).

### Phase 0b — Triage: what is already fixed? (read-only — do this BEFORE Phase 1)
```
Phase 0b — TRIAGE. Read-only: make NO code changes and NO commits.

I already fixed some findings myself. For EVERY finding ID in audit/FINDINGS-STATUS.md, determine
whether it is already fixed on the current branch.

Method:
1. Tests. Run each regression file and the full suite. A finding whose test(s) are green on the
   current code is a candidate ALREADY-FIXED; red means NOT-FIXED or PARTIAL.
2. Patches. For each file in audit/patches run
     git apply --check <patch>             (clean = not applied yet and no conflicts)
     git apply --reverse --check <patch>   (clean = already fully applied)
   If neither works the patch is partly applied or the code diverged: inspect hunk by hunk
   (`git apply --check --verbose`, or apply to a scratch copy) and list which hunks are present.
3. Code reading. Open the file/line cited in the report for each finding and decide whether the
   described defect still exists. Do not rely on tests alone: a test can pass through a workaround,
   so confirm the root cause described in the report is actually gone.
4. Findings with no test (ACCT-006/007/008/010/011, CODE-001..004, REP-005, PRET-002, WO-002, BK extras,
   Flutter items): write a quick THROWAWAY probe (do not commit it) that reproduces the report's
   scenario, or reason from the code with exact citations.
5. Coupled findings: ACCT-002 (P&L) is only safe if PROD-001 is also fixed. If I fixed the P&L but
   not production, report that as PARTIAL and say what is wrong (the test PROD-001G guards this).

Classify each finding as exactly one of:
  ALREADY-FIXED     - root cause gone; cite commit/diff and the passing test
  DIVERGED-ACCEPTED - my fix differs from the audit patch but tests pass and the root cause is fixed
  PARTIAL           - some of it fixed; say precisely what is missing
  NOT-FIXED         - defect still present
  UNCLEAR           - you cannot tell; tell me what you need

Output: (a) a table  ID | classification | evidence (test result, diff, file:line) | action needed;
(b) a revised Phase 1 plan: which patches to apply fully, which only partly (list the hunks/files),
which to SKIP entirely; (c) any place where my changes conflict with an audit patch or with a
decision in DECISIONS.md. Update FINDINGS-STATUS.md with the classifications.
Do not start fixing. Wait for my "go".
```
**Gate:** you read the triage table. Spot-check 3-4 `ALREADY-FIXED` rows yourself (open the diff and the test). Anything you disagree with, tell the agent before saying "go".

**How to read the triage result**
| Classification | What happens next |
|---|---|
| ALREADY-FIXED / DIVERGED-ACCEPTED | Nothing to apply. It is verified again in Phase 6. |
| PARTIAL | Agent completes only the missing part (smallest possible diff on top of your work). |
| NOT-FIXED | Apply the patch / do the phase as normal. |
| UNCLEAR | You decide, or ask the agent to write a probe test that settles it. |

### Phase 1 — Apply the verified patches, one at a time, in this exact order
```
Phase 1. Use ONLY the revised plan from Phase 0b: skip patches/hunks for findings classified
ALREADY-FIXED or DIVERGED-ACCEPTED, and never overwrite my existing changes. For patches that are
NOT-FIXED or PARTIAL, apply them in audit/patches IN THIS ORDER, one per step, committing after each.
For a PARTIAL patch, apply only the missing hunks (e.g. `git apply --include='path' <patch>`, or
re-implement by hand) and explain exactly what you added on top of my work.
The numbered list below is the full order; the 'must go' targets apply once all of a patch's
findings are in place:
 1 candidate-fixes-ACCT-001-004.patch            -> auditRegression.test.ts must go 18/18
 2 candidate-fixes-round2-ACCT-012-PO-001-PRET-001.patch -> auditRegression2: 4/5 (ACCT-005 stays red)
 3 candidate-fixes-round4-production-safe-subset.patch   -> part of auditRegression4
 4 candidate-fixes-round5-PROD-001-PROD-005.patch        -> auditRegression4 must go 11/11
 5 candidate-fixes-round6-WO-001.patch                   -> auditRegression5 4/4
 6 candidate-fixes-round7-REP-001-004.patch              -> auditRegression6 13/13
 7 candidate-fixes-round8-AUTHZ-002-004.patch            -> auditRegression7 10/10
 8 candidate-fixes-round9-FILE-001-002-BK-001-005.patch  -> auditRegression8 9/9
If my own fix replaced part of a patch, the same regression file must still reach its target.
After EACH patch: run its regression file and the full suite and paste the totals.
IMPORTANT: patches 1 and 4 are coupled (the P&L fix in patch 1 is only correct together with the
production fix in patch 4). Apply them in the same sitting and do not deploy between them.
Do NOT apply policy-patch-ACCT-005 yet (that is Phase 2).
Stop at the end and report.
```
**Gate:** full existing suite green after every patch; at the end regression files 1, 4, 5, 6, 7, 8 are fully green; file 2 has only ACCT-005 red; file 3 all red.
**You:** skim each commit diff (they are 3–150 lines each). Review `candidate-fixes-round5` and `round8` most carefully — they touch accounting posting and user permissions.

### Phase 2 — The decision-driven fixes (tests already written)
Give the agent one prompt per decision so each is a separate commit.

**2a — D1 cash-guard policy (ACCT-005, PAY-003)**
```
Phase 2a, decision D1 (see DECISIONS.md). Apply audit/patches/policy-patch-ACCT-005-... and extend the
same funds guard (assertSufficientFunds) to salary payments and employee loan disbursements. This will
break fixtures that seed stock/salary without opening cash: fix them by adding ONE shared helper
(e.g. seedOpeningCash in the test helpers) and using it in the failing suites - do not weaken the
guard and do not edit the regression tests. Targets: auditRegression2 (ACCT-005) and
auditRegression3 'PAY-003' tests green; full suite green. List every existing test file you changed.
```
**2b — D2 reversal guard (ACCT-013)**
```
Phase 2b, decision D2. Make owner-capital edit/void and customer-receipt delete refuse when the
reversal would leave any cash/bank account negative on any date after the entry (not only as of the
entry date). Also audit the same class in: supplier-refund void, loan-repayment void, customer payment
update. Add tests for those in auditRegression9. Targets: the 3 ACCT-013 tests in auditRegression3.
```
**2c — D3 salary overpayment (PAY-001, PAY-002)**
```
Phase 2c, decision D3. Fix employeeController salary overpayment so ONE payment is posted ONCE:
current-month row + advance row total exactly the amount paid; link advance to parent
(add column/migration, idempotent); voiding either voids both; salary history stays correct.
Targets: PAY-001 and PAY-002 tests in auditRegression3. Also add a test that history/remaining-salary
for the month and next month stays correct after overpay and after void.
```
**2d — D4 salary-deduction repayment (PAY-004)**
```
Phase 2d, decision D4. Post Dr cash/bank / Cr 1300 for loan repayments that carry salary_payment_id,
exactly like direct repayments. Target: the PAY-004 test in auditRegression3 (GL 1300 == loan balance
after repay and after write-off). Check the loan void/delete path posts the reverse correctly.
```
**2e — D5 permissions (AUTHZ-001)**
```
Phase 2e, decision D5. Write an idempotent migration that inserts every permission that routes use
but permissions table lacks (list is in the report, finding AUTHZ-001; derive the exact list by
scanning requirePermission(...) calls), rename inventory:write -> inventory:update in routes and DB.
Add a regression test that fails if any requirePermission(module, action) used in routes/ is missing
from the permissions table (so this can never regress). Also list seeded permissions that no route uses
and ask me what to do with each.
```
**2f — D6 confirmation (PROD-001)** — tell the agent your answer from D6. If "no": ask it to change the overhead absorption credit to cash/payables and update test PROD-001O accordingly *with my approval*.

**Gate for Phase 2:** auditRegression2 and auditRegression3 fully green, full suite green.

### Phase 3 — Findings that have NO test yet (test-first)
Use this template for each group; give the agent the group list and let it run all, one commit per finding.
```
Phase 3, group <name>. For each finding below: (1) read its section in the report; (2) write a failing
test in server/src/__tests__/auditRegression9.test.ts (independent, correct-behaviour assertions,
with a passing control where useful); (3) run it and show it RED on current code; (4) implement the
minimal fix; (5) show it GREEN and the full suite green; (6) commit "fix(<ID>): ..." and update
FINDINGS-STATUS.md. Findings: <list>
```
Groups, in this order:

| Group | Findings | Notes for the agent |
|---|---|---|
| **3a Dates & bounds** | ACCT-006, ACCT-007 | Strict `YYYY-MM-DD` validation on every date field of every create endpoint (reuse the owner-equity schema); reject dates beyond a configurable horizon (default today + 1 day for postings); reject negative tax/discount; cap tax ≤ 100%, discount ≤ 100% of line; sane upper bounds on price/quantity; a sale cannot be dated before the item's earliest stock. |
| **3b Aging** | ACCT-010, ACCT-011 | As-of-date aging must reproduce history (filter ledger rows by date); null `due_date` defaults to invoice date + terms; buckets must sum to the total. |
| **3c Error classification** | CODE-001 | Validation errors → 400/422 with the message, not 500. Introduce a `ValidationError` class and map it in the error handler; add tests for the cases listed in CODE-001. |
| **3d Auth hygiene** | CODE-002, CODE-003 | Refresh must re-read user (active, role) from DB; revoke refresh on logout/password change/role change; min password length 10; disable `admin123` fallback outside dev. |
| **3e Idempotency (server + Flutter)** | ACCT-008, CODE-004 | Flutter: send `Idempotency-Key` for sales returns/settlements, owner capital/withdrawal, salary payments, supplier refunds (use `core/utils/idempotency_key.dart`). Server: tests that replay with a key returns the original response and a second POST without a key is still allowed. |
| **3f Purchase returns & stock** | PRET-002, WO-002 | Make supplier-less cash purchases returnable (post Dr cash / Cr 1200); `refund_expected` must create a *pending* refund, not collect cash; damaged-stock write-off per D7; add a write-off reversal path. |
| **3g Reports** | REP-005 | Implement `groupBy.aggregates` (SUM/COUNT/AVG/MIN/MAX validated against the registry's `aggregateFns`) or reject grouped reports with non-aggregated columns; default and maximum row cap (e.g. 50,000); escape `%`/`_` in LIKE. |
| **3h Backups** | uploads, retention, startup, encryption note | Per D7 zip `server/uploads/` with each DB backup; retention must always keep the N newest regardless of age; run `PRAGMA quick_check` at server start and log loudly; document backup encryption/permissions in README; set restrictive file mode on the backups folder. |
| **3i Scope gaps (decide first)** | ACCT-009 | Expense accruals/prepayments, supplier bills, input tax, customer advances. These are features, not bugs — ask me which to build; otherwise record as accepted scope limits in the README. |

**Gate:** each finding has a red→green pair in the git history; full suite green.

### Phase 4 — Data repair for existing databases (before go-live)
```
Phase 4. Write a one-time, idempotent, DRY-RUN-first repair script (server/scripts/) that:
 (a) backfills the raw-material consumption entry (Dr 7000 / Cr 1200 at each production's
     material cost) for every non-deleted production that has none; dated in the CURRENT open period;
     marked with reference_type 'production_consume' so the new delete logic can void it;
 (b) rebuilds supplier balances from the supplier ledger (fixes headers hit by ACCT-012);
 (c) repairs stock_balances vs stock_batches drift caused by ACCT-003 and PROD-005 (report first,
     fix only with --apply);
 (d) reports (does not fix) any journal lines dated inside closed periods and any 3-decimal journal amounts.
Run order for me: backup -> run `npm run data:integrity` and `npm run gl:check` -> script dry-run ->
review output with me -> --apply -> run both checks again. Add tests on a seeded fixture database.
```
**Gate:** dry-run output reviewed by you (ideally your accountant) before `--apply` on real data. **Always back up first.**

### Phase 5 — Flutter client
```
Phase 5. Run `flutter analyze` and `flutter test` (install the SDK if needed) and report the baseline.
Then, as separate commits: (1) fix every analyzer warning/error without behaviour changes;
(2) replace `catch (_)` sites that swallow errors with logging or user-visible handling (list each
one and what you chose); (3) split the 7 largest files (names in the report, CODE-005) by extracting
widgets and calculation helpers WITHOUT changing behaviour - one file per commit, run flutter test
after each; (4) add a stricter analysis_options.yaml (e.g. very_good_analysis or an agreed rule set)
and fix what it reports. Show before/after counts.
```
**Gate:** `flutter analyze` clean, `flutter test` green, and you click through sales → return → payment → report once in the app.

### Phase 6 — Final completion audit (use a FRESH agent session)
```
You are a reviewer who has not seen this work. Repo branch: audit-fixes. Read
audit/MiniERP-Audit-Report.md and audit/FINDINGS-STATUS.md. For EVERY finding ID in the report:
 1. confirm a commit exists that addresses it (cite SHA) and the test that proves it (cite test name);
 2. run that test and show it green; read the diff and say whether it genuinely fixes the described
    problem (not just the test);
 3. list any finding that is only partially fixed, only 'accepted', or has no test.
Include the findings I fixed myself (ALREADY-FIXED / DIVERGED-ACCEPTED): re-verify those too, with the same rigor.
Then run the full server suite and flutter analyze/test. Output a table: ID | status | commit | test |
reviewer verdict. Do not fix anything; report only.
```
**Gate:** every row VERIFIED; any "partial" goes back to the relevant phase.

---

## 4. Habits that keep the agent honest

- **Tests are read-only for the agent.** If a test looks wrong, the agent must stop and show evidence. (Two of my own early tests were wrong and were corrected; that is normal — but a human decides.)
- **Always demand the two lines**: the regression-file summary and the full-suite summary, pasted, every step.
- **Review the diffs of phases 1 (patches 4 and 7), 2c and 4 yourself or with your accountant** — they change how money is posted or who can do what.
- **One finding or patch per commit**, so any step can be reverted: `git revert <sha>`.
- **If the agent says "done" without test output, say "show me the test output."**
- **Never run Phase 4 `--apply` on production data without a verified restore point** (use the corrected README restore procedure; test restoring into a scratch folder first).
- **Keep the sandbox DB separate from real data** while developing.

---

## 5. FINDINGS-STATUS.md — starting table (give this to the agent)

| ID | Title | Phase | Proof (test) | Status |
|---|---|---|---|---|
| ACCT-001 | Balance sheet after store-credit offset | 1 | auditRegression ACCT-001 | TODO |
| ACCT-002 | P&L covers all accounts (after PROD-001) | 1 | auditRegression ACCT-002 | TODO |
| ACCT-003 | Partial-return restock rounding | 1 | auditRegression ACCT-003 | TODO |
| ACCT-004 | Closed-period bypass on create | 1 | auditRegression ACCT-004 | TODO |
| ACCT-005 | Cash purchase funds guard | 2a | auditRegression2 ACCT-005 | TODO |
| ACCT-006 | Date validation | 3a | new (auditRegression9) | TODO |
| ACCT-007 | Tax / discount / price bounds | 3a | new | TODO |
| ACCT-008 | Duplicate submit without key | 3e | new | TODO |
| ACCT-009 | Scope gaps (accruals, bills, input tax, advances) | 3i | decision | TODO |
| ACCT-010 | AR aging as-of + null due date | 3b | new | TODO |
| ACCT-011 | AP aging as-of | 3b | new | TODO |
| ACCT-012 | Supplier balance after backdated purchase | 1 | auditRegression2 ACCT-012 | TODO |
| ACCT-013 | Cash inflow reversal overdraws cash | 2b | auditRegression3 ACCT-013 | TODO |
| PO-001 | Non-numeric goods receipt quantity | 1 | auditRegression2 PO-001 | TODO |
| PRET-001 | Purchase-return rounding | 1 | auditRegression2 PRET-001 | TODO |
| PRET-002 | Cash purchase return / refund_expected | 3f | new | TODO |
| PROD-001 | Raw-material relief in GL | 1 | auditRegression4 PROD-001* | TODO |
| PROD-002 | Production unit-cost rounding | 1 | auditRegression4 PROD-002 | TODO |
| PROD-004 | Negative overhead | 1 | auditRegression4 PROD-004 | TODO |
| PROD-005 | Production delete corruption | 1 | auditRegression4 PROD-005 | TODO |
| PROD-006 | Production closed period | 1 | auditRegression4 PROD-006 | TODO |
| PROD-007 | Self-production | 1 | auditRegression4 PROD-007 | TODO |
| PAY-001 | Salary overpayment double-posted | 2c | auditRegression3 PAY-001 | TODO |
| PAY-002 | Void leaves advance | 2c | auditRegression3 PAY-002 | TODO |
| PAY-003 | Salary/loan funds guard | 2a | auditRegression3 PAY-003 | TODO |
| PAY-004 | Salary-deduction repayment GL | 2d | auditRegression3 PAY-004 | TODO |
| WO-001 | Write-off precision | 1 | auditRegression5 WO-001 | TODO |
| WO-002 | Damaged stock write-off / reversal | 3f | new | TODO |
| WO-003 | Write-off closed period | 1 | auditRegression5 WO-003 | TODO |
| AUTHZ-001 | 14 unassignable permissions | 2e | new (drift test) | TODO |
| AUTHZ-002 | Admin account takeover | 1 | auditRegression7 AUTHZ-002 | TODO |
| AUTHZ-003 | Role assignment escalation | 1 | auditRegression7 AUTHZ-003 | TODO |
| AUTHZ-004 | Role self-grant | 1 | auditRegression7 AUTHZ-004 | TODO |
| REP-001 | Report entity permissions | 1 | auditRegression6 REP-001 | TODO |
| REP-002 | Report whitelist bypass | 1 | auditRegression6 REP-002 | TODO |
| REP-003 | Registry fields without columns | 1 | auditRegression6 REP-003 | TODO |
| REP-004 | HAVING bound value / grouped count | 1 | auditRegression6 REP-004 | TODO |
| REP-005 | Aggregates, row cap, LIKE escape | 3g | new | TODO |
| FILE-001 | Arbitrary file deletion | 1 | auditRegression8 FILE-001 | TODO |
| FILE-002 | Upload served as active content | 1 | auditRegression8 FILE-002 | TODO |
| BK-001 | Apostrophe in DB path | 1 | auditRegression8 BK-001 | TODO |
| BK-002 | Download not audited | 1 | auditRegression8 BK-002 | TODO |
| BK-003 | List/download/delete mismatch | 1 | auditRegression8 BK-003 | TODO |
| BK-004 | Same-second backups | 1 | auditRegression8 BK-004 | TODO |
| BK-005 | BACKUP_DIR ignored | 1 | auditRegression8 BK-005 | TODO |
| BK-006 | README restore procedure | 1 | (docs; reviewer checks) | TODO |
| BK-extra | Uploads in backup, retention floor, startup check, perms/encryption | 3h | new | TODO |
| CODE-001 | Validation errors as HTTP 500 | 3c | new | TODO |
| CODE-002 | Refresh trusts token claims | 3d | new | TODO |
| CODE-003 | Password length / default admin | 3d | new | TODO |
| CODE-004 | Client idempotency keys | 3e | new (+ Flutter test) | TODO |
| CODE-005…007 | Flutter quality (large files, swallowed errors, lints) | 5 | flutter analyze/test | TODO |
| DEPLOY-1 | Production backfill / supplier rebuild / stock repair | 4 | seeded-fixture tests + dry-run review | TODO |

\* PROD-001 is proven by three tests in `auditRegression4` (inventory delta, profit delta, overhead design) plus the GUARD test that protects the P&L fix.

---

## 6. If something goes wrong

| Symptom | What to tell the agent |
|---|---|
| A patch fails to apply | "Use `git apply --3way`; for failed hunks implement the intent from the report. Show me the differences from the patch." |
| A previously green suite goes red after a patch | "Revert that commit. Explain which existing test failed and why; propose the smallest change. Do not edit the existing test unless it encodes the bug." |
| The agent wants to change a regression test | "Stop. Show the evidence the test is wrong. I decide." |
| The agent starts applying patches without triaging | "Stop. Revert uncommitted changes. Do Phase 0b first; I already fixed some findings." |
| Agent says a finding is ALREADY-FIXED | "Show the diff (file:line), the passing test, and explain why the root cause in the report is gone." |
| Agent says "all done" | "Run Phase 6 with a fresh session and show the table." |
| You change a decision later | Update `DECISIONS.md`, tell the agent which findings it affects, and ask it to update the matching tests *with your approval*. |
