# Audit findings status

## Review cycle state — 2026-11-16 (coordinator record)

This section records the state of the GLM/PI review cycle. It is a status note,
not a re-audit; nothing below was re-derived.

**Main.** `main` and `origin/main` are both at `7a96e6d8`. CI is green on that
exact SHA (server, flutter, fallow).

**Open draft PRs.** Three, all drafts, none ready to merge:
`#3` `glm/extract-cash-timeline-only` (D21 extraction), `#4` `glm/ux-review-tests`
(UX fixes + parked tests), `#5` `glm/audit-reviews` (review docs). A reconciled
successor of `#4` is staged as `glm/reconcile-cycle2` (see below).

**D21 — implemented, not merged/resolved.** PR `#3` implements the D21
extraction (the lazy `require` between `accountingService` and
`cashBalanceGuard` becomes a leaf module, `services/cashTimeline.ts`). "Implemented
in a draft PR" is not "merged"; D21 stays open until that PR merges.

**Stock findings — not reproduced.** The stock-path review
(`audit/GLM-STOCK-REVIEW.md`, findings S-1..S-7 after the rename) is a read-only
reasoning pass. No stock finding was reproduced against a live database or a test.
They stay unconfirmed. PI is doing a **read-only** review/environment task this
cycle, including `#3`; PI produced no code changes on these files.

**Full-suite lock.** Unassigned. No agent holds the exclusive full-suite slot.

**Next order (coordinator).** S-2, then the F-3 dating decision and reproduction,
then S-3, S-4, S-1, S-5, S-6, S-7.

**F-2 un-parked (this cycle).** `7a96e6d8` fixed F-2 (a claim carrying a standing
write-off can no longer be cancelled). The parked `it.failing` wrapper was removed
and the case is now a normal regression guard. Red-first proof: with the `cancel`
guard in `SupplierRefundClaim.ts` temporarily reverted, the un-parked case failed
`Expected: >= 400 / Received: 200`; restored, it passes. Five tests remain parked:
four UX (UX-3, UX-6, UX-11, UX-13) and F-3. See the "Finding-tagged tests" section
below.

