## Why

`expectAllInvariantsHold(context)` is documented as asserting all nine
accounting invariants and asserts **four** (A–E). Its own docstring makes the
false claim, and 26 call sites across two files trust the name. Invariant H
(GL inventory 1200 vs stock-batch value) is the one that carries the −1533.20
class of divergence, and it reached a fully green suite — 113/113 suites,
979/979 tests — while the purchase-return path double-posted inventory on
clean data. Nothing was wrong with any individual guard; the master gate never
asked the question.

## What Changes

**Scope as landed: A–E and H.** F, G and I were implemented and measured, then
deliberately deferred — see "Scope reduction" below.

- `expectAllInvariantsHold(context)` becomes the master assertion for **A–E and
  H**, including inventory / H. It stops being A–E only.
- The specialized collectors stay exported and individually callable, unchanged
  in behaviour. They are the reusable units; the master composes them rather
  than re-implementing their logic. No collector is deleted or duplicated.
- The false "asserts all nine" header claim is corrected, and the header now
  carries a letter→collector map marking **which** the master asserts and which
  are deferred, so the master can never overclaim silently.
- New tests prove the master actually invokes H: a planted, balanced-but-wrong
  inventory posting must fail `expectAllInvariantsHold()`, and a clean state
  must pass it. This is the anti-vacuity requirement — a master assertion that
  cannot fail is the defect being fixed, so its own guard must be shown red.
- **Naming correction (recorded deliberately).** The brief for this change
  named `checkAccountingInvariants()`, `checkInventoryInvariants()` and
  `checkPaymentInvariants()` as existing specialized checks. **None of the
  three exists.** The actual architecture is eight collectors returning
  `Violation[]` — `glImbalances`, `customerArImbalances`,
  `supplierApImbalances`, `stockImbalances`, `arImbalances`, `apImbalances`,
  `inventoryImbalances`, `cashImbalances` — plus the single composer
  `expectAllInvariantsHold`. This change composes the existing collectors. It
  does not invent the three named functions, because a taxonomy invented around
  names that never existed would add a second vocabulary on top of the live one.

### Baseline (measured before authoring, not assumed)

With `expect(inventoryImbalances()).toEqual([])` added to
`expectAllInvariantsHold` and nothing else changed:

```
Test Suites: 113 passed, 113 total
Tests:       979 passed, 979 total
```

**Zero pre-existing *inventory* drift is exposed.** All 26 master call sites are
already H-clean on the freshly-migrated test database. The scratch databases'
−1533.20 is irrelevant here — `src/__tests__/setup.ts` hands every run its own
`mkdtemp` database and the suite never opens them.

**Correction, measured at implementation time (2026-10-04).** The measurement
above added **only** invariant H, because H was the question asked. The finished
master adds F, G and I as well, and adding `arImbalances` **fails 3 tests in
`invoiceCancelReturnCollision.test.ts`**:

```
GL AR vs customer balances  {account: "1100", actual: 80, expected: 0, diff: 80}
```

Pre-existing, proven by calling `arImbalances()` directly in that file and
getting the identical violation without the master involved. So the earlier
conclusion "a pure coverage and architecture change: no drift triage is
required" holds **for H only** and is **wrong as a statement about the change
as a whole**. This proposal's scope is no longer drift-free; see the blocking
question in `design.md`.

## Capabilities

### New Capabilities

None. This belongs to the existing capability below; a new capability would
fragment it.

### Modified Capabilities

- `financial-test-invariants`: adds requirements for (a) the master assertion
  composing **A–E and H** rather than A–E only, (b) deferred invariants being
  named in the header with their blocking finding rather than silently omitted,
  (c) a master/specialized split where collectors stay individually callable and
  the master delegates rather than re-implementing, (d) a regression test proving
  the master fails on a planted inventory violation, and (e) the general rule
  that asserting an invariant in the master requires a test which fails when that
  assertion is removed. Existing requirements are unchanged.

## Impact

**Test-only. No production code, no migration, no schema change, no API change.**

| File | Change |
|---|---|
| `server/src/__tests__/helpers/accountingInvariants.ts` | `expectAllInvariantsHold` composes A–I; docstring taxonomy corrected to name the collector behind each letter |
| `server/src/__tests__/accountingInvariants.test.ts` | new tests proving the master invokes H; possible delegation cleanup for the file-local `checkF_I` |
| `server/src/__tests__/invoiceCancelReturnCollision.test.ts` | affected only if master composition changes shared behaviour — expected to need no edit |

**Call sites affected:** 26 (23 in `accountingInvariants.test.ts`, 3 in
`invoiceCancelReturnCollision.test.ts`). All are covered by the baseline above.

**Out of scope, deliberately:** the file-local `checkF_I` / `checkF_I_core`
composers in `accountingInvariants.test.ts` are a second, partial
taxonomy. After this change F/G/H/I are asserted in two places. Collapsing that
is a worthwhile follow-up but is a distinct change with its own risk surface,
so it is recorded rather than bundled. Known-issues.md item 5 already tracks
it.
