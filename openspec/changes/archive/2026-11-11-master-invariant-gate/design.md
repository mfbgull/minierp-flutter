## Context

`server/src/__tests__/helpers/accountingInvariants.ts` defines nine accounting
invariants, A–I, behind eight collectors, plus one composer:

| | invariant | collector | in master today |
|---|---|---|---|
| A | GL balance, global + per reference group | `glImbalances` | yes |
| B, C | customer subledger; invoice `paid_amount` | `customerArImbalances` | yes |
| D | supplier subledger | `supplierApImbalances` | yes |
| E | `stock_balances` vs batch quantities | `stockImbalances` | yes |
| F | GL 1100 + 1110 vs customer balances | `arImbalances` | **no** |
| G | GL 2000 vs supplier balances | `apImbalances` | **no** |
| H | GL 1200 vs batch + legacy item values | `inventoryImbalances` | **no** |
| I | GL cash vs operational cash flows | `cashImbalances` | **no** |

`expectAllInvariantsHold` asserts A–E. F–I are asserted only by the file-local
`checkF_I` in the second describe block of `accountingInvariants.test.ts`, which
since commit `8b47a806` covers F, G, H and I. The 23 master call sites in that
file's *first* describe block, and all 3 in `invoiceCancelReturnCollision.test.ts`,
therefore never see F–I.

Two distinct inaccuracies, which must not be conflated:

- **The file header at line 18 is false** — it states `expectAllInvariantsHold`
  "asserts all nine". It asserts four.
- **The function's own docstring at line 230 is true** — "Assert invariants A–E".

Consequence, established by measurement: the purchase-return path
double-posted inventory on a clean database while the suite reported 113/113
suites and 979/979 tests green. Invariant H is the check that would have caught
it, and no master call site ran it.

**Measured baseline.** With `expect(inventoryImbalances()).toEqual([])` added to
`expectAllInvariantsHold` and nothing else changed: `113 passed, 113 total`
suites, `979 passed, 979 total` tests. **No pre-existing inventory drift is
exposed.** All 26 master call sites are already H-clean on a freshly migrated
test database. The scratch databases' −1533.20 is irrelevant: `setup.ts` gives
every run its own `mkdtemp` database and the suite never opens them.

Constraint: test-only change. Production accounting, inventory, purchase-return
and reversal behaviour are untouched — the baseline proves none needs touching.

## Goals / Non-Goals

**Goals (as landed — scope was reduced during implementation, see below):**

- `expectAllInvariantsHold(context)` asserts **A–E and H**. H is the class fix:
  it was unchecked by the master, and that is how a clean-data double-post of
  inventory reached a green suite.
- The master delegates to the existing collectors. No comparison logic is
  re-implemented, so a fix in a collector reaches every caller.
- The letter→collector mapping is documented where a reader will find it, and
  both false claims — the header's "asserts all nine" and the docstring's
  implied scope — are corrected to say what is actually asserted.
- The new coverage is shown to be load-bearing: a planted invariant-H violation
  must fail the master. A gate never observed red has not been shown to gate
  anything.

**Scope reduction, decided after implementation.** The original goal was A–I.
F, G and I were implemented and measured; adding `arImbalances` exposes the
pre-existing invariant-F violation in `docs/known-issues.md` item 6. Rather than
land a red suite, weaken F, or rename the function to dodge the question, the
master stops at H and the header names F, G and I as deferred with the blocking
finding. Landing them is sequenced work in item 5, not an open question.

**Non-Goals:**

- Not collapsing `checkF_I` / `checkF_I_core`. They are a second, partial
  taxonomy kept for failure locality within the reconciliation block. Tracked
  separately as known-issues.md item 5.
- Not repairing, migrating, or normalising the scratch databases.
- Not introducing a registry/table-driven dispatcher for the invariant list
  (see Decision 3).
- Not changing any collector's comparison logic, including the deliberate
  `Math.abs()` in `arImbalances`, which is an unresolved accounting-policy
  question and stays as documented.

## Decisions

### Decision 1 — Master gains four `expect` calls; collectors untouched