**PR #4 reconciliation (this cycle).** `glm/ux-review-tests` (old head `2e4a101a`)
was rebased onto `7a96e6d8` as `glm/reconcile-cycle2`. Overlapping files:
`audit/FINDINGS-STATUS.md`, `lib/data/repositories/purchase_repository.dart`,
`lib/features/purchases/refund_claim_write_off_dialog.dart`,
`server/src/__tests__/supplierRefundClaims.test.ts`,
`server/src/models/SupplierRefundClaim.ts`; plus `scripts/check.sh` and the
generated l10n (mine only, no main-side collision). PI's `653dfe43` and `7a96e6d8`
are preserved; one write-off implementation survives (the GLM superset with amount
and date fields subsumes PI's key-only fix; PI's `voidRefund` fix is kept verbatim).
`key_mandatory_endpoints_test.dart` (PI's wire-level spec) was adapted only in its
field selector (`.first` → `.last`, because the reconciled dialog has three
fields); every assertion is unchanged.

**Correction — the "no keyless Flutter caller" claim was partially wrong, and the
"void is key-mandatory" half is wrong.** The write-off route
`POST /supplier-refunds/claims/:id/write-off` **is** key-mandatory, and the Flutter
caller sent none, so the UI write-off would have been refused — `653dfe43` fixes
that. But `653dfe43` also named `POST /supplier-refunds/:id/void` as mandatory,
and that half is false. `653dfe43` is a **Flutter-only** commit and its message
says two routes mandate an Idempotency-Key via `startRequiredIdempotentRequest`;
only the write-off one is true. The void route
(`server/src/routes/supplierRefunds.ts:34`) and handler
(`server/src/controllers/supplierRefundController.ts:162`) call **no** idempotency
helper, and there is **no** `SUPPLIER_REFUND_VOID` scope (only
`SUPPLIER_REFUND_CREATE`, `SUPPLIER_REFUND_CLAIM_CREATE`,
`SUPPLIER_REFUND_CLAIM_WRITE_OFF`). **Runtime verification (GLM, isolated
test-only worktree):** a keyless void returned `HTTP 200`, so the route is not
key-mandatory. The wire-level Flutter test still proves the *client* sends the
header (it rejects at the Dio interceptor), but that is a client contract — it
does **not** prove a server mandate. The coordinator independently confirmed the
correction. The client comment `lib/features/purchases/void_refund_dialog.dart:53`
(PI-owned) still repeats the false server claim; recorded here, not edited.

**PI read-only reports (2026-11-16).** `readonly-cycle-report.md` (superseded) and
`readonly-cycle-report-v2.md` (the record). PI's cycles were read-only; no code
changes and no file overlap with this cycle's work.

- **PR #3 @ `971c4f5b`: NO FINDINGS** (behaviour-preserving). Reviewed by PI and
  **independently re-run by the coordinator** — 7 suites / 67 tests, exit 0, on a
  clean ext4 review worktree at the exact SHA (107.959s; log
  `/home/fawad/logs/minierp-orchestration-20261116/coordinator-pr3-targeted.log`;
  clean status after, `diff --check` passes, CI green on the exact SHA). Suites:
  `supplierRefundClaims`, `settlementCashIntegrity`, `supplierRefund`,
  `cashOutflowEditTimeline`, `moneyPathReviewGaps`, `cashInflowReversal`,
  `supplierRefundValidation`. **PR #3 remains draft — review is not merge
  approval, and the full suites / `scripts/check.sh` were NOT run.**
  The earlier 2-test delta is the F-2 two-test block from `7a96e6d8`, not a
  PR #3 regression.
- **Reconciliation clean rerun (2026-11-16) — `glm/reconcile-cycle2` @ `25820165`.**
  The coordinator reran, on a **clean ext4 worktree with real `npm ci`
  dependencies** (no NTFS symlink), `moneyPathFindingsRed`, `supplierRefundClaims`,
  and `supplierRefund.test.ts`: **3 suites / 34 tests, exit 0**, 154.519s
  (`/home/fawad/logs/minierp-orchestration-20261116/coordinator-reconcile-clean-targeted.log`).
  This includes **one expected failure (F-3, `it.failing`)** — F-3 is **not**
  fixed. Clean status before and after.
- **Environment correction (2026-11-16).** An earlier `glm-reconcile-346d` run of
  the same three suites was **deliberately terminated with SIGTERM (exit 143)**
  and produced **no completed result** — it was **not** a pass or a failure, and
  there is **no** pre-existing claim about those suites from it. Cause: that
  worktree carried an untracked `server/node_modules` **symlink** to the NTFS main
  checkout, which is **not clean** under the baseline rule. GLM removed the
  symlink. The retained clean baseline is the Orca-managed verification worktree
  `/home/fawad/orca/workspaces/minierp-flutter/glm-verify-25820165` at exact
  `25820165` with a real ext4 `npm ci` (exit 0; `better_sqlite3.node` is a
  2091520-byte regular file; smoke test `{ x: 42 }`). Dependency links are **not**
  hidden with `assume-unchanged`.
- **Evidence-file labels.** `f3-unwrapped-keyless-void.md` and
  `f2-reverted-guard-red.md` are **short reports with the key verbatim excerpts**,
  not full raw transcripts; relabelled accordingly. A full raw re-capture can be
  produced on request.
- **PR #6 (stock S-2) @ `819034da`: READ-ONLY review filed (v2, corrected).**
  `/home/fawad/logs/pr6-stock-s2-readonly-review.md`. Direction is right and the
  two named defects (full-take-per-bin, cross-warehouse) are real and fixed.
  **Review v2 corrections (coordinator-verified against the source graph;
  v1 claims withdrawn):**
  - flag-ON **returns** `consumeBatchesByLocation` and flag-OFF calls
    `consumeLegacyStock` — they are **not** both executed in one request, so the
    commit's "2 pre-fix red (OFF) + 2 green ON controls" is coherent and four red
    is **not** implied.
  - `consumeBatchesByLocation`'s final guard checks allocation **across batches**
    (`remaining`), not its inner `batchRemaining` bin remainder; the "opposite
    inner guard" v1 claimed does **not** exist.
  - the F2 example was corrected: master 10, bin 4, sell 6 → diff **4**, and the
    gap **pre-existed** the sale — not "bins drift 6 below the master".
  - the F1 fixture `physical=0, available=5` was invalid (a trigger keeps
    `available = MAX(0, physical − reserved)`); replaced by a reachable
    `DAMAGED` bin with `physical=5, reserved=0`.
  - the "pre-existing" label on the reserved-quantity point was removed (no
    clean known-good run), and `quantity_available > 0` **does** account for
    reservations, so that claim was overstated.
  Remaining hypotheses (R1 different bin predicates, R2 legacy drain can
  under-cover silently, R4 reservations) are routed to **PI for test-only
  reproduction** after the full run. No stock code changed; no tests run.
- **PR #6 (stock S-2) FULL GATE PASSED; slot released (2026-11-16, evening).**
  PI's full gate on `819034da`: **284 suites / 2273 tests, exit 0**
  (`scripts/check.sh --server` on the clean ext4 worktree). Coordinator
  independent clean rerun of S-2 + accounting invariants: **2 suites / 37
  tests, exit 0, 17.352s**
  (`/home/fawad/logs/minierp-orchestration-20261116/coordinator-s2-focused.log`).
  **Flag-OFF-only correction confirmed:** the pre-fix reds for the S-2 bin
  write are **flag-OFF only** (flag-ON controls green) — consistent with the
  coherent "2 pre-fix red (OFF) + 2 green ON controls" reading, not four red.
  Review v2's remaining findings (R1/R2/R4) stay **UNCONFIRMED hypotheses**;
  R2 is **not** a product choice for PI — PI reproduces/investigates the
  documented fallback, Gull owns the business tradeoff. With the gate green
  the test slot is **free**; UX work resumed on `glm/ux-fixes` (see
  `/home/fawad/logs/ux-redfirst-chronology.md` for the red-first evidence
  matrix).
- **PI S-2 triage recorded (2026-11-17, msg_d9c2829138fd).** Confirmed
  discrepancies with exact evidence: **R1** (legacy bin predicate omits the
  `status_override` filter the flag-ON predicate applies) and **R4**
  (reservations: legacy reads `physical`, not net-of-reserved `available`)
  are **real flag differences — DECIDED by Gull, see D28**; **R2** (legacy
  drain under-coverage as a NEW defect) is **dismissed as a defect** and
  **DECIDED as clamp-and-warn by Gull (D28)**. Review v2's findings may not
  be labelled confirmed/pre-existing without a run (D22). PI commits triage
  test-only; no stock overlap with `glm/ux-fixes`. The `d687e6bd` triage
  tests are **characterization** (pin today's behaviour), not
  corrected-semantics regression.
- **UX-11 loading round complete (2026-11-17).** The
  error-only UX-11 fix (`0535ffa0`) was a partial: the original scope is
  loading AND error. Coordinator rejected the done claim
  (msg_d9c2829138fd); the loading feedback was then implemented genuine
  red-first — `42c1b469` on `glm/ux-fixes`, evidence in
  `/home/fawad/logs/ux-redfirst-chronology.md` (pending test failed with
  `Found 0 widgets with type LinearProgressIndicator` BEFORE the change;
  revert-proof failed the same way; 4/4 green after restore; UX-3/6/13
  regression 3/3).
- **FLUTTER GATE on `0186b8d9`: PASSED — phase gate GREEN (2026-11-17).**
  Exclusive-slot run per msg_2834f953b232: clean ext4 detached worktree
  `glm-gate-0186b8d9`, `bash scripts/check.sh --flutter` only (server NOT
  rerun — unchanged tree; server evidence stays at `42c1b469`). **Result:
  exit 0, "all checks passed"** — flutter analyze ok, l10n drift ok,
  **flutter test 1212 passed / 1 skipped / 0 failed** ("All other tests
  passed!"), finding-tagged `it.failing=1` (expected F-3), RED-BY-DESIGN
  files=0. Raw log `/home/fawad/logs/gate-0186b8d9/check-flutter-raw.log`.
  The 42c1b469 gate's 3 failures are the same tests that now pass; no other
  flutter state changed. **Bounded combined evidence (stated honestly, not
  all on one SHA): server 284/284 suites, 2273/2273 tests, typecheck, lint,
  fallow @ `42c1b469`; flutter @ `0186b8d9`.** The only diff
  `42c1b469..0186b8d9` is `test/widgets/cash_blockers_list_test.dart`.
  **CORRECTION of an earlier wrong claim:** in the 42c1b469 result report
  (msg_80986a5a4c44) GLM claimed "status after CLEAN" without verifying.
  Actual: BOTH gate runs regenerated the 11
  `audit/accounting-audit/remediation/` render artifacts (PNG/JSON
  screenshots — environment-dependent pixel output of a test that refreshes
  the audit evidence). Not a code change; not committed; both retained
  worktrees restored to pristine at their exact SHAs (verified: 0 dirty
  paths each). Gate workspaces retained for independent reruns. Slot
  released.
- **FULL GATE on `42c1b469`: FAILED on 3 stale PRET-002 tests; fix committed
  (2026-11-17).** Exclusive-slot run, clean ext4 detached worktree
  `glm-gate-42c1b469`, `bash scripts/check.sh` (attempt 1 `./scripts/check.sh`
  exited 126 — the script is committed mode 100644; no tree change).
  **Server side fully green:** typecheck ok, lint ok, **284/284 suites,
  2273/2273 tests, exit 0** (1408s), fallow ok (0 changed files),
  flutter analyze ok, l10n drift ok, server `it.failing=1` = expected F-3,
  flutter RED-BY-DESIGN files=0. **Flutter test: 3 failures** (~1209 passed,
  1 skipped), ALL in `test/widgets/cash_blockers_list_test.dart` — they pinned
  the OLD raw rendering (`SALE`/`EXPENSE`, ISO dates) that UX-6 (`9cd46127`)
  was tasked to replace: `Expected: exactly one/3 matching candidates /
  Actual: Found 0 widgets with text containing SALE`. **Cause: the UX-6
  commit changed the row contract without updating its sibling
  characterization tests — a gate catch, not a pre-existing failure.** Fix:
  the three tests re-expressed to the new contract (localized/humanized
  labels, `Formatters.date` output; structural assertions unchanged in kind),
  `0186b8d9` on `glm/ux-fixes`; after the update 6/6 green
  (`cash-blockers-updated-green-raw.log`). Full log
  `/home/fawad/logs/gate-42c1b469/check-full-raw.log`. The gate workspace is
  retained at `42c1b469` for independent reruns. **New exclusive gate slot
  requested for `0186b8d9`; the phase gate remains pending until it passes.**
- **PI v2 corrections (do not propagate v1).** Withdrawn: the NTFS→BUG-011
  *causal* claim (unsupported), and the F-3 "the ONLY reversal that breaks the
  rule" universal claim (only the complete `reverseLedgerEntry` **caller**
  inventory is known — `invoiceReturnService.ts:1481`, `Payment.ts:198/:222/:726/:732`,
  `SupplierBill.ts:145`, `Purchase.ts:736`, `Invoice.ts:1099` — which covers
  callers, not every ledger write). `.gitignore` alone, `assume-unchanged`, and
  commit-once are **not** accepted as recurring-churn fixes. F-3 was a hypothesis
  in v1 and is now runtime-reproduced by GLM (see the correction above).
- **D21:** implemented in draft PR #3 and independently reviewed clean at
  `971c4f5b`; **still not merged and not resolved.**
- **Environment:** the repository and its dependencies are on NTFS
  (`/dev/nvme0n1p4`, ntfs-3g/FUSE); PI confirmed this. The ext4 move is **pending
  Gull's approval** — not executed.
- **Regenerated artifacts:** generator is
  `test/features/accounting_report_regressions_test.dart` (a test side-effect).
  Two JSON files change **one date line each** (`"Nov 15, 2026"` →
  `"Nov 16, 2026"`). The nine PNGs change **nine rendered date glyphs** (one
  8×12 px digit per image, `5`→`6`). **No broader claim of substantive
  non-date change is made** — the change is the date glyph, and that is all that
  is asserted.
- **Artifact policy:** do **not** accept `.gitignore` alone for tracked
  artifacts, `git update-index --assume-unchanged`, or "commit once" as a
  recurring-churn fix. The preferred direction is a **deterministic test clock**,
  pending Gull.
- **Money F-3:** PI escalated the discrepancy. **No dating implementation exists.**
  Any decision must keep both stores consistent. The two coherent options are
  (a) same-date reversal that respects the period lock, or (b) current-date
  GL **and** subledger reversal together, preserving historical postings (wider
  scope). A UTC-only adjustment does **not** resolve the as-of mismatch.
- **PI state:** preparing a clean review worktree for the coordinator's rerun;
  otherwise read-only.

**Deferred backlog (unchanged, carried forward).** Stage-2 keys, D20 (fallow gate
— no baseline change needed), BUG-011 (local `jest --coverage` ~11.6 h on three
suites; CI unaffected), task 8.6 (drop the old stock columns — deliberately
deferred, exit criteria not met), mobile keys, the remaining mutating-endpoint
keys, and the first-deployment checklist (`audit/FIRST-DEPLOYMENT-CHECKLIST.md`).

**OPEN-DECISION (proposals, not decisions taken).** Recorded in
`audit/DECISIONS.md` D26: F-3 dating, F-1 semantics (money review), UX-5/7
wording, audit-artifact policy, and the ext4 move.

## Accounting audit revalidation — 2026-10-26–27

The current F-001–F-073 accounting remediation is tracked in
[accounting-audit/remediation/STATUS.md](accounting-audit/remediation/STATUS.md).
That ledger distinguishes executed current behavior from historical audit labels.
Gull approved D15 later open-period settlement in this remediation chat; see the
updated decision log. No historical financial records were repaired.
The final source passed252 backend suites/2002 tests,1042 Flutter tests, the
unchanged quick gates and79 standalone reversal checks. Independent review is
CLEAR / APPROVE within the documented scope. Unsupported workflows, D12 and
unexecuted historical/native/concurrency cases remain explicit in the current
ledger. Older phase records below are dated evidence, not a new release assessment.

## Finding-tagged tests (skipped / expected-failure)

Five tests deliberately exercise known, unfixed findings (four UX + F-3). Each is
tagged with its finding ID so it stays visible and flips to a real failure when the
finding is fixed. `scripts/check.sh` prints the count (see "Finding-tagged test
count").

F-2 was un-parked on 2026-11-16: `7a96e6d8` fixed it (a claim with a standing
write-off can no longer be cancelled), so its `it.failing` wrapper was removed and
the test is now a normal passing regression guard. Red-first proof for the
un-park: with the `cancel` guard in `SupplierRefundClaim.ts` temporarily reverted,
the un-parked case failed `Expected: >= 400 / Received: 200`; with the guard
restored it passes.

| Finding | Test | Tag | Fails today because |
|---|---|---|---|
| F-3 (GLM-REVIEW) | `server/src/__tests__/moneyPathFindingsRed.test.ts` | `it.failing` with `F-3:` in the name | GL AP vs supplier subledger differ by 3,000 at as-of 2026-11-05 (`Expected: 0, Received: 3000`). |
| UX-3 (GLM-UX-REVIEW) | `test/features/supplier_refund_message_test.dart` | `skip: true`, `RED-BY-DESIGN … UX-3` | The refund-amount error contains "quantity" (`Found 1 widget with text containing quantity`). |
| UX-6 (GLM-UX-REVIEW) | `test/widgets/cash_blockers_localization_test.dart` | `skip: true`, `RED-BY-DESIGN … UX-6` | The blocker row leaks `receipt_overpayment` and raw ISO `2026-11-15`. |
| UX-11 (GLM-UX-REVIEW) | `test/features/sales_order_form_loading_test.dart` | `skip: true`, `RED-BY-DESIGN … UX-11` | A failed customer load renders as an empty picker; `Found 0 widgets with text containing Failed`. |
| UX-13 (GLM-UX-REVIEW) | `test/features/sales_order_discount_validation_test.dart` | `skip: true`, `RED-BY-DESIGN … UX-13` | A flat discount above the line total passes validation (`errorText` is `null`). |


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
| ACCT-006 | GREEN (full suite + quick gate) | current worktree | backdatedSaleWarning.test.ts (6 passed, red-first 5/6); inventoryEffectiveDate.test.ts (13 passed, D1/D3 updated to the D19 contract); 30 more targeted suites across the consumption surface (invariants A–J, production, withdrawals, transfers, POS, mobile, invoice lifecycle) all green; scripts/check.sh --quick EXIT=0 (2026-11-13) | D19: a sale dated before the item's first purchase receipt is accepted with a `warnings` array, a `backdated_before_receipt` flag and batch-linked actual-cost COGS from the later receipts (`StockMovement.consumeForSale` / `preReceiptFallback`); `GET /invoices/backdated` lists flagged invoices. Oversell, expired-at-sale, insufficient as-of stock, blocked locations and closed periods still refuse. Flag-ON sales of API-purchased batches (no `batch_stock_by_location` rows) now consume batch-level at actual cost instead of the NULL-batch standard-cost fallback, removing an invariant-H drift when `standard_cost` differs from batch cost. | Full server suite 269 suites / 2139 tests passed (2026-11-14); docs updated (API.md, DATABASE.md, INVENTORY-EFFECTIVE-DATES.md). |
| ACCT-007 | GREEN | — | auditRegression9 ACCT-007 | invoiceCreate items were `z.array(z.any())`, so no line was bounded. A typed `invoiceLine` schema now enforces: tax_rate 0-100, unit_price strictly positive and <= 1e9, discount_value >= 0, and percentage discount <= 100 (previously clamped to 0 while COGS was still posted). Negative and absurd values are rejected with 400. Verified by 6 red-first tests plus full-suite run. | Keep the bounds; revisit 1e9 ceiling only if a real document needs more. |
| ACCT-008 | GREEN (staged rollout; 16 keyed writes; full-suite re-run in progress) | current worktree | idempotencyMandate.test.ts (13 passed, red-first each stage); doubleVoidState (6 passed); invoiceIdempotency, idempotencyRound1/2, supplierBills, supplierPrepayments, purchaseReturn, accountingInvariants, auditRegression4/9, stockTransfer, stockTransferVoid, closedPeriodImmutability and others (all passed); scripts/check.sh --quick EXIT=0 (2026-11-14) | D19 widening continues in stages. Stage 1: `POST /api/pos/sale` logs keyless writes (`logKeylessIdempotentWrite`) but still accepts them (older desktop builds). Stages 2–5 (all now 400 keyless, replay on retry): `POST /api/purchase-returns`, `POST /api/productions`, supplier bill create/pay + prepayment create/apply (was optional → now required), `POST /api/inventory/stock-movements` and `POST /api/inventory/stock-transfers`. **No key needed** (naturally idempotent by state): `POST /api/accounting/periods/:id/close` (`alreadyClosed:true`), `POST /api/physical-counts/:id/complete` (fails on Completed), `POST /api/physical-counts/:id/items` (set-based upsert). `/api/mobile-invoices/*` stays keyless (D13). | Commits e58311ae, 3a5450ec, 2b125db3, 4a83ca46, 5cefd018. Full coverage run queued. See DECISIONS.md D19. |
| ACCT-009 | GREEN (full verification) | — | D13; server: 164 suites / 1457 tests passed; client: 1001 tests passed; `flutter analyze` clean | Accrual expenses, non-stock bills, direct/PO input tax and supplier advances are implemented. Mounted lifecycles cover gross payment, partial returns, voids, reporting, rejected applications, bill correction and retry safety. Separate GL controls cover 2115, 1320 and 1330. Full server and client suites now pass with the accounting invariants in place. | None outstanding. See ACCT-009-IMPLEMENTATION.md and REMAINING-ISSUES-2026-10-18.md. |
| ACCT-010 | GREEN (targeted verification) | 8f3431ad + current worktree | arHistoricalAging.test.ts, arSurfaceConsistency.test.ts, arPartialReturn.test.ts, api.integration.test.ts | Historical AR uses invoice cutoffs, dated positive receipt allocations, dated returns/fees and unapplied-cash application dates. Null due dates remain in the current bucket; summary uses the same customer buckets. Five regressions observed red; 4 suites / 89 tests green (2026-10-18). Legacy header-only amounts retain their invoice-date interpretation. | Full implementation-phase checks pending; no historical data repair. |
| ACCT-011 | DIVERGED-ACCEPTED | 3cab5c7d | apSingleDerivation.test.ts:131-155 (PASS) | Reports.ts:343-414 derives AP aging from ledger entries filtered through as-of date; apSingleDerivation.test.ts:131-155 covers later purchases/credits and passes in full suite. | Keep existing ledger-based implementation. |
| ACCT-012 | ALREADY-FIXED | 8badf489 | auditRegression2 ACCT-012 | SupplierPaymentService.ts:63-73 and Purchase.ts:296 rebuild supplier balances; regression passes. | Keep existing fix. |
| ACCT-013 | GREEN (full verification) | f9a72d63 + current worktree | cashInflowReversal.test.ts, supplierRefund.test.ts, cashOutflowEditTimeline.test.ts, accountingInvariants.test.ts, settlementCashIntegrity.test.ts | SupplierRefundModel.void wraps all effects in a transaction, records GL void lineage, checks the original accounting period and asserts the chronological cash balance. Cash-timeline refusals now return 409 with structured blockers (id, date, amount, type) for the first deficit date; all cash-affecting controllers honor the embedded status. The ACCT-013 sweep found and fixed the same hole in OwnerWithdrawal.update and Expense.update (moved-earlier outflow overdraws a later day); both now run the double assertCashTimeline inside the re-post transaction. A source-scan tripwire pins the guard in all five cash-affecting models. Red regressions observed for every fix. Full server suite 266 suites / 2112 tests passed with invariants A–J; scripts/check.sh --quick passed (2026-11-13). | Residual: backdated creation of cash outflows still uses the point-in-time check only (D2/D19 scope was edits, voids and reversals); recorded in DECISIONS.md D19. Claim-lifecycle reset lands with PRET-002. |
| PO-001 | ALREADY-FIXED | 8badf489 | auditRegression2 PO-001 | purchaseOrderController.ts:396-400 rejects nonnumeric, nonfinite, boolean and nonpositive quantities; regression passes. | Keep existing fix. |
| PRET-001 | ALREADY-FIXED | 8badf489 | auditRegression2 PRET-001 | PurchaseReturn.ts:314,350,364 rounds lines and total as money; regression passes. | Keep existing fix. |
| PRET-002 | GREEN (server) / corrected 2026-11-16: the UI write-off was broken | f31c511e / 3cab5c7d + current worktree | supplierRefundClaims.test.ts (new, 10), supplierRefund.test.ts, idempotencyRound2.test.ts, purchaseReturn.test.ts, creditOffsetSubledger, ledgerIntegrity, accountingInvariants, glBalanceInvariant, supplierPayment, **key_mandatory_endpoints_test.dart (new, 2)** | D19 full build: `supplier_refund_claims` + `refund_receipt_allocations` (SRC-… claim numbers, legacy backfill SRC-LEGACY-*), account 7300, receipts post `REFUND_RECEIPT` (Dr cash/bank / Cr AP) with allocation capped at claim remaining, excess rejected by default or booked as supplier credit on one entry (`treat_excess_as_advance`), write-offs Dr 7300 / Cr AP + supplier-ledger mirror with mandatory reason (owner-only above Rs 1,000 → role admin), claims API under /supplier-refunds/claims with mandatory Idempotency-Key, return void blocked (409 + blockers) while receipts are live, receipt void releases the claim, Flutter refund dialog shows the claim and cash/bank-only methods. Red-first: claims suite written before the model fixes; 12/12 refund-claim tests green (the suite has 12 `it(` cases, not 21 — that figure was wrong); targeted regression suites green. Flutter UI added 2026-11-14: refund-claim list tab with status chips and a default open-only filter, standalone + return-backed receipt dialog, write-off dialog (reason mandatory, admin-disabled above Rs 1,000), refunds-due badge on the supplier header and dashboard, and the 409 `cashBlockers` list. No void entry point yet — see BUG-008. **CORRECTION (2026-11-16, `653dfe43`):** the server mandates an Idempotency-Key on `POST /supplier-refunds/claims/:id/write-off`, and the Flutter caller sent none, so the UI write-off would have been refused with 400. The earlier note in this row and an earlier report claiming "no keyless Flutter caller exists" were WRONG. `writeOffClaim` now takes a required key and passes the header; the dialog supplies it from an `IdempotencyKeyCache`. Proved by a wire-level test that intercepts the real `RequestOptions` — red-first, it failed with `Actual: <null>` before the fix. **CORRECTION 2 (2026-11-16):** `653dfe43` also named `POST /supplier-refunds/:id/void` as key-mandatory, but that is **false**. The void route/handler call no idempotency helper and there is no `SUPPLIER_REFUND_VOID` scope; a keyless void returns HTTP 200 (verified at runtime in an isolated test-only worktree). The client still sends a key there (harmless, optional contract) but no server mandate exists. | Full server suite verified 269/2139 (2026-11-14); Flutter suite + scripts/check.sh pending for the UI. **The UI write-off is now covered by an assertion on the actual request; the void's key is client-optional.** D13 residual: claim-lifecycle reset done, see DECISIONS.md D19 implementation record. |
| PROD-001 | GREEN | 6eba103c | auditRegression4 PROD-001, PROD-001O, PROD-001G, PROD-001b | Material consumption now posts Dr production_clearing / Cr inventory_asset (`production_consume`), and overhead posts Dr production_clearing / Cr 2200 (`production_overhead`). All four regression4 cases pass. | Verified by targeted and full-suite runs. Joint-cost allocation for oil/cake is now implemented (D6, multi-output). |
| PROD-002 | GREEN | 78e5c8e8 | auditRegression4 PROD-002 | Production.ts:341 posts roundCurrency(output_quantity * costPerUnit), matching batch value; its regression passes. | Verified by targeted and full-suite runs; preserve in subsequent patches. |
| PROD-004 | GREEN | 78e5c8e8 | auditRegression4 PROD-004 | Production.ts:144-147 rejects nonnumeric, nonfinite or negative overhead; its regression passes. | Verified by targeted and full-suite runs; preserve in subsequent patches. |
| PROD-005 | GREEN | 6eba103c | auditRegression4 PROD-005, PROD-005a, PROD-005b | Delete guards the period, refuses once output is partly moved, voids both `production_consume` and `production_overhead`, and restores batches with `skipAdjustmentFinancialPosting`. | Verified by targeted and full-suite runs. |
| PROD-006 | GREEN | 78e5c8e8 | auditRegression4 PROD-006, auditRegression5 WO-003 | Production rejects closed-period production before writes; round5 also added the shared `postLegacyStockEntry` period guard used by the new production postings. | Verified by targeted and full-suite runs; preserve in subsequent patches. |
| PROD-008 | GREEN | 38f25161 | expiryHasExpiryGuard.test.ts (10 cases) | D6 guarded only the production output path. A batch whose item has `has_expiry = 0` could still be given an expiry_date by purchase, goods receipt or PATCH /stock-batches/:id. Inert until expiry tracking is switched on for that item, at which point every such historical batch is swept to EXPIRED in one boot. Invariant moved to `ItemModel.batchExpiryDate`; all four write paths route through it. | Verified red-before-green: disabling the guard fails exactly the 3 previously-ungated paths. See D11. |
| PROD-009 | GREEN | 1d8a2d74 | multiOutputProduction.test.ts (11 cases) | End-to-end joint-production verification: materials deducted, one batch per output, overhead absorbed, relative-sales-value weighting, allocated costs summing EXACTLY to total_batch_cost, unit_cost = allocated/qty, production_clearing balancing, reversal restoring stock and GL, and negative-stock/duplicate-output/output-is-input rejections leaving no partial writes. Surfaced a real defect: a second DELETE returned 500 because the controller mapped every error to 500; now 404. | Exact-cent assertions; verified by targeted and full-suite runs. |
| PROD-007 | GREEN | 78e5c8e8 | auditRegression4 PROD-007 | Production.ts:148-150 rejects identical input/output items; its regression passes. | Verified by targeted and full-suite runs; preserve in subsequent patches. |
| PAY-001 | DIVERGED-ACCEPTED | f9a72d63 | auditRegression3 PAY-001 + auditRegression3Recovered (PASS) | employeeController.ts:286-360 splits and links rows; accountingService.ts:1557-1597 posts salary/1310 advance once. Corrected regression3 and recovered regression pass. | Keep D3 implementation and add-salary-advance-link.sql migration. e46fc432 corrected only the approved test. |
| PAY-002 | DIVERGED-ACCEPTED | f9a72d63 | auditRegression3.test.ts, auditRegression3Recovered.test.ts | D13: user explicitly selected parent-only voiding. Voiding the parent salary payment voids both linked rows; a direct child-advance void remains blocked with 409. Fresh verification: 2 suites / 16 tests passed (2026-10-18). | Keep the approved parent-only behavior. |
| PAY-003 | ALREADY-FIXED | f9a72d63 | auditRegression3 PAY-003 | accountingService.ts:1581-1583 and postLoanDisbursementEntry enforce funds; both regression3 cases pass. | Keep existing guards and funded fixtures. |
| PAY-004 | ALREADY-FIXED | f9a72d63 | auditRegression3 PAY-004 | employeeController.ts:777-827 validates salary deduction and posts repayment; account 1300 is loan receivable; regression3 passes. | Keep existing implementation. |
| WO-001 | GREEN | a8266f37 | auditRegression5 WO-001 (2 cases) | StockMovement.ts uses the batch's exact unit cost and rounds the write-off VALUE to currency precision; `postLegacyStockEntry` normalises every amount with `roundCurrency` and rejects a value that rounds to zero. All 4 regression5 tests pass. | Verified by targeted and full-suite runs. |
| WO-002 | GREEN | — | auditRegression9.test.ts WO-002 cases | The damaged write-off endpoint and Dr 7202 / Cr 1200 regressions already exist. Fresh verification: auditRegression9 passed in the combined 9-suite / 139-test run (2026-10-18), including no-expiry batches, DAMAGED-warehouse batches and expired-endpoint rejection. | Keep existing implementation; earlier NOT-FIXED entry was stale. |
| WO-003 | GREEN | 6eba103c | auditRegression5 WO-003 | Round5 added the shared `postLegacyStockEntry` closed-period guard, which covers write-offs and the new production postings; regression5 passes. | Verified by targeted and full-suite runs. |
| AUTHZ-001 | GREEN | 0bbac98d | auditRegression9 AUTHZ-001 (3 cases) | A drift test walks `routes/`, `controllers/` and `middleware/` for every `requirePermission('m','a')` call and asserts each code exists in `permissions`. Migration `add-missing-guarded-permissions.sql` seeds the 17 genuinely absent codes; `stockBatches.ts` uses `inventory:update` per D5. | Verified by targeted and full-suite runs. |
| AUTHZ-002 | GREEN | 235b01ab | auditRegression7 AUTHZ-002 | Password and status mutations now protect admin targets; all 10 regression7 tests pass. | Verified by targeted and full-suite runs. |
| AUTHZ-003 | GREEN | 235b01ab | auditRegression7 AUTHZ-003 | Privileged role assignment requires the actor check that was previously missing. | Verified by targeted and full-suite runs. |
| AUTHZ-004 | GREEN | 235b01ab | auditRegression7 AUTHZ-004 | Permission grants now require the actor to possess the permission being granted. | Verified by targeted and full-suite runs. |
| REP-001 | GREEN | 32c13c05 | auditRegression6 REP-001 (3 cases) | Custom reports now require the entity's read permission to execute or list it; all regression6 cases pass. | Verified by targeted and full-suite runs. |
| REP-002 | GREEN | 32c13c05 | auditRegression6 REP-002 | HAVING fields are whitelist-enforced and computed aliases are protected in `reportQueryEngine`. | Verified by targeted and full-suite runs. |
| REP-003 | GREEN | 32c13c05 | auditRegression6 REP-003 | `entityRegistry` no longer advertises the nonexistent `stock_balances.id` and BOM quantity fields. | Verified by targeted and full-suite runs. |
| REP-004 | GREEN | 32c13c05 | auditRegression6 REP-004 | COUNT construction now carries the grouped/HAVING query structure while sharing the existing bindings. | Verified by targeted and full-suite runs. |
| REP-005 | GREEN | 56205265 | auditRegression9 REP-005 (4 cases) | `groupBy.aggregates` is now rendered as SELECT items, restricted to an advertised field and an aggregate function the registry lists for it, with a non-colliding alias. Reports always get a bounded row count (`DEFAULT_REPORT_ROWS` 500, `MAX_REPORT_ROWS` 1000). `contains`/`starts_with`/`ends_with` escape `%`, `_` and `\\` and declare `ESCAPE`. | Verified by targeted and full-suite runs. |
| FILE-001 | GREEN | 73b6ccfc | auditRegression8 FILE-001 (3 cases) | Employee document upload no longer trusts a supplied `file_path`, and deletion requires employee ownership; all 9 regression8 tests pass. | Verified by targeted and full-suite runs. |
| FILE-002 | GREEN | 73b6ccfc | auditRegression8 FILE-002 | Uploads validate extension and MIME, and employee documents are served as attachments rather than inline. | Verified by targeted and full-suite runs. |
| BK-001 | GREEN | 73b6ccfc | auditRegression8 BK-001 | The `VACUUM INTO` path is quoted, so a data path containing an apostrophe no longer breaks backup. | Verified by targeted and full-suite runs. |
| BK-002 | GREEN | 73b6ccfc | auditRegression8 'downloading a backup writes an audit row' | A backup download now writes a `BACKUP_DOWNLOAD` activity row like create/delete do, alongside the pre-existing dot-segment-safe `res.download`. | Verified by targeted and full-suite runs. |
| BK-003 | GREEN | 73b6ccfc | auditRegression8 'every backup the list shows can be downloaded and deleted' | The download path and the `backupService` name validator were reconciled, so any name the list returns is downloadable and deletable. | Verified by targeted and full-suite runs. |
| BK-004 | GREEN | 73b6ccfc | auditRegression8 'two backups requested back to back both succeed' | Backup filename timestamps are second-granular, so two backups in the same second no longer collide. | Verified by targeted and full-suite runs. |
| BK-005 | GREEN | 73b6ccfc | auditRegression8 BK-005 | `BACKUP_DIR` now overrides the backup location instead of always using `DB_DIR/backups`. | Verified by targeted and full-suite runs. |
| BK-006 | GREEN | 73b6ccfc | (docs; reviewer checks) | The restore runbook no longer copies from the wrong `../backups/` path. It copies from `backups/`, verifies integrity on the copy first, moves the live DB aside into `pre-restore/`, and swaps in only after the check passes, so a bad backup cannot destroy the live database. `BACKUP_DIR` is documented. | Documentation only; reviewed by reading the runbook, the destructive procedure was not executed. |
| BK-extra | NOT-FIXED | — | Source reasoning; later new | backupService.ts:91-137 backs up DB only; :58-82 lacks retention floor. Startup physical integrity/perms/encryption work has no acceptance proof. | D7 uploads and remaining backup hardening need independent regression9 coverage before fixes. |
| CODE-001 | GREEN (targeted verification) | — | clientValidationStatus.test.ts, businessErrorClassification.test.ts and dependent suites | Shared invoice validation uses typed business errors and checks customer/item existence before writes. Desktop/mobile line validation rejects invalid and nonfinite quantities; production business errors are mapped through handleBusinessError. Mounted regressions observed red, then green. Latest combined authority/validation run: 9 suites / 139 tests passed, including accounting invariants (2026-10-18). | Full implementation-phase checks pending. |
| CODE-002 | GREEN (targeted verification) | — | authAuthority.test.ts, authAsync.test.ts, security.regression.test.ts, auditRegression7.test.ts | Access and refresh reload active account authority; assigned role takes precedence over legacy role; disabled/deleted accounts and refresh-as-access are rejected. Red: 10 failed / 1 passed. Green: 4 suites / 71 tests passed (2026-10-18). | Full implementation-phase checks pending; see REMAINING-ISSUES-2026-10-18.md. |
| CODE-003 | GREEN (targeted verification) | — | passwordPolicy.test.ts, authAuthority.test.ts, databaseInitialization.test.ts, password_validation_test.dart | New password writes require 12 Unicode characters and at most 72 UTF-8 bytes. Bootstrap requires an explicit valid password in every environment. Assigned system Admin role governs profile, login, administration and access; custom role names cannot confer admin. Server regressions and 7 bootstrap checks passed; 3 widget regressions red then green. Typecheck, lint and Flutter analyze passed (2026-10-18). | Final visual QA and implementation-phase full suites pending. |
| CODE-004 | GREEN (targeted) | — | money_submission_idempotency_test.dart; repositories_test.dart | Remaining financial forms send retry keys stable for unchanged bodies and rotated after edits. Goods receipts and salary deductions are covered too. Return settlement now sends the server's allocations field. Eight form cases pass, including the new credit-expense payment flow. | Final phase checks pending. |
| CODE-005 | GREEN (targeted verification) | — | CODE-005-EXTRACTIONS.md; 7 extraction phases, 102 focused tests passed | All seven rendering/export responsibilities are extracted and verified sequentially: CSV builders/encoding, invoice responsive layout, dashboard sales-vs-purchases panel, date-picker calendar and focus state, purchase-order line editor, invoice return row and position preview, supplier allocation rows. Characterization was added before each move; state and controller ownership stayed with the parent; `flutter analyze` is clean. | Full Flutter suite at phase completion. |
| CODE-006 | GREEN (targeted verification) | — | auth_storage_failure, api_client, recoverable_failure, preferences/grid tests: 29 passed | Login storage failures remain signed out with a visible localized error; failed refreshed-token persistence does not retry stale credentials. Twenty-four catch sites now use safe diagnostics; nine retain visible handling or usable recovery. Salary deduction failure was fixed atomically. | Final full Flutter checks pending; see FLUTTER-ERROR-AND-LINT-REVIEW.md. |
| CODE-007 | GREEN (targeted verification) | — | analysis_options.yaml; FLUTTER-ERROR-AND-LINT-REVIEW.md; `flutter analyze` no issues | Six async/resource/error-preservation lint rules enabled and the tree is clean under them: 34 findings fixed at the source with `await`, explicit `unawaited(...)` or an import removal. No suppression, no `exclude:` entry, no rule change. JSON maps and valid late fields remain explicit supported patterns. | Full Flutter suite at phase completion. |
| DEPLOY-1 | CLOSED (not needed: the data is disposable) | — | D13; AGENTS.md; live restore test 2026-11-15 | Not needed. The live database held dummy development data only, so no backfill or repair was warranted. The dev database was reset on 2026-11-15 and the restore test now passes clean. **The live restore test proved the backup, verify and restore-smoke scripts work end to end. Repeat that test on the first real production data before relying on it.** Production material relief stays fixed in source (PROD-001). | — |

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
- **Historical data (DEPLOY-1):** CLOSED — not needed, the live data was disposable dummy development data. The dev database was reset on 2026-11-15 and the restore test passes clean. The live restore test proved the backup, verify and restore-smoke scripts work end to end; **repeat it on the first real production data** before relying on it. Do not infer historical correctness from test fixtures.

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

- ~~Joint-cost allocation between mustard oil and mustard cake by relative sales value~~ **Now implemented.** `production_outputs` (migration `add-production-outputs.sql`, legacy rows backfilled) holds one line per output; joint cost (materials + overhead) splits by relative sales value using `items.standard_selling_price`, with a quantity-share fallback when no output is priced. Per-output batch, movement and GL posting; delete reverses every line. `POST /api/productions` accepts `outputs: [...]` alongside the legacy `output_item_id` + `output_quantity`. Covered by auditRegression9 D6 (4 cases) and a full-suite run.
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

## Historical Phase 3 queue (superseded by the findings table)

These have no failing test because none was supplied. Per the rules each needs a test written
and shown red before any fix, so they are NOT part of the green suite above:

| Finding | Why still open |
|---|---|
| AUTHZ-001 | `seedDefaultPermissions` lacks the audit's requested permission codes. Needs the exact code list confirmed before implementation. |
| REP-005 | Group aggregates ignored, unbounded limit, and further items in `reportQueryEngine`. Needs a test per sub-item. |
| WO-002 | `StockMovement` insists on expired batches and `inventoryController` handles the case; no test encodes the intended behaviour yet. |
| CODE-005..007 | Flutter client quality observations (large files, error handling). `flutter analyze` passes; the audit itself did not run it. |
| D6 joint-cost allocation | ~~Mustard oil/cake allocation by relative sales value is unimplemented: `CreateProductionDTO` accepts a single output item.~~ **Done** — multi-output with relative-sales-value allocation (see the D6 section above). **Server + Flutter**: the production form adds co-product lines and posts `outputs[]` when any exist (legacy shape otherwise); the detail dialog renders the split; a client preview mirrors the server's allocation. Also fixed a D6-introduced defect: the single `expiry_date` was stamped on **every** output batch, and the boot-time expiry sweep filters on `expiry_date` alone — a non-expiry co-product would have been swept to EXPIRED. Expiry is now stamped only on outputs whose item has `has_expiry` (regression test in auditRegression9). |
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

## Phase 3, REP-005 report engine gaps

- Red first: all four new cases failed on the current engine, then passed after the fix.
- Targeted `auditRegression9.test.ts`: `Test Suites: 1 passed, 1 total`; `Tests: 8 passed, 8 total`.
- Also re-run `auditRegression6.test.ts` (13 passed), `reportExpressionSecurity.test.ts` and
  `apReporting.test.ts` (8 passed) as guardrails on the engine change.
- Full `npx jest --silent`: `Test Suites: 136 passed, 136 total`; `Tests: 1213 passed, 1213 total`;
  `Snapshots: 0 total`; `Time: 703.231 s`. Log: `/tmp/phase3-rep005-full.log`.
- Typecheck passed.

### Changes to `reportQueryEngine.ts`

1. **Aggregates are rendered.** `buildSelectClause` now emits
   `FN(table.field) AS alias` for each `groupBy.aggregates` entry. Each is validated: the field must
   be in the entity whitelist, the function must be one the registry lists in that field's
   `aggregateFns`, and the alias must not collide with an existing column. This closes the alias
   gap REP-002 closed on the HAVING side - an aggregate alias is now a real column rather than a
   name only HAVING could see.
2. **Every report is bounded.** `LIMIT` is now always emitted with `effectiveRowLimit()`: absent,
   non-finite or non-positive requests fall back to 500, and anything above 1000 is clamped. The
   count query drops exactly one trailing parameter, so the shared-binding fix from REP-004 still
   holds now that the LIMIT parameter is unconditional.
3. **LIKE metacharacters are literal.** `contains`, `starts_with` and `ends_with` escape `\`, `%`
   and `_` in the user's value and emit `LIKE ... ESCAPE '\\'`. Previously `contains: '%Alice'`
   matched every value merely *containing* 'Alice'.

### Test-fixture correction worth recording

The first draft of the aggregate case filtered on `employee_code`, assuming the employees API honours
a supplied code. **It does not** - it assigns its own `EMP-<year>-<n>` code. The filter silently
matched nothing and the case looked like an engine failure. The fixture now selects on `salary > 100`
so it is independent of generated codes. Two row-limit cases were also initially vacuous because the
database held too few rows to exceed any cap; the fixture now bulk-inserts 1,200 rows so the cap is
observable.

### Still open

WO-002 needs decision D7 and has no test yet. See the decisions listed under AUTHZ-001 above.

## DB-INIT-001 importing the database module executed all 107 migrations

`config/database.ts` opened the connection and then ran its entire migration ledger as
top-level statements, so merely importing the module wrote to the database. Anything that
imported it for read-only reasons inherited the write.

### How it was triggered

`scripts/verify-invariants-live.ts` imports the A-J collectors from
`src/__tests__/helpers/accountingInvariants.ts`. That helper imports `db` from
`config/database`, so the diagnostic reached the migration ledger transitively and advanced the
live database from `user_version` 103 to 107. A report-only script changed the ledger it was
reporting on.

### What the four accidental migrations did

| Migration | Effect |
|---|---|
| `add-missing-guarded-permissions.sql` | 15 permission rows + 15 role grants, Admin only |
| `add-production-overhead-payable.sql` | account `2200` Production Overhead Payable |
| `fn.verifyProductionOverheadPayableAccount` | verification of the above |
| `add-production-outputs.sql` | `production_outputs` table + 2 indexes |

All four are additive and inert with respect to accounting data: no journal entry, no journal
line, and no stock movement was written. Live verification after the fix reports
`user_version=107`, `integrity_check=ok`, 107 migration rows and 218 journal entries, unchanged.
The migrations are **not** reverted — reversing applied schema is out of scope and prohibited.

### Fix

The boot sequence (checksum verification, all 107 `runLedgered` calls, the account-4150 guard,
the journal-balance assertion, the admin seed and rollback handling) moved into an exported
`applyPendingMigrations()`. Importing the module now opens a connection and nothing else; the
schema write is opt-in and explicit.

Call sites that legitimately need the migrated schema call it before touching any table:

- `server.ts` — before the `app` import, because `app.ts` builds the route tree against it.
- `src/__tests__/setup.ts` — before the `dbSeedReady` gate, per test file.
- `scripts/repair-orphaned-ledger.ts`, `scripts/repair-stock.ts` — operator tools that write.

Read-only callers were deliberately left unmigrated, which is the point of the fix:
`verify-invariants-live.ts` and `verify-reversal-rules.ts` now report against the ledger without
being able to alter it.

### Latent defect found while fixing it

`migrationReplay.test.ts` asserted a clean double boot, but its first "boot" reused the module
instance `setup.ts` had already imported — pointing at setup's temp database, not the temp
directory the test itself created. Only the second boot, taken after `jest.resetModules()`,
actually opened the directory under test. The assertion passed for the wrong reason. Both boots
are now explicit and both run against the directory the test creates.

### Tests

`src/__tests__/databaseInitialization.test.ts` pins the boundary: importing applies nothing,
`applyPendingMigrations()` applies the full set, a second call adds no ledger rows, a tampered
checksum aborts the boot, and the invariant collectors import cleanly against an unmigrated
database. Written red first — importing created `schema_migrations` with 0 expected.

Full server suite: `Test Suites: 141 passed, 141 total`; `Tests: 1278 passed, 1278 total`;
`Time: 618.845 s`. Typecheck and lint clean.

### Also fixed

`.gitignore` ignored `*.bak` but not `*.bak-shm` / `*.bak-wal`, so `database/erp.db.bak-shm` and
`database/erp.db.bak-wal` were visible to git. Both patterns added.

## ACCT-F-CREDIT-OFFSET — correction to the earlier F finding (2026-10-15)

The previous commit (`c4b970b8`) recorded invariant F as an **open production defect that
reproduces on every new credit offset**, on the grounds that no current code writes a
`customer_ledger` row with `transaction_type='CREDIT_OFFSET'`. **That conclusion was wrong
and is withdrawn.**

### What the investigation found

Two callers post a GL credit offset, and they differ on purpose:

- `PaymentRecordingService` posts GL only for `CREDIT_APPLICATION`, with no ledger row,
  because the originating return already wrote a `RETURN` credit row.
- `InvoiceCreationService` writes a `CREDIT` ledger row only for the portion drawn from
  the `customers.credit_balance` pool. Credit held as a negative `current_balance` on the
  ledger is extinguished by the new invoice's own `INVOICE` row, which is correct.

A grep finding "no writer exists" was the wrong inference: the sub-ledger event is named
`CREDIT`, not `CREDIT_OFFSET`, and is conditional on the credit's source.

### Why no code change was made

The fix originally proposed — write a `CREDIT_OFFSET` ledger row on every offset — would
have credited each invoice settled by ledger credit a second time and corrupted customer
balances. It was not implemented.

`server/src/__tests__/creditOffsetSubledger.test.ts` now pins the real behaviour for both
credit sources, asserting financial values and ledger events rather than HTTP status:
exactly one economic credit event per credit, correct invoice settlement, and no cash
movement on a credit-offset group.

### Historical remainder

The live database still holds five GL credit-offset groups (total 5350) against 1800 of
sub-ledger representation, and F still reports 1800. `CREDIT_OFFSET` survives only as two
historical rows (customer 15, invoices 50 and 51) whose writer no longer exists.

An append-only reversal of those two rows was prototyped on an isolated copy and
reported as **rejected on the numbers**: F moved from +1800 to −3600 and customer 15
ended at a +5400 receivable. **That report was wrong — the prototype was buggy.** See the
D2b section below for the corrected implementation and result.

**Status: OPEN — historical-data reconciliation.** Not marked GREEN; live reconciliation
has not passed. Tracked as D2/D2b in `audit/ACCOUNTING-REMEDIATION-PLAN.md`. No live
financial data was modified; the live digest is unchanged at
`01359308f37ed33fb506cc42a829c170`.

## D2b — historical customer credit reconciliation, investigation complete (2026-10-15)

**Update 2026-10-15:** the invoice-49 sub-question that held the Strategy C′ correction on
hold (whether the second Rs 600 return was genuine) is now resolved — **both returns are
genuine**; the divergence is missing *physical* stock and one spurious GL leg, not a duplicate
return. See `audit/FINDING-invoice-49-return-reconciliation.md`. The correction itself remains
**not applied and not authorised**; the historical repair stays deferred by decision.

Investigation and simulation only. **No live data modified** — digest
`01359308f37ed33fb506cc42a829c170` and mtime unchanged, 10 existing backups intact.
All work ran against isolated copies created with the SQLite backup API
(`integrity_check=ok`, `user_version=107`, logical checksums identical to live across
customers / invoices / payments / payment_allocations / customer_ledger / journal_entries /
journal_lines).

### Scope correction

The previous entry above proposed reversing ledger rows #104/#108 and reported that doing
so moved F to −3600 and customer 15 to +5400. **That result was a bug in the prototype,
not a property of the correction.** The script voided the original rows *and* left the
newly inserted `REVERSAL:CREDIT_OFFSET` rows countable, while invariant F's own filter
(`voided = 0 AND reversed_by IS NULL`) excludes them. The 5400 was a double count. The
correctly-implemented reversal is simulated below.

### Invariant F, exactly as implemented

```
glBalance   = |GL_BALANCE(1100) + GL_BALANCE(1110)|        // Σ(debit−credit), voided = 0
custBalance = |Σ customers.current_balance − Σ customers.credit_balance|
```

Two different Rs 3,550 figures exist and neither is F's Rs 1,800:

- GL 1110 `Dr` total = **5,350**; `customer_ledger` `CREDIT_OFFSET` `Cr` total = **1,800**;
  difference **3,550**. This compares GL credit-offset postings against subledger
  credit-offset rows. It is **not** F.
- F's own 1,800 = glBalance 3,499.80 − custBalance 1,699.80. The two differ because GL
  1100 is −1,850.20 (credit-normal) and F adds the accounts before taking the absolute
  value.

### Proven root cause — invoices 50 and 51 were settled twice

Timeline reconstructed from `payment_allocations`, `payments`, `invoice_returns` and
`customer_ledger`, not from headers:

| Invoice | Total | Date | Cash settled | Credit offset | Verdict |
|---|---:|---|---:|---:|---|
| 50 `INV-0926-00008` | 1,200 | 2026-09-17 | 600 | 600 | correct **then** |
| 50 | | 2026-10-10 | +600 (`PAY-1026-00061`) | | **double-settled +600** |
| 51 `INV-0926-00009` | 1,800 | 2026-09-17 | 600 | 1,200 | correct **then** |
| 51 | | 2026-10-10 | +1,200 (`PAY-1026-00060`) | | **double-settled +1,200** |

On 2026-09-17 both invoices were settled exactly once: invoice 50 = 600 cash + 600 credit,
invoice 51 = 600 cash + 1,200 credit. Both credit offsets were backed by real return
credits (ledger #102 and #106, `RETURN Cr 600` each on `INV-0926-00007`) — legitimate when
written. Later cash payments on 2026-10-10 then settled the same invoices again in full
(allocations now total 1,200 and 1,800 respectively), making the original credit offsets
redundant.

Invoice headers corroborate: 50 and 51 both record `credit_offset = 0`, `paid_amount` =
full total, `balance_amount = 0`. The headers say "settled by cash alone" while the GL
and subledger carry a credit offset for each. The headers are right and the postings are
the orphan.

### Root-cause classification

| Discrepancy | Classification | Provable cause | Reproducible by current code? |
|---|---|---|---|
| F = 1,800 | Accounting error (duplicate settlement) | Invoices 50/51 credited twice; later cash payments superseded earlier credit offsets | No — no allocation-capacity guard in the historical data |
| GL 1110 vs subledger 3,550 | Two different comparisons | GL 5,350 across 5 invoices vs subledger 1,800 across 2; the other 3 (52/54/59) legitimately have no ledger row | No |
| `current_balance` 0 vs `SUM(invoice.balance)` −1,200 | Denormalised-header divergence, **separate axis** | Subledger is internally consistent (`current_balance == ledger net` for all 5 customers); invoice headers disagree with it | Pre-existing; untouched by any option |

Current production code does **not** reproduce any of this: the offsets were valid when
posted and were invalidated by later data, not by a logic fault.

### Simulations (isolated copies, all `integrity_check=ok`, no unbalanced entries)

| Option | Records changed | F before | F after | Other invariants | Accounting valid? |
|---|---|---:|---:|---|---|
| A — reverse #104/#108 **and** void the matching GL `CREDIT_OFFSET` groups for inv 50/51 | 2 ledger + 2 reversal rows + 4 journal lines | +1,800 | **0** | A, D, E, J pass; B/C, G, H, I unchanged | **Yes** — removes the duplicate settlement on both ledgers together |
| B — void only the GL groups | 4 journal lines | +1,800 | +1,800 | unchanged | No — leaves the subledger orphaned |
| C — A + restate inv 50/51 headers | as A + 2 invoice rows | +1,800 | 0 | unchanged | Pointless — headers already correct |

GL total is unchanged by option A (3,499.80) because voiding a credit offset removes
`Dr 1110` and `Cr 1100` together; the correction moves the subledger side only. Other
customers are byte-identical across all options (checksum `ce54cd497fca68de`).

**Rollback verified**: restoring `voided = 0` on rows #104/#108, deleting the two
`REVERSAL:CREDIT_OFFSET` rows and unvoiding the journal lines returns F to +1,800 and
customer 15 to 0 exactly.

### Caveat — F green is necessary, not sufficient

Option A leaves customer 15 `current_balance = 1,800` while `SUM(invoice.balance_amount)`
= −1,200, a 3,000 divergence. That is the *second* axis above and is **not** repaired by
any option. Customer 14 shows the same pattern (600.20 divergence) and is untouched by
this correction entirely. A full reconciliation of customer 15 and 14 against their
invoice headers is a larger exercise than D2b and is not started.

### Status

**OPEN.** Option A is proven on the numbers and is recommended, but it has **not** been
applied — no live correction has been made or is authorised. Awaiting explicit approval.


---

## D2b final verification and correction readiness (2026-10-16)

Investigation only. **No live modification.** Live SHA-256 `63e61c6a…` unchanged before
and after; `integrity_check=ok`; `user_version=107`. Full write-up in
`audit/D2B-INVOICE-49-INVESTIGATION.md`.

### Invoice 49 — confirmed historical defects

Both Rs 600 returns are **genuine**. The earlier open question ("is the second return
spurious, making the correction Rs 2,400?") is **withdrawn — the correction stays Rs 1,800**.

| Defect | Evidence | Status |
|---|---|---|
| `je#198` spurious inventory leg, Dr 1200 / Cr 7100 = **500** (standard cost) duplicating `je#200`'s FIFO 100 | per-account journal lines; `mv#197.unit_cost=100` vs `financial_value=500` | Historical; **fixable, evidence-complete, not applied** |
| Return 2 created no `stock_movements` row | no movement carries `reference_docno='INV-0926-00007'` besides `#197` | Historical; **guard defect, forward-only fix** |
| Return 1 restocked with `batch_id=null` | `#197` | Historical; attribution only |

Corrected GL arithmetic (verified independently): `−300 (je196) + 500 (je198) + 100 (je200) +
100 (je206) = **+400**`; correct is **−100**. Voiding `je#198` alone lands exactly on −100.
**No third Rs 100 posting is proposed** — `je#200` and `je#206` already carry both units.

Corroborated by `server/docs/known-issues.md` item 1, which names the same defect class and the
forward-only fix (`skipAdjustmentFinancialPosting`).

**Batch-51 correction.** `pi`'s finding (§4.1, §4.4) states the repair target is
`quantity_remaining 0 → 2`. That `0` is the *clamped* stored value; the true balance is
`10 − 12 = −2`, so crediting both units gives **0**. Setting 2 would push
`SUM(batch.quantity_remaining)` to 21 against `items.current_stock`/`stock_balances` at 19 and
**break Invariant E**. Corrected in place in that document. Item-level target is **19 → 20**,
not 21 — only one restock movement is missing at item level.

### Physical inventory — Scenario C, receipt cannot be established

`physical_counts` and `physical_count_items` hold **zero rows** — no stock count has ever been
run. No damaged/disposal/write-off record exists for item 1 (the only `WRITE_OFF`, `mv#180`, is
expired batch 49). Per the standing instruction, a missing movement is not proof of
non-receipt and a financial return is not proof of receipt. **Recorded as unresolved; requires a
business decision or a physical count.** The existing decision to defer historical inventory
repair is **preserved**.

### October cash — disposition

| Transaction | Received | Valid | Invalid | Treatment |
|---|---:|---:|---:|---|
| `PAY-1026-00060` | 1,400 | 200 → inv 57 | **1,200 → inv 51** | genuine receipt |
| `PAY-1026-00061` | 600 | — | **600 → inv 50** | genuine receipt |

The Rs 1,800 was genuinely received and its cash debit stands. Its allocations to invoices
50/51 were **invalid** (both settled 2026-09-17). The spurious credit was consumed by invoice
59's `credit_offset=1800`. **Customer intent is not provable from accounting records** — the
offset is a posting, not an instruction. Invoice 59's header is internally inconsistent
(`status='Unpaid'`, `payment_status='Paid'`, `balance=0`).

### Strategy C′ — Case 1 vs Case 2

| Case | Inv 59 balance | Cust 15 receivable | GL reconciled | Evidence |
|---|---:|---:|---|---|
| 1 — October cash applied to inv 59 | 0 | 0 | **No, F stays 1,800** | No — allocations provably invalid |
| 2 — cash unapplied (C′) | 1,800 | 1,800 | **Yes, F → 0** | Yes |

**Case 1 does not repair F**, measured: re-pointing the allocations changes neither GL nor the
sub-ledger, so `GL_AR − Σ customer balances` is unchanged at 1,800. The gap originates in the
**September CREDIT_OFFSET** mechanism, not the October allocation error. Case 2 is preferred on
evidence, **not** because it makes F pass.

**Product gap:** MiniERP has no unapplied-cash concept, so Case 2 must be represented as an
outstanding invoice balance rather than a customer credit. Recorded as a separate requirement.

**Assumptions carried by C′:** invoices 50/51 were settled before the October cash; the
September return credits were validly earned and consumed; customer 15 is a single legal entity
for balance purposes. All three are unverified assumptions, not findings.

### Correction-script safety — `c1d0c120` had none

`apply-customer15-correction.ts` and `rollback-customer15-correction.ts` shipped with **no
safety surface**: both resolve their database through `config/database`, which falls back to
the live `server/database/erp.db`. Neither had an authorization gate, identity check,
precondition validation, or idempotency guard.

Fixed in **`92d89486`**: `scripts/lib/correctionSafety.ts` adds four fail-closed gates
(exact authorization token, explicit `DATABASE_PATH`, live exclusion bound to a measured
SHA-256, `--apply` flag) plus ten preconditions that also make a repeat run a no-op. The
accounting logic of both scripts is **unchanged**.

Verified on isolated copies: 7 refusal paths, authorized happy path, idempotency refusal, and
exact logical rollback of all 7 financial tables (`activity_log` append-only by design).
**Note:** `eslint` does not cover `scripts/`, so these files rest on typecheck + behavioural
tests only.

### Status

**F and H remain OPEN.** Neither is marked resolved; every result above is from isolated
simulation. No live correction is authorised. Three decisions are outstanding and are
**deliberately not bundled**: physical disposition of invoice 49's second unit; allocation or
retention of the October Rs 1,800; and approval of any specific historical correction.

---

## Money-path review — 2026-11-15 (read-only)

Three read-only subagents reviewed the money and stock paths that changed since the
audit began: refund claims, the cash guard, the idempotency middleware, and
sales-order→invoice conversion. This section records what they found and how each
claim was checked. **No fix is applied for any item below** — the owner decides.
Regression proofs that can be written now live in
`server/src/__tests__/moneyPathReviewGaps.test.ts` (1 red, 2 green).

### M1 — settle-return idempotency claim is outside the transaction (HIGH) — FIXED

**File.** `server/src/controllers/invoiceReturnController.ts`, `settleReturn`.

**Finding.** `claimIdempotencyKey(...)` ran **after**
`InvoiceReturnService.settleReturn(...)` had already committed its own
`db.transaction`. A crash between the commit and the claim left no key row.
A retry with the same key could settle again and pay twice.

**Fix (`db6fbce2`).** The service call and the claim now sit in **one**
`db.transaction(() => { ... })()`, so both commit or both roll back.
better-sqlite3 nests the service's inner transaction as a savepoint.
Same shape as `expenseController`'s `EXPENSE_CREATE` claim.

**Verified.** `moneyPathReviewGaps.test.ts` asserts the claim is **inside** the
transaction body (`txnBody` contains `claimIdempotencyKey` **and**
`settleReturn(`), and that the service call does **not** sit before the
transaction (`beforeTxn` does not contain `InvoiceReturnService.settleReturn(`).
The test failed before the fix and passes after it.

### M2 — salary and loan outflows never check the cash timeline (MED) — FIXED

**File.** `server/src/services/accountingService.ts`, `postSalaryEntry`,
`postLoanDisbursement`.

**Finding.** Both called only `assertSufficientFunds` (a point-in-time check).
Neither called `assertCashTimeline` (the running-balance check). Every other
cash-outflow path calls both.

**Fix (`db6fbce2`).** Both methods now call a new private static
`AccountingService.assertCashTimelineAfterOutflow(db, paymentMethod, fromDate)`
after posting, which lazy-`require`s `cashBalanceGuard` (the two modules import
each other, so a top-level import would be circular). The caller's transaction
rolls back when the guard throws. Pattern copied from `SupplierPaymentService`
(ACCT-013).

**Red proof.** `moneyPathReviewGaps.test.ts` GAP-2: JazzCash (1030) is funded
30,000 on 2026-09-20; a 25,000 loan is dated 09-25 and posts; a 28,000 loan is
**backdated** to 09-22 and posts, because its own date shows 30,000. Cash on
09-25 would then be **−23,000**. Removing the guard makes the test fail with
the 09-25 balance at −23,000; restoring it makes the backdated loan refused with
`Insufficient funds in Cash on 2026-09-25: balance would be -23000.00. Reverse
the later spending first.` This is a **real red proof**, not a pin.

**Correction to the earlier note.** `assertSufficientFunds` uses
`getAccountBalance`, which **is** cumulative (`SUM(debit-credit)` for
`line_date <= asOfDate`). The `available 0.00` observation was a probe artifact
from a malformed payload that tripped a different check. The real defect is the
**missing timeline check**, not a broken balance read.

### M3 — supplier refund-claim write-off has no GL-level idempotency (MED) — FIXED

**File.** `server/src/models/SupplierRefundClaim.ts`, `writeOff`.

**Finding.** No `assertNoActivePosting` guard. Two attempts could both post
`Dr 7300 / Cr AP`, overstating 7300. `recomputeStatus` is not a latch.

**Fix (`8e0d9b61`).** `writeOff` now calls
`AccountingService.assertNoActivePosting(db, 'REFUND_CLAIM_WRITE_OFF', id)`
before posting. The guard scopes to `voided = 0`, so a reversal (void + re-post)
still works — the test proves both halves.

**A UNIQUE index on `journal_lines(reference_type, reference_id)` was NOT added,
and must not be.** One invoice legitimately posts revenue, tax and COGS as three
active lines with the same `reference_id`
(`accountingService.ts` single-INVOICE postings), so that index would break
invoicing. M3 is fixed at the claim-status layer, not the GL layer.

**Verified.** `supplierRefundClaims.test.ts`: the claim balance is reset so the
**only** rule that can refuse a second write-off is the GL guard. With the guard
present the second call throws; with it removed the call does not throw (red
proven).

**Coverage limit, stated in the test.** A true interleaved double-post is **not
reachable on this stack**. better-sqlite3 is synchronous and SQLite permits one
writer, so a second writer gets `SQLITE_BUSY` rather than a duplicate posting.
Two connections cannot be used in the test either: the suite's fixture data sits
inside an uncommitted `SAVEPOINT`, which a second connection cannot read. The
test therefore proves the guard **contract**, not a reproduced race.

### M4 — sales-order→invoice conversion: negative stock risk untested (MED) — TESTED

**File.** `server/src/models/SalesOrder.ts` (conversion), `salesController.ts`.

**Finding.** The conversion can attempt to consume more than is on hand, and no
test covered a double-fire of the conversion.

**Fix (`706c21c0`).** No production change was needed. The controller and the
model both refuse a conversion when the order is already `Invoiced`/`Completed`,
inside the transaction that flips the status. A double-fire test now covers it:
two conversions of one order — exactly one returns 201, exactly one invoice
exists, and stock falls by exactly the ordered quantity.

**Red proof.** Removing both status guards makes **both** conversions return
201 (two invoices, double deduction); the test fails. Restoring them passes.

### M5 — turning `feature_batch_locations` on breaks sales (latent, MED) — FIXED

See `docs/bugs.md` **BUG-013**. With the flag on, `sellableAvailabilityByWarehouseSql`
read `batch_stock_by_location` instead of `stock_batches`, and nothing backfilled
that table for batches created while the flag was off. The full suite went from
**272/272 green** to **38 suites / 122 tests failing**. The shipped default is
off, so it was latent.

**Fixed 2026-11-16 (head `f4088c6f`).** Six write sites no longer gate on the
flag; the flag-on sellable query reads covered AND uncovered batches and its
residual deduction is per unit and unfiltered; migration
`127_backfill_batch_stock_by_location.sql` backfills existing databases; a
structural guard fails any future write placed behind the flag; and a legacy
database upgrades through the migration and then sells, returns, transfers and
voids with invariants A–J holding and zero per-bin drift. Full suite green in
both flag states: **282/282 suites, 2261/2261 tests**.

**Still open.** The flag default stays OFF. Task 8.6 (drop the old columns) is
not met — five read sites still use `stock_batches.warehouse_id` or
`stock_balances.quantity`. Drift is verified on the rehearsal fixture, not yet on
the live databases. See `audit/DECISIONS.md` D25 and `docs/bugs.md` BUG-013.

**Why the dev DB worked with the flag on.** Two different databases, neither
exercising the defect. The live `database/erp.db` had **0** stock batches (so
nothing to lose). The archived stale DB's 5 batches were bought while the flag
was **already on**, so each got a location row at purchase time. The defect needs
batches created while the flag was **off**, then a flip to **on** — the exact
situation of every existing install at migration time.

- **Warn-UI follow-up complete on `glm/warning-ui` (2026-11-17).** Branch
  off frozen `0186b8d9`; commits `9cef8928` (POS sale warnings on the
  receipt dialog), `d29b01c7` (invoice-create warnings before the form
  closes), `6b4e9b5a` (doc-only: correct the false "void route mandates an
  Idempotency-Key" claim — server truth verified: void performs no
  idempotency handling; write-off DOES 400 without the key, that doc left
  as-is). Both paths red-first with clean revert-proofs (POS: warnui-*.log;
  invoice: warnui-invoice-*.log in /home/fawad/logs/ux-evidence/); combined
  regression 88/88; analyze + l10n drift exit 0. Client accepts `warnings`
  at envelope top OR inside data — no new API field; strings verbatim.
  Targeted tests only; full gate NOT requested yet. **PI coordination
  status: server field placement now confirmed by PI's diff
  (`0fc5d41a`): POS sends envelope-top `warnings` (posController.ts:349);
  invoice route unchanged (ACCT-006 merge). Both match the client.**
- **Cross-review of PI's stock fix `0fc5d41a`: 5 findings + 1 minor, ALL
  UNCONFIRMED until run (2026-11-17).** Read-only review
  (`/home/fawad/logs/glm-cross-review-r1r2r4.md`): F1/F2 — DAMAGED warning
  keyed on the candidate bin list, not actual takes (false-positive
  warnings, both flag states); F3 — R2 under-coverage warning masked by
  non-sellable bins' availability (silent bin-write shortfall); F4 —
  pre-receipt fallback returns `warnings: []` (damaged sells silently on
  that path — needs an explicit decision if intended); F5 — idempotent POS
  replay drops the original sale's warnings; F6 minor — duplicate per-batch
  warnings. Verified correct: reserved/blocked double-subtraction disjoint,
  warehouse attribution (stock_batches warehouse-scoped), available caps,
  transaction rollback (service-wide db.transaction; shortage throws roll
  back), warning carrier on the live path. **Independent reviews NOT
  finished** (PI has not reviewed GLM's UX diffs yet; findings not run);
  PI's full-gate request pending — F1-F4 should be resolved or consciously
  accepted first.

- **Invoice warning wire-contract proof added (`52447ccc`, 2026-11-17).**
  Closes the coordinator-identified gap: the fake-repo tests prove display;
  this test drives the REAL InvoiceRepository over a Dio adapter serving the
  exact 201 shape invoiceController.ts sends, asserting POST method/path,
  Idempotency-Key header, body (customer_id, item_id, quantity) and the
  warning rendered through the real Invoice.fromJson — plus the save-and-
  print path (only the `net.nfet.printing` channel mocked: layoutPdf awaits
  a native-only job callback). Honest chronology: the display fix went
  red-first on the fake-repo harness; this wire test passes first-run by
  design (honest green guard) and its sensitivity is PROVEN — with the
  model parse neutralized, both wire tests fail 0/2
  (warnui-invoice-wire-sensitivity-raw.log). Regression 80/80; analyze
  exit 0. Cross-review findings F1-F6 remain UNCONFIRMED until PI's tests
  run (unchanged).

- **Migration 128 proposal: CONDITIONALLY ACCEPTED for implementation
  validation — NOT SHIPPED, do not incorporate (2026-11-17).** GLM's
  read-only architecture review (msg_92190dda7c9b; findings:
  `/home/fawad/logs/glm-cross-review-migration128.md`) returned
  **approve-with-evidence** on the DESIGN only: 10 items verified in source
  (ledgered registration after 127, safe JSON parse, legacy NULL → [],
  request-hash identity before replay, claim-with-warnings inside the create
  transaction, replay reads only the invoice row — no stock re-consume or
  duplicate cash, all 10 claim callers compile, POS covered at envelope top,
  payload adequate, no simpler storage exists). Gull accepted the nullable-
  column design **conditionally** (msg_73d2d3087643): acceptance is for
  implementation validation, NOT shipping. PI was asked to provide, before
  commit: pre-128 upgrade/replay/atomicity controls and a MIGRATION-SPECIFIC
  partial-apply recovery proof; no broad migration-runner refactor. The false
  "Idempotent" comment in the migration file MUST be corrected, but a comment
  alone is not recovery evidence. **F-A (crash window between the ALTER commit
  and the ledger-row insert) is recorded as a HYPOTHESIS, not a confirmed
  inherited/pre-existing behavior** — the source reading is consistent with a
  shared window across file migrations 121–127, but without a clean-baseline
  targeted test the "inherited" label is unproven; PI's targeted test must
  confirm or refute it. F-B (ON CONFLICT warnings downgrade guard) and F-C
  (clean two-commit split: migration/replay commit vs stock-precision commit,
  verified feasible both orders) stand as proposed. All findings UNCONFIRMED
  until run (no tests were run — gate discipline). The patch remains
  uncommitted in PI's worktree and must NOT be merged into any GLM branch.
  PI's production result is NOT done; PI prepares tests now and executes them
  AFTER the gate slot is released. The 11
  audit/accounting-audit/remediation renders regenerate during gate runs and
  are restored after — never committed.
- **Flutter full-gate plan for the warning path (prepared, NOT requested —
  slot unassigned, 2026-11-17).** Candidate: `glm/warning-ui` at exact
  `52447ccc` (history: base `0186b8d9` + `9cef8928` POS warnings +
  `d29b01c7` invoice warnings + `6b4e9b5a` doc-only + `52447ccc` wire
  proof; tree clean — Flutter, l10n and test files only; server files
  untouched. `0186b8d9`'s only server-lineage diff vs `42c1b469` was
  the flutter test file, so the bounded-combined evidence stands: server
  284/284 suites 2273/2273 @ `42c1b469`, no duplicate server rerun for an
  unchanged server tree). Plan: exclusive slot; clean ext4 detached
  worktree `glm-gate-52447ccc`; `bash scripts/check.sh --flutter` once
  (no standalone duplicate flutter run); literal log
  `/home/fawad/logs/gate-52447ccc/check-flutter-raw.log`; SHA + status
  before/after recorded (artifacts: the 11 `audit/accounting-audit/
  remediation/` renders regenerate during the run and are restored AFTER —
  documented, not claimed clean-throughout); release the slot only after
  the process exits; keep the workspace for independent reruns; report
  exact exit/counts. NOT executed — awaiting Gull's assignment once the
  cross-review and migration-128 question settle.

- **Flutter full gate PASSED for the warning path at exact `52447ccc`
  (2026-11-17 09:02 +05:00).** Exclusive slot, clean ext4 detached worktree
  `glm-gate-52447ccc`, `bash scripts/check.sh --flutter` ONCE: **exit 0,
  "all checks passed"**, flutter suite 1219 passed / 1 skipped (~1, the known
  parked skip) / 0 failed, flutter RED-BY-DESIGN files=0 (server-side
  `it.failing=1` is the parked F-3 tag, unchanged — server NOT rerun;
  server evidence stands at 284/284 suites, 2273/2273 @ `42c1b469`).
  Duration 08:45:30 → 09:02:32. The 11 regenerated
  `audit/accounting-audit/remediation/` render artifacts were restored after
  the run (documented; never claimed clean-throughout, never committed) —
  both gate worktrees verified 0 dirty paths afterwards. Slot released.
  Gate workspace retained for independent rerun.

- **PR4 branch updated on the remote under Gull's explicit approval
  (2026-11-17).** Guarded push executed verbatim as approved
  (msg_3ae96e056674): `git push
  --force-with-lease=refs/heads/glm/ux-review-tests:2e4a101a...` origin
  `0186b8d9:refs/heads/glm/ux-review-tests` — exit 0, forced update
  `2e4a101a → 0186b8d9`, lease matched the live remote at push time
  (preflight ls-remote confirmed both SHAs before executing). Remote head
  verified `0186b8d903cb182e6ed017d64ef2ca57f83af1a4`; PR #4 state OPEN,
  **isDraft: true** (kept draft). Remote CI triggered: runs 44017092273 and
  44017098422 — six checks (fallow ×2, flutter ×2, server ×2) PENDING at
  report time. Approval scope: remote branch update ONLY — no ready, no
  merge, no main push, candidate unaltered. No local suite rerun (PI holds
  the exclusive full server slot; remote CI checks are the verification
  path).

- **PR4 CI fallow push-job failure: corrected diagnosis (fetch/base-
  availability hypothesis) + fix proposal (2026-11-17).** Gull corrected
  GLM's initial reading (msg_57d7140b6fa5): non-ancestor/diverged history
  alone does NOT invalidate a git symmetric difference — the literal error
  (`Invalid symmetric difference expression 2e4a101a...HEAD. Verify the ref
  exists`, job 133817500194, push event, step "Dead-code / complexity /
  duplication gate") proves the runner could not RESOLVE the old head
  `2e4a101a` as an object: after the approved force-with-lease, the old tip
  is unreachable from every fetched ref, so checkout@v7 (fetch-depth 0)
  never downloads it. `ci.yml:67` selects `github.event.before` on push
  events — hence the failure; the sibling pull_request run passed because
  `pull_request.base.sha` resolves (API-verified events: run 44017092273 =
  push/fallow-FAIL/flutter-PASS; run 44017098422 = pull_request/fallow-PASS/
  flutter-in-progress; server PASS x2). Content NOT implicated (same tree
  passed fallow in the PR run). No workflow edit, no blind rerun, no local
  fallow baseline run. Minimal fix proposal with fixtures (force-push-
  missing-base, new-branch zero-SHA, normal-case regression, PR-path
  unchanged) prepared for Gull's decision:
  `/home/fawad/logs/fallow-ci-base-ref-fix-proposal.md`. Workflow file owner:
  Gull.

- **Warning draft PR #8 published under Gull's authorization (2026-11-17,
  msg_2a903977e3e6).** Frozen branch `glm/warning-ui` @ exact `52447ccc`
  pushed as a NORMAL new-branch push (remote branch did not exist; no force
  used — per directive, a non-FF conflict would have STOPPED the
  publication). DRAFT stacked PR created: **PR #8**
  https://github.com/mfbgull/minierp-flutter/pull/8 — head `52447ccc`
  (verified via API `headRefOid`), base `glm/ux-review-tests` (PR #4),
  `isDraft: true`, state OPEN, no ready/merge. Preflight: local SHA exact,
  tree clean (tracked+untracked=0), diff vs `0186b8d9` inspected = warning
  UI (5 lib files) + comment-only doc corrections (2 lib files) + tests
  (3 files), zero server files. PR body includes: PR #7 dependency for
  stock-warning semantics (display functions without it — ACCT-006's
  existing carrier already usable), the real-repository wire proof,
  chronology disclosures (red-first display fixes; green-guard wire test
  with mutation-proven sensitivity), per-SHA gates, and not-run items.
  CI on PR #8: 6 checks pending at publication time. **Bounded-combined
  evidence stands per-SHA, NOT on one SHA:** full Flutter gate at exact
  `52447ccc` (1219 pass/1 skip/0 failed, exit 0) + full server gate at
  exact `7416280e` (287 suites/2307 tests, exit 0, PI's gate verified by
  the coordinator's independent focused run: 3 suites/50 tests exit 0).
- **PR4 CI final: 5 PASS / 1 FAIL — the sole failure is the diagnosed
  fallow base-ref artifact (2026-11-17).** flutter PASS ×2 (push 6m47s job
  133817500567; PR 8m26s job 133817520686), server PASS ×2, fallow PR-event
  PASS; fallow PUSH-event FAIL (job 133817500194) on
  `Invalid symmetric difference expression 2e4a101a...HEAD` — the recorded
  fetch/base-availability hypothesis: `ci.yml:67` selects
  `github.event.before` on push events; after the approved force-with-lease
  the old tip is unreachable from any fetched ref, so checkout cannot
  resolve it. PR #4 is otherwise fully green on content. Minimal workflow
  fix proposal + fixtures await Gull's decision
  (`/home/fawad/logs/fallow-ci-base-ref-fix-proposal.md`); no workflow edit,
  no blind rerun. PR #8's push-event fallow may hit the same corner (new
  branch → `event.before` = zero SHA) — predicted by the recorded proposal
  fixture (b), to be confirmed from CI.
- **F3 owner-note correction recorded (Gull msg_3c3b25eee7b3); F3 remains
  OPEN — no product decision made.** PI's F3 note (msg_22a90e689fc8)
  incorrectly characterized the original behavior and the fix as a
  one-date+guard change. The coordinator verified at `741` (SupplierRefund
  code paths 372/387/401): the GL void is retroactive while the ledger
  reversal uses UTC today — the MIXED behavior is a bug. Owner options:
  (a) original receipt date **with period protection**, or (b) current date
  **with both stores preserving original history** — option (b) requires a
  counter-posting design, not merely changing the date and the void guard.
  Standing rule reaffirmed: historical as-of reporting must compare the
  DATED ledger, never `current_balance`. This entry corrects the note only;
  prior accepted decisions are untouched.

- **PR7 quality gate: OPEN — fallow complexity findings on `7416280e`
  (2026-11-17, Gull msg_7f9b07a53f34).** Both PR7 fallow jobs FAIL at exact
  `7416280e` (jobs 133827661652/133827684740): the gate reached a structural
  verdict — `✗ complexity: 4 findings · 6 changed files` — new-vs-base
  findings in `server/src/models/StockMovement.ts` (×3) and
  `server/src/services/InvoiceCreationService.ts` (×1). Routed to PI: exact
  CI investigation + **behavior-preserving refactor** (GLM cross-reviews the
  refactor diff read-only when it arrives; no stock edits by GLM).
  **CORRECTION ON RECORD (owner explicit rule):** renewing the local fallow
  baseline to absorb new findings is **FORBIDDEN**, as is lowering
  thresholds or allowlisting new findings — GLM's earlier suggestion to
  "renew the baseline" is retracted and must not be repeated. A changed-base
  audit matching CI is allowed for DIAGNOSIS only, never to produce a new
  baseline.
- **Local verification limitation on the earlier focused run (disclosed).**
  The coordinator's independent focused run at `7416280e`
  (batchLocationWarningPrecision + idempotencyResponseWarningsUpgrade +
  accounting invariants — 3 suites / 50 tests, exit 0) and PI's full server
  gate (287 suites / 2307 tests, exit 0) remain valid as TEST evidence, but
  that worktree ran a **zero-changes** fallow audit (no diff vs its own
  HEAD), so it did NOT prove the PR's structural gate — which is exactly the
  check CI's changed-base audit performs and which PR7 currently FAILS.
  PR7 therefore remains quality-gate OPEN until PI's refactor lands and CI
  passes.

- **Correction to GLM's msg_6f9d11aff091 (Gull msg_edf9609a4c3f).** The
  clause "PR4/PR7 PR-runs passed their fallow" was FALSE for PR7: **both** of
  PR7's fallow jobs failed on CONTENT (the 4 complexity findings). Only
  PR4's PR-event fallow passed; PR7's passed none. The clause is retracted
  and must not be used to predict PR8's PR-event fallow outcome. PR8's
  content verdict is pending; it will be reported when it finishes, without
  plausibility guesses.

- **Attribution correction: the 4 PR7 fallow findings are ALL
  StockMovement.ts functions — GLM's "InvoiceCreationService ×1" retracted
  (Gull msg_c6e3756d02d3).** Literal CI log (job 133827661652):
  consumeFromOldestBatches (cyclomatic 22 / cognitive 22),
  consumeLegacyBatches (cognitive 21), preReceiptFallback (cognitive 21),
  consumeBatchesByLocation (cognitive 16). The earlier ×1 attribution was
  inferred from the changed-files list, not the finding list. Kept separate
  from the PR4/PR8 push-event base-ref failures (infra class).
- **GLM read-only review of PI's refactor `e400f4cc` (parent `7416280e`,
  StockMovement.ts only, 265+/201−): APPROVE-WITH-LIMITS** — full findings:
  `/home/fawad/logs/glm-refactor-review-e400f4cc.md`. Verified equivalent at
  the exact SHAs: clamp ON (legacy/fallback MAX(0)) vs OFF (flag-on plain
  subtraction) preserved per path; the removed `quantity_reserved`
  self-assign is value-identical (trigger `AFTER UPDATE OF
  quantity_physical, quantity_reserved` still fires — `quantity_physical` is
  listed — and recomputes available from NEW values); `selectBatchBins`,
  `throwShortfall`/`assertAvailable`, `warnMirrorShortfall`,
  `mergeUncoveredBatches`, `consumeFlagOn`,
  `preReceiptFallbackWithLocations` all verbatim-equivalent; warning
  text/precision, cost/order, and rollback unchanged. LIMITS: source-reading
  only (no tests — PI's exclusive gate); the EXACT CI changed-base audit
  with fresh coverage on the refactor is the authority and has not landed —
  no final green claimed. Two proposed pinning tests recorded (trigger
  recomputation invariant; clamp-difference pin).

- **PR7 quality gate: changed-base proof OBTAINED at `e400f4cc` — remote CI
  pending (2026-11-17, Gull msg_ee0f1afaca90).** PI's full server gate:
  287 suites / 2307 tests, exit 0. The coordinator's independent clean-ext4
  rerun: 3 suites / 62 tests, 23.719s, exit 0, AND the **EXACT fallow
  3.34.1 `audit --base 7a96e6d8`: exit 0, "No issues", 9 changed files**,
  status clean — this REPLACES the earlier zero-changed limitation with
  actual independent changed-base proof, with NO baseline changes. Logs:
  `/home/fawad/logs/coordinator-e400f4cc-focused.log` +
  `coordinator-e400f4cc-fallow.log`. GLM's read-only review of the refactor
  (approve-with-limits) stands, not repeated. PI pushed `e400f4cc` to PR7
  (fast-forward, draft kept); remote CI runs 44026406745/44026414784
  **PENDING — not counted as green until they resolve** (no guessed green).
  PR7 leaves quality-gate OPEN status only when the remote changed-base
  audit confirms.

- **F3 status change: OPEN → DECIDED / implementation-pending (Gull
  msg_ca9008067d4f).** Decision recorded in DECISIONS.md: existing VOID =
  correction of an incorrect receipt entry; ORIGINAL RECEIPT DATE on both the
  GL and the supplier ledger; audit trail preserved; existing period lock
  respected — closed-period ordinary void BLOCKED. A later actual cash return
  is a separate reversal workflow, out of scope for this fix; controlled
  prior-period correction also separate. PI assigned: fresh branch,
  SupplierRefund.ts + F3 server regressions, real-HTTP red-first (as-of/date,
  closed-period guard, cash guard, A–J), revert-proof. GLM independently
  reviews PI's money diff read-only before any merge. Status stays
  implementation-pending — NOT FIXED until evidence lands.

- **Test ownership coordination: `server/src/__tests__/moneyPathFindingsRed.test.ts`.**
  The parked F-3 case (wrapped in `it.failing`, header documents the pending
  dating decision) lives on the GLM line (glm/ux-review-tests, glm/warning-ui,
  glm/ux-fixes). GLM owns this existing parked test; GLM will not edit it
  concurrently with PI's fresh-branch work. Proposed single-owner unpark: PI's
  branch owns the FIX + new regressions; once the fix is integrated, GLM
  unparks the F-3 case on the GLM line (removes the `it.failing` wrapper) as
  the one owner/branch — pending Gull's confirmation.

- **PR7 remote CI GREEN at exact `e400f4cc` — quality gate CLOSED
  (2026-11-17).** All 6 checks PASS on head `e400f4ccd755…` (verified via
  `gh pr view`: headRefOid = e400f4cc…, draft=OPEN, untouched): fallow PASS
  ×2 (3m59s job 133847689582 / 4m42s job 133847716288 — the remote
  changed-base audit confirms no findings, matching the independent local
  `fallow --base 7a96e6d8` proof), flutter PASS ×2 (8m26s/8m12s), server
  PASS ×2 (4m08s/4m59s). The earlier OPEN status (4 StockMovement complexity
  findings @ `7416280e`) is resolved by PI's refactor `e400f4cc` — GLM
  read-only review: approve-with-limits; independent changed-base proof:
  exit 0, no issues, 9 changed files. PR7 stays DRAFT; ready/merge remains
  Gull's call. PR4/PR7/PR8 tested candidates stay frozen per
  msg_ca9008067d4f.

- **F3 ownership CONFIRMED (Gull msg_065193806caa):** single-owner plan
  confirmed — PI owns SupplierRefund.ts + NEW F3 regressions; GLM alone owns
  moneyPathFindingsRed.test.ts on the GLM line. Unpark only on a branch
  containing the reviewed fixed commit through approved integration, with
  the regression observed passing; header comment updated accurately at the
  same edit; no concurrency. Ownership agreement sent to PI via the run.
  F3 stays DECIDED/implementation-pending; GLM will independently review
  PI's exact money diff when available.

- **F3 status: implemented / validation-pending — GLM independent review of
  PI's `859831aa` (parent main `7a96e6d8`): fix correct at source, test gap
  confirmed (2026-11-17, Gull msg_5b991349abb0).** Full review:
  `/home/fawad/logs/glm-f3-money-fix-review-859831aa.md`. [SOURCE] findings:
  the one-line fix (`transaction_date: refund.refund_date`) matches the
  decided rule and the codebase precedent
  (`ledgerUtils.reverseLedgerEntry` same-date reversal); receipt path
  already posts at `refundDate`, so both stores now cancel as a net-zero
  pair ON the receipt date; ledger stays append-only (INSERT +
  `rebuildBalances`, REVERSAL-RULES 1.6); period guard
  (`assertPeriodNotClosed` on receipt_date + CODE-001 internal guard)
  blocks closed-period void before any write; cash timeline guard
  unchanged and consistent; `voided_at` stays wall-clock (attribution
  metadata, not a money date). Coordinator's test gap VERIFIED PRECISE:
  the as-of test filters REFUND types only and compares GL only
  before-vs-2099 — it never asserts GL at the receipt date nor
  cross-store GL-vs-ledger agreement; proposed test-only matrix recorded
  (GL flat across before/atReceipt/now; whole-ledger unfiltered net
  identical across dates; GL-vs-ledger delta constant). F3 = implemented /
  validation-pending: NOT fully fixed until PI's refined tests pass the
  full server gate. Parked moneyPathFindingsRed.test.ts untouched (unpark
  only after approved integration, observed passing).

- **F3 batched update (2026-11-17, Gull msg_f49350c2f842): PI test
  refinement `7dc3deab` reviewed — approve-with-limits; ONE test-only date
  defect before the gate.** Full review:
  `/home/fawad/logs/glm-f3-test-refinement-review-7dc3deab.md`. [SOURCE]:
  test-only (SupplierRefund.ts diff EMPTY — approved source fix at
  `859831aa` unchanged). The refinement closes the earlier test gap:
  `glApScopedAsOf` scopes GL AP 2000 to the supplier's own document refs
  (PURCHASE/PAYMENT/PURCHASE_RETURN/REFUND_RECEIPT) and asserts
  `gl === ledgerNetAsOf` at every sampled as-of date against the WHOLE
  dated ledger net (unfiltered); exact 409 closed-period refusal (message
  + row-equality on journal_lines/supplier_ledger/status) and exact 400
  double-void (message + three stores row-equal); `.not.toBe` anti-vacuity
  baseline guard. DEFECT (coordinator's, verified at exact SHA):
  `INTERMEDIATE_DATE = '2026-03-12'` is BEFORE `RECEIPT_DATE = '2026-03-15'`
  — the loop's "between receipt and today" claim is false; no sample
  exists in (receipt, today). Receipt-date cancellation assertions still
  catch wrong-dating, but the claimed mid-window coverage does not exist.
  Fix: `INTERMEDIATE_DATE = '2026-03-20'` (test-only, one line, comment
  updated), then focused test → PI's exclusive full server gate +
  changed-base audit. F3 remains **implementation-pending-full-gate** —
  not fixed until that gate passes; no final green claimed. Parked GLM
  test untouched; frozen PR4/PR8 untouched.

- **F3 batched update (2026-11-17, Gull msg_2442fda9bf0d): final test
  refactor `dbfbe415` reviewed — APPROVE; date fix verified at `d1f5091b`;
  gate pending at `dbfbe415`.** Full review:
  `/home/fawad/logs/glm-f3-final-refactor-review-dbfbe415.md`. [SOURCE]:
  (a) source byte-identical across 859831aa/d1f5091b/dbfbe415 (SupplierRefund.ts
  blob 8b0ddf9d — approved fix untouched, no re-audit needed); (b) `d1f5091b`
  lands exactly the proposed one-line date fix (INTERMEDIATE_DATE 03-12 →
  03-20, corrected comment; sampled set now monotonic with a genuine
  mid-window point); (c) `dbfbe415` helper split is verbatim-equivalent
  (seed vs post decomposed, same sequence/constants/payloads/expects,
  same wrapper return shape; describe split moves only the two state-guard
  its, bodies untouched; file-level savepoint hooks unchanged; execution
  order preserved). Evidence ledger: PI-reported [TEST] focused 4/4 +
  changed-base audit no-issues (2 files, exit 0, fresh coverage) at
  dbfbe415; full server gate RUNNING at dbfbe415 (single run); prior full
  gate 284/2273 @ d1f5091b valid FOR THAT SHA only. F3 remains
  **implementation-pending-full-gate** until the dbfbe415 run resolves —
  no final green claimed, no baseline/threshold changes. Parked GLM test
  untouched; frozen PR4/PR8 untouched.

- **F3 batched update (2026-11-17, Gull msg_ef5a53431ebe): implementation
  LOCALLY VERIFIED / remote CI pending / NOT merged.** Evidence at exact
  `dbfbe415`: PI full server gate 284 suites / 2273 tests exit 0;
  changed-base fallow audit no issues (2 files, exit 0, fresh coverage);
  coordinator independent F3 + accountingInvariants rerun 2 suites /
  37 tests, 58.857s, exit 0, clean before/after
  (`/home/fawad/logs/coordinator-dbfbe415-focused.log`). GLM final review
  APPROVE stands (no duplicate). Draft **PR9** head verified exact
  `dbfbe415`; all 6 remote CI checks PENDING — monitored automatically.
  F3 is NOT merged; no final green claimed until PR9 CI resolves.

- **F3 unpark-before-merge sequencing rule + concrete integration plan
  (per Gull msg_ef5a53431ebe).** Rule: the existing GLM
  `moneyPathFindingsRed.test.ts` F-3 case (in `it.failing`) MUST be
  unparked on a fix-containing integration branch BEFORE the combined fix
  merges — jest fails a passing `it.failing`, so merging the fix while the
  case is still wrapped would break CI with an unexpected pass. Concrete
  plan (single owner per file, no silent candidate change):
  1. PR9 CI green at `dbfbe415` (pending; monitored automatically) →
     reported; ready/merge stays human-only.
  2. On Gull's explicit integration approval: create an integration branch
     containing BOTH the F3 fix (PR9 content) AND the GLM parked test
     (from the GLM line).
  3. GLM (sole owner of the file) removes the `it.failing` wrapper on that
     branch in the SAME edit that updates the header comment accurately
     (decision implemented at `859831aa`; case now a normal regression).
  4. Targeted run: the previously-parked case observed PASSING on the
     integration branch (no full-suite rerun without cause).
  5. Only then the combined merge proceeds, as sequenced by Gull.
  Frozen PR4/PR8 candidates stay untouched until explicitly sequenced; no
  silent cherry-picks/force pushes.

- **Slot + next assignment (Gull msg_ef5a53431ebe).** The exclusive full
  server slot is FREE (F3 gate complete). PI assigned S3 only, on a fresh
  branch from `e400f4cc`: reproduce then red-first
  purchase/receipt/production `stock_balance` extension — stock/server
  only. GLM cross-reviews the future S3 diff read-only when available.
  GLM runs no tests in PI's slots.

- **S-3 CONFIRMED SCOPE + flag-gated mirror-write correction (Gull
  msg_c67507eb7509).** PI reproduced S-3 on `e400f4cc` through REAL
  purchase/receipt/production routes: bin quantities present, the
  `stock_balances` extension NULL; the control `recordMovement` path
  passes. Gull independently read `syncStockBalancesExtension` and
  confirmed it returns flag OFF — the mirror write is FLAG-GATED, the
  confirmed defect class. PI routed: extend the red matrix to BOTH flag
  states BEFORE code; then unconditional SHARED mirror refresh after
  balance+bin creation at all three seams. Scope guards: no global
  invariant widening; no schema/backfill/default/migration-127 changes.
  Ownership: PI owns the model seams + StockMovement; GLM owns
  Flutter/docs and cross-reviews the eventual stock diff READ-ONLY.
  Status: **confirmed S-3 scope, fix NOT final until evidence** (red
  matrix both states + gate + changed-base audit).

- **PR9 remote CI final (2026-11-17): 5 PASS / 1 FAIL(artifact) at exact
  `dbfbe415`.** Content verdict: PR-event fallow PASS (3m46s, job
  133895665328) — changed-base audit clean. server PASS ×2, flutter PASS
  ×2. Push-event fallow FAIL 4m46s (job 133895588740): literal log
  "could not determine changed files for base ref '0000…': fatal:
  Invalid symmetric difference expression", exit 2 — the SAME zero-SHA
  base-ref INFRA artifact as PR4/PR8 push runs (new branch, `event.before`
  = all-zero), NOT a content verdict. With the locally verified gate
  (284/2273 exit 0 + independent 37-test rerun + changed-base clean),
  F3 stands at: implementation locally verified, remote content verdict
  clean, NOT merged — ready/merge remains human-only.

- **S-3 batched update (2026-11-17, Gull msg_f23d3ecacd98): GLM review of
  `360e1aa8` — APPROVE-WITH-LIMITS; reservation-only mirror gap CONFIRMED
  as a separate linked finding.** Full review:
  `/home/fawad/logs/glm-s3-review-360e1aa8.md`. [SOURCE] verified: all
  three ADD-path sync calls inside the same transaction AFTER balance+bin
  rows exist (Purchase writePurchaseRow:312 / PO:1123 / Production:547);
  warehouse scope correct (bins batch-scoped, l.warehouse_id filter, same
  warehouse as the writes); legacy/no-bin safe — the sync touches ONLY the
  extension columns, never legacy `quantity`; no-bin → 0/0/0 is
  semantically correct and read-inert (the only extension reader,
  StockMovement.ts:280, reads quantity_available only with flag ON; no
  COALESCE-fallback readers). Callers: recordMovement:879 call site STILL
  self-gated (net behavior unchanged; inconsistency with the in-function
  comment noted — protective for no-bin adjustments); PhysicalCount
  399/669 now ungated (flag-OFF behavior change, consistent+inert).
  LINKED FINDING (coordinator's, confirmed at source): StockReservation.ts
  (reserve :104 / release via negative delta) updates bin rows but has
  ZERO stock_balances references — mirror stale after every
  reservation/release; SEPARATE from S-1 consume-release, NOT fixed by
  360e1aa8; later ADD-path syncs repair staleness incidentally. Same
  family, pre-existing, out of scope: PurchaseOrder.ts:758 PO-cancel
  zeroing also does not sync. TEST FOLLOW-UP before the final gate
  (coordinator): replace the downgraded reserved=0 control with a
  meaningful existing-NONZERO-reservation THEN ADD case (reservation
  preserved), red/revert proof; code frozen at 360e1aa8. S-3 =
  implemented / validation-pending — final verdict waits on the corrected
  case + PI's exclusive full gate + changed-base audit. No global
  invariant widening, no schema/backfill/default/127 changes (verified in
  diff); focused-coverage CRAP warnings inconclusive until full
  same-worktree coverage; no baseline changes.

- **CORRECTION to the S-3 review (Gull msg_c7abb19bc488): the
  recordMovement caller gate is the SAME invariant, not a protective
  exemption.** Gull independently verified StockMovement.ts:877-880 still
  flag-gates the shared mirror refresh. Since the function is now
  ungated, the caller-level gate is REDUNDANT and enforces nothing but an
  inconsistency with the shared maintained-write rule ("the flag selects
  what is READ, never what is MAINTAINED"). It must NOT be described as
  protective for the no-bin case. Routed to PI (bounded, before the final
  gate): narrow OFF real-route regression first, THEN remove the
  redundant caller gate, alongside the meaningful
  existing-NONZERO-reservation THEN ADD case with red/revert proof. S-3
  stays validation-pending — no final approve until the bounded follow-up
  is tested.

- **Evidence-class relabeling (same message).** The tracker must
  distinguish SOURCE-confirmed missing calls from runtime-confirmed
  reproductions, and current-source observations must not carry
  "pre-existing" labels unless a clean known-good baseline proves them:
  - RUNTIME-CONFIRMED reproduction: S-3 itself — bins present, extension
    NULL via real purchase/receipt/production routes (PI, e400f4cc).
  - SOURCE-CONFIRMED missing calls (current source, runtime repro NOT
    required for the code fact): StockReservation reserve/release updates
    bins with zero stock_balances references; PurchaseOrder.ts:758
    PO-cancel zeroing does not sync; recordMovement:877-880 caller gate.
    All three remain UNRESOLVED gaps — none is fixed by 360e1aa8, and
    none is permission for wider production cleanup beyond the routed
    bounded follow-up.
  - No-bin extension sum=0: already reviewed safe (read-inert; legacy
    `quantity` stays authoritative with flag OFF).

- **Discipline standing:** no GLM tests during PI's future full gate; no
  stock edits; batched routine record updates.

- **S-3 batched update (2026-11-17, Gull msg_0bba910f3970): final follow-up
  `2692ab1e` reviewed — APPROVE; S-3 validation-pending on the running
  gate.** Full review:
  `/home/fawad/logs/glm-s3-final-followup-review-2692ab1e.md`. [SOURCE]:
  production change is EXACTLY the routed caller-gate removal
  (recordMovement ~877-880: `syncStockBalancesExtension` now unconditional,
  accurate comment) — consistent with the shared maintained-write
  invariant; no other production changes in the branch (4 model files + 1
  spec only; no services/migrations). New cases verified meaningful:
  (a) both-flag recordMovement parity (real-HTTP ADJUSTMENT, both states —
  the OFF regression justifying the gate removal); (b) the coordinator's
  existing-NONZERO-reservation THEN ADD case via the REAL reservation
  route (10 → reserve 4 → ADD 5 ⇒ bins/mirror {15,4,11}, reservation
  preserved); (c) legacy/no-bin control (quantity 42, no bins: nothing
  fabricated, legacy column intact, mirror reads its true 0 coverage).
  [TEST, PI-reported]: 13/13 focused, 27 suites / 205 dependents + A–J;
  revert-all → 11 fail / 2 pass (survivors consistent: the PROBE asserting
  current stale behavior + the tolerant legacy control). Full gate
  RUNNING at `/home/fawad/verify-2692ab1e`
  (`/home/fawad/logs/gate-2692ab1e.log`); exact changed-base audit with
  fresh coverage follows; NO final green until both resolve.

- **RESERVATION-ONLY STALE MIRROR: evidence class corrected to
  RUNTIME-CONFIRMED (Gull msg_0bba910f3970).** PI's executed probe (green
  in the focused run) asserts the concrete divergent state after a REAL
  reservation with no ADD afterward: bins {physical:10, reserved:4,
  available:6} vs stock_balances extension mirror {10, 0, 10}. This is a
  runtime-confirmed CHARACTERIZATION of the defect — not UNCONFIRMED, and
  NOT intended correct semantics. It remains a SEPARATE finding from the
  S-1 consume/release issue, UNFIXED in S-3 (no StockReservation production
  edits in the branch), and not permission for wider cleanup. The test
  comment's "UNCONFIRMED PROBE" header is mislabeled; this tracker entry
  is the authoritative record; the in-code label corrects naturally when
  the separate finding is fixed and the assertions flip to equality.

- **S-3 batched update (2026-11-17, Gull msg_cba41ac59db9): final gate
  evidence + setup-claim correction.**
  - **Gate VERIFIED at exact `2692ab1e`: 288 suites / 2320 tests, EXIT 0;
    exact changed-base fallow audit: 14 changed files, "No issues",
    EXIT 0.** Together with GLM's APPROVE of the follow-up diff, S-3 is
    now **locally verified at source+gate level; not merged**; final
    publication awaits Gull (proposed: S-3 draft stacked on the PR7
    branch AFTER an independent check of the final snapshot, normal push
    only — no force, no ready/merge).
  - **Candidate `9fd41a39`** (parent line after `2692ab1e`): diff is
    comments/test-name ONLY; production unchanged; inspected by the
    coordinator; NO full rerun required for that delta.
  - **SETUP-CLAIM CORRECTION (accurate evidence per SHA):** the retained
    `verify-2692ab1e` worktree was reported clean-untracked-0 but ACTUALLY
    carries an untracked symlink `server/node_modules ->
    /home/fawad/s3-ext/server/node_modules` (verified by GLM: `??` in
    status, symlink target confirmed). Source is unchanged and the test
    results remain observed valid; the correction is recorded so per-SHA
    evidence stays accurate. PI asked to prepare a CLEAN final `9fd41a39`
    snapshot with a REAL npm ci for the coordinator's focused
    verification — not a repeat of the full gate.
  - **Fallow default note:** a default-base fallow run showed "1 changed
    file" — likely the dependency link (the untracked node_modules
    symlink); the AUTHORITATIVE result is the exact changed-base audit
    (14 files, clean) recorded above.
  - **Reservation-only stale mirror: remains RUNTIME-CONFIRMED** (executed
    probe, bins {10,4,6} vs mirror {10,0,10}) — separate from S-1, unfixed
    in S-3, not permission for wider cleanup.
  - **Slots free**; no baseline changes, no ready/merge, no artifact
    changes. GLM follow-up role: independent check of the clean final
    snapshot when routed.
