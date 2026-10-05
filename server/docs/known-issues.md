# Known issues — inventory / GL integrity

Findings on inventory valuation and GL integrity, each established by
measurement. Do not rediscover these — they cost a chain of exchanges to
characterise and the numbers are easy to mis-frame.

Status per item: **OPEN** (no fix, no guard) or **FIXED** (landed, with the
guard named and the mutation that proved the guard fires). Items 1 and 4 are
fixed forward-only; neither repairs historical rows, and section
*"What is NOT fixed, by decision"* explains why that is deliberate.

A note on the scratch databases: `server/database/erp.db` and
`database/erp.db` are untracked and **the test suite never opens them** —
`src/__tests__/setup.ts` hands every run its own `mkdtemp` database. Their
divergence is therefore historical data, never a contamination risk, and it
cannot evidence current behaviour in either direction.

## 1. Invoice-return redundant adjustment leg — FIXED (forward only)

Resolved in two steps. Both are **code-only**: neither repairs historical
journal entries, and the dev-database gap is therefore unchanged.

### The duplicate COGS reversal was never a code defect

`postCOGSReversalEntry` (`accountingService.ts:1133`) has exactly **one**
caller — `invoiceReturnService.ts:403`, guarded by `if (cogsAmount > 0)`. The
current path cannot double-post. Measured: the only two `invoice_returns` rows
each have exactly one reversal, keyed to the return id.

The `je=186`/`je=192` pair is keyed to `reference_id = 45`, and **no return with
id 45 exists** — 45 is an `invoices.id`. Pre-rework rows. Same for
`je=200`/`je=206` at 49. **No code emits them; "dedupe" was the wrong
treatment.** The trap: return ids and invoice ids are independent sequences,
and void paths key by one while the posting path keys by the other — warned
about at `Invoice.ts:1028-1044` and `accountingService:1470-1486`.

### The real defect, and the fix

The invoice-side reversal posted inventory to GL **twice on fresh data**:
`postCOGSReversalEntry` (correct, at true FIFO cost) and then
`postFinancialEntryForAdjustment` (redundant, at `items.standard_cost` because
the return path sets `skipBatchCreation` so `batch_id` is null). 17 such legs
existed on the dev database, 3 misvalued (`je=156`, `je=163`, `je=184` posted
500 against reversals of 400/400/100).

`RecordMovementDTO.skipFinancialCostForwarding` (`3c1af576`) only picked the
leg's cost, so it still fired whenever `standard_cost != 0`. Replaced with
**`skipAdjustmentFinancialPosting`**, which suppresses the leg entirely.
`Invoice.ts:738` is the only setter. `unit_cost` stays on the movement for the
audit trail and `posted[]` consumers.

`posted[]` was checked and is **not** a fourth posting path: the return value
is discarded at all four call sites, and `invoiceReturnService.ts:365` uses it
only for `m.item_id` FK bookkeeping.

### Guard

`invoiceReturnAcceptance.test.ts` scenario 9 — a dedicated item with
`standard_cost = 999` (with `standard_cost = 0` the leg is dormant and the
assertion would pass without the fix). Asserts exactly one `INVOICE_RETURN`
1200 posting for that return, at the FIFO cost, and zero adjustment legs.
Scoped to its own return id: unscoped, it passes in isolation and fails in file
context, which is trap 1 below.

Verified red by reverting the source — the leg query returned **6** entries
where 0 were expected — and green after.

### What is NOT fixed, by decision

**The historical rows stay broken. This is a deliberate decision, not an
oversight — do not write a repair script for it without revisiting that
decision.**

Frozen baseline on `server/database/erp.db`, measured 2026-10-04. Note that the
database is **live** — a running server's backup scheduler rewrites it and
users record transactions against it — so treat the two stable rows as the
finding and the rest as a snapshot:

| | measured | stable? |
|---|---|---|
| **signed gap (GL 1200 − batch value)** | **−1533.20** | yes — re-measured after a later transaction, unchanged |
| `stock_adjustment` legs | 26 | yes |
| ADJUSTMENT movements with no remaining layer | 17 | yes |
| GL 1200 net | 2433.60 | no — drifted to 2146.80 |
| batch value | 3966.80 | no — drifted to 3680.00 |