Add `arImbalances`, `apImbalances`, `inventoryImbalances` and `cashImbalances`
to the existing body, in letter order, alongside the current A–E calls.

*Rationale:* the function already reads as a flat list of assertions in letter
order. Extending the list matches the file's own idiom, keeps the diff
reviewable line-by-line, and preserves the invariant-A special case
(`glImbalances` returns a two-field object, not `Violation[]`, so it cannot be
folded into the `Violation[]` calls without reshaping it).

*Alternative considered:* reshape A into a `Violation[]` collector so all nine
are uniform. Rejected — it touches the strictest invariant in the suite for no
behavioural gain, and the double-entry check's two-part assertion
(`groups` empty AND `totalDiff` ≈ 0) is deliberate.

### Decision 2 — Correct the false claim at its source, in the header

The file header's A–I list becomes a letter→collector table. The function
docstring becomes "Assert invariants A–I".

*Rationale:* the defect is a claim, not only a behaviour. A reader who greps for
"nine" and finds "asserts all nine" beside a four-assertion body has no signal.
Making the table the source of truth means the next reader can verify the master
against it without reading both the comment and the body.

*Sub-decision:* `void context` stays, and the docstring stops implying the label
appears in the failure. Failure locality comes from the distinct literal at each
of the 26 call sites, which is already visible in the stack. Threading `context`
into the assertion messages would touch every assertion's mechanics for a
cosmetic gain; recorded as optional follow-up, not done here.

### Decision 3 — Explicit calls, not a registry

A `{letter, name, collect}[]` registry would let a test assert "the master
invokes every registered collector" structurally, closing the
added-but-not-wired gap by construction.

Rejected for this change. The guard that actually matters is behavioural — plant
drift, observe red — and it works either way. A registry adds indirection to a
120-line helper, and the failure mode it prevents (a collector nobody wired) is
already covered by the header table plus the behavioural test. If the invariant
count grows past ~12, revisit.

### Decision 4 — Anti-vacuity test mirrors the existing planted-drift test

`accountingInvariants.test.ts:1027` already establishes the pattern:
`cashImbalances detects planted GL-only drift` asserts clean, plants a
balanced `Dr cash / Cr capital` pair, asserts exactly one violation with the
expected diff, and cleans up in `finally`.

The inventory test does the same with `Dr <non-1200 account> / Cr 1200`. That
pair is internally balanced and every `journal_lines` reference group still sums
to zero, so **invariant A still passes** — only H moves, by the planted amount.
This is the strongest form of the guard: it fails for the intended reason, not
because the double-entry check tripped.

*Alternative considered:* weaken a batch's `quantity_remaining` directly to
create the gap. Rejected — it also breaks E (`stock_balances` vs batches), so the
test could pass while H was never exercised. The GL-side plant isolates H.

### Decision 5 — Scope the new tests to the helper, not the lifecycle files

New coverage lands as a describe block beside the existing planted-drift test,
using the app database via the module-level `db` singleton.

*Rationale:* the property under test is a property of the master function, and
`inventoryImbalances` reads that singleton directly. Fixture-based suites such as
`purchaseReturn.test.ts` pass an explicit fixture `db` to the model, so calling
the collector there would measure the wrong database.

## Risks / Trade-offs

- **[The master now asserts 4 more invariants at 26 call sites]** → **PARTIALLY
  REALISED. Measured at implementation time:** adding `inventoryImbalances`
  alone left the full suite green (113/113, 979/979). Adding `arImbalances`
  alongside it **fails 3 tests in `invoiceCancelReturnCollision.test.ts`** with a
  pre-existing invariant-F violation: `GL AR vs customer balances`,
  `{account: "1100", actual: 80, expected: 0, diff: 80}`.

  Confirmed pre-existing by calling `arImbalances()` directly in that file,
  bypassing the master: identical violation. Nothing in this change causes it.

  Treat it as real drift to diagnose, not as something to relax. See Open
  Questions — this is now the blocking question for the change, not a footnote.

