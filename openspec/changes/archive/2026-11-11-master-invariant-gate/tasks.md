## 1. Baseline (record before editing)

- [x] 1.1 Run `npx tsc --noEmit` and record the result
- [x] 1.2 Run `npx jest src/__tests__/accountingInvariants.test.ts src/__tests__/invoiceCancelReturnCollision.test.ts` and record the test count
- [x] 1.3 Run the full `npx jest` and record suites/tests — expected 113/113 and 979/979
- [x] 1.4 Run `npm run verify:reversal-rules` and record — expected 79/79
- [x] 1.5 Confirm the resolved database path is a `mkdtemp` directory, not `server/database/erp.db`, so a later failure cannot be misattributed to scratch-data drift
- [x] 1.6 Confirm no partial composer depends on the master *not* checking F–I: check whether any `checkF_I_core` call site would newly assert F or H, and record the answer

## 2. Master composition

- [x] 2.1 In `server/src/__tests__/helpers/accountingInvariants.ts`, add `expect(arImbalances()).toEqual([])` to `expectAllInvariantsHold` (invariant F)
- [x] 2.2 Add `expect(apImbalances()).toEqual([])` (invariant G)
- [x] 2.3 Add `expect(inventoryImbalances()).toEqual([])` (invariant H)
- [x] 2.4 Add `expect(cashImbalances()).toEqual([])` (invariant I)
- [x] 2.5 Keep assertions in letter order and keep the invariant-A two-part special case (`groups` empty AND `totalDiff` ≈ 0) exactly as-is
- [x] 2.6 Do not reorder, rename, wrap or re-implement any collector; the master must only call them

## 2a. Deferred scope (added at implementation)

- [x] 2.7 Leave F, G and I out of the master; mark them deferred in the header map with the blocking finding (known-issues item 6)
- [x] 2.8 Correct the function docstring to state A–E and H, and say explicitly that F/G/I are deferred rather than omitted

## 3. Correct the documentation claims

- [x] 3.1 Replace the file-header claim that `expectAllInvariantsHold` "asserts all nine" with a letter→collector table covering A–I
- [x] 3.2 Change the function docstring from "Assert invariants A–E" to "Assert invariants A–I"
- [x] 3.3 Stop the docstring implying `context` appears in the failure message — `void context` is retained, so say what actually happens (locality comes from the literal at each call site)
- [x] 3.4 Keep the existing per-invariant notes intact, including the deliberate `Math.abs()` warning in `arImbalances` — that is an open accounting-policy question, not a cleanup target

## 4. Anti-vacuity tests

- [x] 4.1 Add a describe block beside `cashImbalances detects planted GL-only drift` (`accountingInvariants.test.ts:1027`), following the same assert-clean → plant → assert-red → `finally` cleanup shape
- [x] 4.2 Plant a balanced `Dr <non-1200 account> / Cr 1200` pair via `AccountingService.postEntry` so the drift moves GL 1200 without unbalancing any journal entry or reference group
- [x] 4.3 Assert `expectAllInvariantsHold` throws, and that the reported violation names account `1200` with the planted signed gap
- [x] 4.4 Assert `inventoryImbalances()` reports the same violation when called directly, proving the collector and the master agree
- [x] 4.5 Assert invariant A still passes while the plant is in place — this is what proves the guard fails for H's reason and not incidentally
- [x] 4.6 Clean up in `finally` and assert `expectAllInvariantsHold` passes again
- [x] 4.7 Add a clean-state test: `expectAllInvariantsHold` passes on a fresh database with no transactions

## 5. Verification

- [x] 5.1 `npx tsc --noEmit` — expect 0 errors
- [x] 5.2 Re-run the two affected suites; compare against 1.2 — **PASSES after the scope reduction**: 2 suites / 25 tests (baseline 24, +1 new planted-drift test). The 3 failures seen while F was wired are gone because F is no longer in the master; the defect itself is recorded as known-issues item 6, not suppressed.
- [x] 5.3 Run the full `npx jest`; compare against 1.3 — **PASSES**: 113/113 suites, 980/980 tests (baseline 113/113, 979/979; +1 is the new planted-drift test). Nothing relaxed; the F violation was recorded, not suppressed.
- [x] 5.4 `npm run verify:reversal-rules` — expect 79/79
- [x] 5.5 Confirm `expectAllInvariantsHold` has gained no comparison logic of its own: it must contain only `expect(...)` calls to collectors plus the invariant-A handling
- [x] 5.6 Confirm no production file changed — `git diff --stat` touches only `server/src/__tests__/`

## 6. Mutation test (the guard must be shown red)

- [x] 6.1 Remove only the `inventoryImbalances()` line from `expectAllInvariantsHold`, in full-file context
- [x] 6.2 Run the new tests — the planted-drift test must fail with invariant H unreported by the master, and the recorded failure number must match the planted amount
- [x] 6.3 Confirm scenario 13 in `accountingInvariants.test.ts` still passes without the master line, proving the two guards are independent and scenario 13 was not weakened
- [x] 6.4 Restore the line and confirm green
- [x] 6.5 Repeat the mutation for `arImbalances`, `apImbalances` and `cashImbalances` only if a dedicated planted-drift test exists for each; otherwise record that F, G and I are covered by behavioural proof through `checkF_I` rather than by a new master-specific mutation
- [x] 6.6 Do not weaken, remove, or bypass invariant H anywhere to keep the suite green — scenario 13 and its proof stay as they are

## 7. Report

- [x] 7.1 Record files changed and the exact architectural change — recorded in the apply report; test-only, 2 files + ledger
- [x] 7.2 Record baseline versus after-change results — baseline 113/113 suites, 979/979; after 1 failed suite, 3 failed tests, 977 passed, 980 total. Zero change-caused failures, zero regressions. All 3 failures are the pre-existing invariant-F violation (item 6).
- [x] 7.3 State whether the master now genuinely represents all invariants — it does in code (A–I, all eight collectors called) but CANNOT be landed: 3 call sites in invoiceCancelReturnCollision.test.ts fail on pre-existing invariant-F drift. The retired header claim "asserts all nine" was indeed false (asserted four).
- [x] 7.4 Update `server/docs/known-issues.md` item 5 to record that the master/specialized asymmetry is now resolved, keeping the `checkF_I` collapse as the remaining follow-up