The two drifting rows moved by the *same* −286.80 when a further purchase was
recorded against the live database, so the gap did not move. Incidental but
worth recording: the current code posts GL and batch together on a new
transaction. The historical rows are the residue; they are not reproduced by
new activity.

Rationale: both databases are untracked scratch (`.gitignore:51-61`) whose rows
are placeholder data, and no code path produces this shape any more — a clean
database driven through the fixed paths returns a zero gap. Repairing
placeholder data would add a migration and a script to fix rows nothing reads.

Consequences to keep in mind:

- Any figure describing what a code-only commit "does to the gap" is a
  **projection of a replay, not a measurement**. Treat the −1533.20 baseline as
  the only real number for this database.
- These rows are *not* evidence about current behaviour, in either direction.
  They cannot be used to argue a fix works, and they cannot be used to argue one
  is still needed.

## 2. Which stock table is authoritative — undocumented

`stock_batches.quantity_remaining` is what `Dashboard.ts:103-106` and `:460`
value inventory from, ungated by `feature_batch_locations`. The location table
(`batch_stock_by_location`) answers a different question — availability at a
location — and every one of its reads is flag-gated. So master is
authoritative for valuation *today*.

But `add-batch-location-model.sql` never states an intent, and seeds the flag
`'0'`. If a migration was meant to flip authority, it is unfinished and
undocumented. Data-model decision, not a bug.

## 3. Flag-on consumption falls back to legacy (migration incomplete)

With `feature_batch_locations` ON, `consumeFromOldestBatches`
(`StockMovement.ts` ~:900) takes the "no per-location coverage" fallback when a
batch has no `batch_stock_by_location` rows, and returns **`batchId: null`**.
The sale movement then carries no `batch_id`, so `Invoice.ts` ~:663 skips the
restore loop entirely.

Consequence: the flag-on restore branch is unreachable through the normal
purchase → sale → return sequence, and only via direct-insert fixtures like
`batchLocationIntegration.test.ts` 7.6. That is why this class of defect never
showed up in ordinary flows or on the scratch databases.

**Confirmed on clean data, 2026-10-04.** With `feature_batch_locations` ON, on
a freshly migrated database: purchase 20 @ 100 then sell 5. The SALE movement
carries `batch_id: null` and `unit_cost: null`, and `batch_stock_by_location`
holds **0 rows** — the purchase wrote no location coverage, so the fallback is
taken on every flag-on sale. This is structural, not a property of the scratch
rows.

Note the interaction with item 2: because no location rows are ever written,
`stock_batches.quantity_remaining` is the only populated authority and the two
sources cannot disagree *on clean data*. That is not evidence the migration is
complete — it is evidence the new table is unused.

## 4. Cost-basis forwarding for three callers — LANDED, premise corrected

`postFinancialEntryForAdjustment` re-derived cost from `items.standard_cost` and
ignored the cost the caller recorded and relieved the layer at. `3c1af576` fixed
that by forwarding `caller_unit_cost` from `RecordMovementDTO`.

### Premise correction (2026-10-04)

> **Reading `git log 3c1af576` alone will mislead you.** That commit message
> states "the adjustment leg IS the GL posting" for `PurchaseReturn.ts:443`,
> `PurchaseReturn.ts:638` and `Production.ts:627`, and reports a +700.00 effect
> on the GL-vs-batch gap. **That claim is superseded for the two
> `PurchaseReturn` callers** — see below. Only the `Production.ts` claim
> survives. The commit is left unamended on purpose: it is immutable history and
> rewriting it would destroy the record of the wrong turn. This section is the
> correction that `git log` cannot show you.

`3c1af576` asserted that for `PurchaseReturn.ts:443`, `PurchaseReturn.ts:638`
and `Production.ts:627` "the adjustment leg *is* the GL posting". **That holds
for `Production.ts` only.** On the two `PurchaseReturn` callers it was false,
and the file's own header said so: `PurchaseReturn.ts:28` documents that GL
posting "reuses `AccountingService.postPurchaseReturnEntry` (Dr AP / Cr
Inventory)", called at `:559` in the same transaction as `recordMovement` at
`:438`. The adjustment leg was therefore always a **duplicate** credit, not the
posting.