- **[A future collector is exported but not wired into the master — the exact
  failure that produced this change]** → The header table lists all nine
  letters; the behavioural test proves H is reached rather than assumed. A
  reviewer adding a tenth letter has one obvious place to add the assertion.

- **[Overlapping assertions: F/G/H/I are now checked by both the master and
  `checkF_I`]** → Accepted. They run in different describe blocks and therefore
  never double-assert within one test. Recorded rather than collapsed, per
  Non-Goals.

- **[Only invariant H has a master-specific anti-vacuity test]** → Measured at
  implementation time: the file's one planted-drift test targets
  `cashImbalances` and calls the **collector directly**, not the master. So the
  master's new `arImbalances`, `apImbalances` and `cashImbalances` calls have no
  test proving the master reaches them; they are covered only behaviourally,
  through `checkF_I` asserting the same collectors on the same path. That is
  weaker than it looks — it is the *same* class of assumption this change exists
  to remove. Adding planted-drift tests for F, G and I is the obvious follow-up
  and is deliberately **not** bundled here: the change is already blocked on
  item 6 (invariant F), and adding an F planted test before F's own defect is
  diagnosed risks asserting the defective behaviour as correct.

- **[Reading a −1533.20 gap on a scratch database and concluding the change
  caused it]** → Stated explicitly in the proposal and in known-issues.md: the
  suite never opens those files. If a new failure appears, read the resolved
  database path before attributing cause.

- **[`checkF_I_core` omits F, G? — verify before assuming]** → At implementation
  time, confirm whether any partial composer is relying on the master *not*
  checking F–I at an intermediate checkpoint. Measured today: `checkF_I_core`
  already asserts G and I and its call sites pass, so the subset choice is about
  locality, not applicability. Re-check rather than assume.

## Migration Plan

None. Test-only, no schema, no production code, no deployment step.

Rollback is `git revert` of a single commit. Verification at implementation
time, in order: `npx tsc --noEmit`; the two affected suites; `npm run
verify:reversal-rules`; the full suite; then the mutation test — remove the
`inventoryImbalances` line from the master, confirm the new guard goes red with
the expected signed gap, restore, confirm green.

## Open Questions

- **BLOCKING — how should the newly exposed invariant-F violation be handled?**
  `invoiceCancelReturnCollision.test.ts` leaves GL 1100 at a net credit of 80
  while every customer subledger nets to zero. Measured entries on that clean
  database: `je=5` INVOICE ref=1 Dr 200 **voided** by invoice A's cancellation;
  `je=7` INVOICE ref=2 Dr 200 active; `je=9` PAYMENT ref=1 Cr 200 active;
  `je=10` INVOICE_RETURN ref=1 Cr 100 active; `je=11` RETURN_FEE ref=1 Dr 20
  active → 1100 = −80, subledger = 0, customer credit 1110 = 0. The
  operational side fully reversed invoice A; GL carries an 80 credit no ledger
  row explains. Whether the fault is the GL account chosen for an unsettled
  return, a missing customer-ledger effect, or a cancellation that should have
  been refused (`Invoice.ts:1093` guards paid invoices but did not fire) is
  **unresolved** and needs the return/settlement design read. Options: scope the
  master to A–E + H; land A–I and track the violation; or investigate F first as
  its own change. This change must not weaken F to go green.
- Should `checkF_I` / `checkF_I_core` be retired in favour of the master, or kept
  permanently for failure locality? Tracked as known-issues.md item 5; a
  deliberate follow-up, not this change. Note `checkF_I_core` omits F and H, and
  both were measured to hold at its call sites, so the subset is locality rather
  than applicability.
- Should the four dead-before-this-change collectors also be asserted by the
  lifecycle tests' own composers with per-invariant labels, so a failure names
  the letter without reading the helper? The helper's `Violation.account` field
  already carries it for F–I; A–E do not.
- Is `financial_value` safe to treat as a movement's financial value? Resolved
  in `StockMovement.ts` as *not* — it is an adjustment-leg audit field, written
  only by `postFinancialEntryForAdjustment`. Recorded so an invariant built on
  it later is not built on sand.