Measured on a clean database — purchase 10 @ layer cost 50 with
`items.standard_cost = 400`, return 3 units:

| state | 1200 leg from the movement | GL 1200 vs batch gap |
|---|---|---|
| `3c1af576` reverted | credit **1200** (3 × standard_cost) | **−1200** |
| `3c1af576` as landed | credit **150** (3 × layer cost) | **−150** |

Two credits for one return: `je=8` `stock_adjustment` and `je=9`
`PURCHASE_RETURN`, 150 each, against 150 of inventory that actually left
(batch 10 → 7).

So `3c1af576` **narrowed** the double-post on these two callers without
eliminating it. It remains correct for `Production.ts:594`/`:620`, which has
no second poster.

### The fix

`skipAdjustmentFinancialPosting` — the mechanism item 1 introduced — is now set
at `PurchaseReturn.ts:438` (create) and `:635` (void). Both sides are required:
`voidReturn` reverses the `PURCHASE_RETURN` entry via
`voidJournalLinesByReference`, so suppressing only create would leave the void
debiting inventory twice.

Option considered and rejected: drop the 1200 line from
`postPurchaseReturnEntry`. It owns the AP leg and the void-reversal symmetry
that makes the void path work.

### Guards

- `accountingInvariants.test.ts` scenario 13 — drives a real purchase then a
  purchase return on the app database, with `standard_cost = 400` against layer
  cost 50 so the leg is not dormant, then voids it. Asserts the invariant after
  each of the three steps, zero adjustment legs on the return's movement, and
  exactly one `PURCHASE_RETURN` credit at 150. Verified red on the unfixed tree
  (`diff: -150`), red again with only the create suppression removed
  (`diff: -150`), and red with only the void suppression removed
  (`diff: 150`).
- `purchaseReturn.test.ts` — "credits inventory once per return, at the source
  batch cost". This replaces the `3c1af576` guard, which asserted the leg
  credited 40 and therefore failed once the leg was suppressed. The replacement
  asserts the stronger property: no adjustment leg, and one authoritative
  `PURCHASE_RETURN` credit at the layer cost (40, not the 160 that
  `standard_cost` would have produced). Verified red with the suppression
  reverted.

### Do not reuse the old figures

The earlier "GL 1200 rises 700.00, gap −1533.20 → −833.20" was a **projection of
a replay**, not a measurement: it was computed against the unrepaired scratch
rows that item 1 leaves alone, on a database the test suite never opens. It is
retained nowhere as a result.

## 5. `expectAllInvariantsHold` covers A–E and H; F, G, I deferred

**Partly resolved.** The master used to assert four invariants (A–E) while being
documented as asserting nine. It now asserts six — **A–E and H** — and the
header carries a letter→collector map stating exactly that. F, G and I are
reached only by `checkF_I` inside `accountingInvariants.test.ts`.

Current coverage:

| invariant | asserted by |
|---|---|
| A–E, H | `expectAllInvariantsHold` (26 call sites) |
| F (AR), G (AP), I (cash) | `checkF_I` in `accountingInvariants.test.ts` only |

**Why F, G and I are not in the master yet.** They were implemented and
measured. Adding `inventoryImbalances` alone leaves the suite green; adding
`arImbalances` **exposes a real pre-existing violation of invariant F on clean
data** — see item 6. A gate that fails is not a gate, so the master stops at H
and the helper's header says so explicitly rather than claiming all nine.

**Do not "fix" this by deleting the H assertion, by weakening F, or by renaming
the function to match its scope.** Those are pattern 4 below with extra steps.
The remaining work is sequenced, not optional:

1. Fix item 6 (the credit settlement's missing GL leg).
2. Add `arImbalances`, `apImbalances` and `cashImbalances` to the master.
3. Land a planted-drift test for each. None exists today — the file's single
   planted-drift test targets `cashImbalances` and calls the **collector
   directly**, so the master's F, G and I calls would ship unproven. That is the
   same class of assumption this item exists to remove.

Step 3 is easy to skip and must not be. Add them with their own anti-vacuity
proofs, the way H got one.

## 6. Invariant F violated on clean data — GL AR and the customer subledger disagree

**Status: OPEN, no fix. Found 2026-10-04 by wiring invariant F into
`expectAllInvariantsHold`; the wiring is what made it visible.**

`arImbalances()` returns, on the freshly-migrated database used by
`invoiceCancelReturnCollision.test.ts`:

```
GL AR vs customer balances  {account: "1100", actual: 80, expected: 0, diff: 80}
```

GL 1100 carries a **net credit of 80** while every customer's
`current_balance` is 0 and every `customer_ledger` net is 0. Account 1110
(Customer Credit) is also 0, so the 80 is not held as store credit either.

Non-voided 1100 lines at the first checkpoint, as measured:

| entry | effect on 1100 | state |
|---|---|---|
| `je=5` INVOICE ref=1 | Dr 200 | **voided** by the cancellation of invoice A |
| `je=7` INVOICE ref=2 | Dr 200 | active |
| `je=9` PAYMENT ref=1 | Cr 200 | active |
| `je=10` INVOICE_RETURN ref=1 | Cr 100 | active |
| `je=11` RETURN_FEE ref=1 | Dr 20 | active |

Net −80.

### Diagnosis: the credit settlement's GL side never posted

Measured `customer_ledger` at the same checkpoint — the subledger is fully
consistent and nets to zero, so the fault is **entirely on the GL side**:

| id | customer | type | reference | Dr | Cr |
|---|---|---|---|---|---|
| 1 | 1 | INVOICE | INV-1026-00001 | 200 | |
| 2 | 2 | INVOICE | INV-1026-00002 | 200 | |
| 3 | 2 | PAYMENT | PAY-1026-00001 | | 200 |
| 4 | 2 | RETURN | RET-1026-00001 | | **80** |
| 5 | 2 | **CREDIT** | **CR-1026-00001** | **80** | |
| 6 | 1 | CANCELLATION | INV-1026-00001 | | 200 |

Customer 1: 200 − 200 = 0. Customer 2: 200 − 200 − 80 + 80 = 0.

The return (`invoice_returns.id=1`, `invoice_id=2`, status **Settled**,
`returned_amount` 100, `fee_amount` 20, `net_amount` 80, `settled_amount` 80)
produced **two** ledger rows: a RETURN credit of 80 and a consuming CREDIT debit
of 80. Row 5 is the settlement extinguishing that credit in the subledger.

**Row 5 has no journal entry.** `postCreditOffsetEntry` posts `Dr 1110 /
Cr 1100` per the H9 model in `models/AGENTS.md`; it did not run. Proof by
exhaustion: the entry list filtered to accounts 1100 and 1110 contains exactly
`je=5, 7, 9, 10, 11` — no credit-offset entry — and 1110's balance is 0.

So the subledger moved 80 from RETURN to CREDIT, and the GL left the 80 sitting
as a credit on 1100. That is the whole of the 80.

Three candidate explanations were considered and **all three are now excluded**:

1. ~~Return posts AR to 1100 where H9 says store credit belongs on 1110~~ —
   excluded: the subledger *did* record the return and its settlement. The
   accounts chosen on the subledger side are consistent.
2. ~~Return emits GL with no matching ledger row~~ — excluded: rows 4 and 5 are
   exactly that matching pair.
3. ~~Cancellation should have been refused~~ — excluded: invoice 1 has
   `paid_amount = 0`, so `Invoice.ts:1093` correctly did not fire. The payment
   belongs to invoice 2 (`payment: 'full'`).

**Remaining question, and it is narrow:** why did `postCreditOffsetEntry` not
post for this settlement? The subledger write happened, so the credit-offset
consumer recorded its ledger effect and skipped — or was never called for —
the GL half. Note the test asserts the current 1100 behaviour as intended
(`accountTotals('INVOICE_RETURN', returnId, '1100').credit ≈ 100`), so the
return's own posting is deliberate; it is the **settlement's** missing GL leg
that is unaccounted for.

This is the same family as the orphaned-GL tooling that already exists
(`repair-orphaned-ledger.ts`, `void-orphaned-salary-gl.ts`) — a ledger row
without its journal entry. It was invisible for the reason in pattern 4: no
assertion computed invariant F on this path.

Evidence that it predates the invariant wiring: calling `arImbalances()`
directly in that file, with the master not involved, returns the identical
violation.

---

# Validating a guard before trusting it

Five failure modes caught while producing this file. All are checks that
*felt* sufficient and were not.

## 1. Run guards in file context, not just targeted

The item-4 guard passed when run with `-t` and failed in the full file. It
hardcoded `item_id = 1`, but `seedPurchase` allocates item ids from a
module-level counter, so the id is only 1 when that test runs first. Every
other assertion still held; only the fixture's premise was wrong.

**Run the guard (a) targeted, (b) with the whole file, and (c) against the
unfixed source.** A targeted green is the weakest of the three. A guard that
only passes in isolation is worse than no guard, because it reads as coverage.

## 2. Ask what the number measures before asking whether the conclusion is nice

`−1700` was `ABS(quantity) × (unit_cost − standard_cost)` — the signed change
in a posted GL amount. It was reported as a divergence contribution, and on its
own would have justified a commit. The actual GL-vs-batch gap on that database
was **−1533.20**, a different quantity with a different sign.

Before a number supports a conclusion, confirm the query computes the thing the
conclusion is about. This is read-only and takes one query.

## 3. Prove the guard can fail

Every landed fix here was checked by reverting the source and confirming the
guard goes red with the *right* number (`Expected 10, Received 6`;
`Expected 40, Received 160`). A guard never observed red has not been shown to
guard anything — the pre-audit `cashImbalances` helper and the stale
scenario-10 skip were both accepted in the earlier report on the strength of
passing tests.

## 4. A green suite that never asks the question

The strongest of these, because no amount of re-running finds it.

`expectAllInvariantsHold` is documented as asserting nine invariants and
asserts **four** (A–E). `inventoryImbalances` — GL 1200 vs batch value — had
**zero call sites in the entire suite**. So the one invariant carrying the
−1533.20 class of divergence was never checked, on any database, by any test.

113/113 suites and 978/978 tests passed *while the purchase-return path
double-posted inventory on clean data* (item 4). Nothing was wrong with any
guard; the question simply was not on the sheet. `checkF_I` even carried a
comment explaining why it skipped inventory — the skip looked deliberate and
justified, which is what made it durable.

Generalisation: **a passing suite bounds the questions it asks.** When a number
matters, confirm some assertion actually computes it — grep for the checker's
call sites, and treat "exported but never called" as "not implemented". Adding
the missing assertion is worth more than any single fix: it is the difference
between closing one bug and closing the class.

Corollary for reviewing green output: "suite green" answers "did anything
already asserted break?" It cannot answer "is the thing I care about correct?"
Only a check on that specific quantity can.

## 5. Whoever writes the next artifact has to read the code first

This one is not specific to agents, and recording it as such would be
self-flattery. **Read the code before asserting a fact about it — and that
applies to the author of the prompt, not only the author of the fix.**

The chain that produced this file contained seven falsified premises. Six were
caught by the implementer after it had already stated a conclusion. The seventh
was in the **verification brief itself**: it asserted that "all verification to
date ran against scratch DBs with pre-existing divergence", which was false.
`src/__tests__/setup.ts` has always created a `mkdtemp` database per run, so
every green suite result had *already* been a clean-database result. The brief
also inherited the stale `+25` claim as a live open question. Both errors were
found in the first ten minutes of executing against it — by reading
`setup.ts`, which the brief had not required.

The pattern is not "agents assert too confidently". It is that a plausible
premise, inherited from a summary, survives unexamined until something forces
a check. Author and artifact type make no difference — prompt, fix, guard, doc,
or commit message all fail the same way. The mitigation is the same in every
case: before a claim about code is written down, open the file and confirm it.
Cheap, and it is the only thing that has ever worked here.

